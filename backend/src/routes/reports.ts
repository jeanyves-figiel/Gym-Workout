import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Fetch } from '../appleTokens.ts';
import { sanitizeJpeg } from '../community/image.ts';
import { type DB, tx } from '../db.ts';
import { ApiError } from '../errors.ts';
import type { Mailer } from '../mailer.ts';

/**
 * Member problem reports (#467, design A + B + C from `report-problem/proposals.png`): the Report a problem page,
 * shake to report, and Report on errors all post here. Stored privately and emailed to the team with screenshots.
 * When GITHUB_REPORTS_TOKEN is set a GitHub issue (label member-report) is opened too: it carries the member's words
 * and app facts only, never their name, email, account id or screenshots.
 */
const KINDS = { bug: 'Bug', broken: 'Not working right', idea: 'Idea' } as const;

const report = z.object({
  kind: z.enum(['bug', 'broken', 'idea']),
  area: z.string().trim().min(1).max(40),
  text: z.string().trim().min(1).max(4000),
  screen: z.string().trim().max(80).nullish(),
  error: z.string().trim().max(500).nullish(),
  via: z.enum(['settings', 'shake', 'error']).default('settings'),
  app: z.object({
    version: z.string().max(20),
    build: z.string().max(20),
    os: z.string().max(40),
    device: z.string().max(60),
    locale: z.string().max(20).nullish(),
  }),
  /** Base64 JPEGs, ≤ 1024 px per side and 512 KB each; EXIF stripped here. */
  screenshots: z.array(z.string().max(720_000)).max(3).default([]),
});

export type ReportsConfig = { githubToken?: string; githubRepo: string };

interface Row {
  id: string;
  data: string;
  issue_number: number | null;
  created_at: string;
}

export const reportExport = (db: DB, userId: string) =>
  (db.prepare('SELECT id, data, issue_number, created_at FROM member_reports WHERE user_id = ? ORDER BY created_at').all(userId) as unknown as Row[]).map(
    (r) => ({ id: r.id, ...(JSON.parse(r.data) as object), issueNumber: r.issue_number, createdAt: r.created_at }),
  );

/** Public issue text: email addresses and phone-like numbers the member typed are removed. */
const redact = (s: string) => s.replace(/[^\s@]+@[^\s@]+\.[^\s@]+/g, '[email removed]').replace(/\+?\d[\d ()-]{7,}\d/g, '[number removed]');

const oneLine = (s: string) => s.replace(/\s+/g, ' ').slice(0, 70);

const facts = (b: z.infer<typeof report>) =>
  [
    `Type: ${KINDS[b.kind]}`,
    `Area: ${b.area}`,
    b.screen ? `Screen: ${b.screen}` : undefined,
    `Sent from: ${b.via}`,
    `App: ${b.app.version} (${b.app.build}) · ${b.app.os} · ${b.app.device}${b.app.locale ? ` · ${b.app.locale}` : ''}`,
    b.error ? `Error: ${b.error}` : undefined,
  ].filter(Boolean) as string[];

export const reportRoutes = (
  r: FastifyInstance,
  deps: { db: DB; now: () => Date; mailer: Mailer; to?: string; fetch: Fetch; config: ReportsConfig; log: (m: string) => void },
) => {
  const { db, now } = deps;

  const openIssue = async (id: string, b: z.infer<typeof report>, shots: number): Promise<number | null> => {
    if (!deps.config.githubToken) return null;
    const res = await deps.fetch(`https://api.github.com/repos/${deps.config.githubRepo}/issues`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${deps.config.githubToken}`,
        accept: 'application/vnd.github+json',
        'content-type': 'application/json',
        'user-agent': 'MonkeyWorkout-reports',
      },
      body: JSON.stringify({
        title: `[${KINDS[b.kind]}] ${b.area}: ${oneLine(redact(b.text))}`,
        body: [
          '**Member report** (in-app)',
          '',
          ...facts(b).map((f) => `- ${f}`),
          `- Screenshots: ${shots} (sent to the team by email)`,
          `- Report id: \`${id}\``,
          '',
          '---',
          '',
          b.text.replace(/@/g, '@​'),
        ].join('\n'),
        labels: ['member-report', b.kind === 'idea' ? 'enhancement' : 'bug'],
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) throw new Error(`GitHub issue failed: HTTP ${res.status}`);
    return ((await res.json()) as { number: number }).number;
  };

  r.post(
    '/me/reports',
    { bodyLimit: 2_400_000, config: { rateLimit: { max: 10, timeWindow: '1 hour' } } },
    async (req, reply) => {
      const b = report.parse(req.body);
      // Nowhere to deliver it: refuse before storing, so the app's retry or the member's email doesn't duplicate it.
      if (!deps.to && !deps.config.githubToken)
        throw new ApiError(503, 'reports_off', 'Reports are not switched on. Please email us from Settings → Support.');
      const shots = b.screenshots.map((s) => sanitizeJpeg(Buffer.from(s, 'base64')).data);
      const id = randomUUID();
      const ts = now().toISOString();
      const { screenshots: _s, ...data } = b;
      tx(db, () => {
        db.prepare('INSERT INTO member_reports (id, user_id, data, created_at) VALUES (?, ?, ?, ?)').run(id, req.userId!, JSON.stringify(data), ts);
        const put = db.prepare('INSERT INTO member_report_shots (id, user_id, report_id, data, created_at) VALUES (?, ?, ?, ?, ?)');
        for (const s of shots) put.run(randomUUID(), req.userId!, id, s, ts);
      });

      let issue: number | null = null;
      try {
        issue = await openIssue(id, b, shots.length);
        if (issue) db.prepare('UPDATE member_reports SET issue_number = ? WHERE id = ?').run(issue, id);
      } catch (e) {
        deps.log(`report ${id}: ${(e as Error).message}`);
      }
      if (deps.to) {
        const user = db.prepare('SELECT email FROM users WHERE id = ?').get(req.userId!) as { email: string } | undefined;
        await deps.mailer
          .send({
            to: deps.to,
            subject: `Member report · ${KINDS[b.kind]} · ${b.area}${issue ? ` · #${issue}` : ''}`,
            text: [
              `From: ${user?.email ?? 'unknown'} (account ${req.userId})`,
              ...facts(b),
              issue ? `GitHub: https://github.com/${deps.config.githubRepo}/issues/${issue}` : undefined,
              `Report id: ${id}`,
              '',
              b.text,
            ]
              .filter((l) => l !== undefined)
              .join('\n'),
            attachments: shots.map((content, i) => ({ filename: `screenshot-${i + 1}.jpg`, contentType: 'image/jpeg', content })),
          })
          .catch((e: Error) => deps.log(`report ${id} mail: ${e.message}`));
      } else if (!issue) {
        // Stored, so it's not lost (the team reads member_reports); answering an error would only make the app retry.
        deps.log(`report ${id}: stored but not delivered (GitHub failed, no mail address)`);
      }
      return reply.status(201).send({ id, issueNumber: issue });
    },
  );
};
