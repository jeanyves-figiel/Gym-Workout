import { createHash, createPrivateKey, sign } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

/**
 * Over-the-air config and content (#583). App Review 2.5.2 forbids downloaded code, so only data changes ship this way:
 * feature flags / kill switches, remote values, minimum and recommended build, and content packs (catalogues, notes).
 * Everything lives in `content/` in the repository: edit → PR → staging → Promote to production (same image).
 */

/** Packs the app knows how to read; each replaces its bundled file on the next launch. */
export const PACKS = ['recipes', 'foods', 'whats-new', 'coach-tips'] as const;
export type PackName = (typeof PACKS)[number];

const build = z.number().int().min(0);
const key = z.string().regex(/^[a-zA-Z][\w.-]{0,47}$/, 'Keys: letters, digits, . _ -, start with a letter');

/** A flag is on for builds in [minBuild, maxBuild] and `percent` of installs (bucketed on the device). */
const flag = z
  .object({
    on: z.boolean(),
    minBuild: build.optional(),
    maxBuild: build.optional(),
    percent: z.number().min(0).max(100).optional(),
    /** Shown on the "paused" card when the flag is off. */
    message: z.string().max(200).optional(),
  })
  .strict();

export const remoteConfigSchema = z
  .object({
    /** Builds below this see the required update screen. */
    minimumBuild: build.default(0),
    /** Builds below this see the update banner on Train. */
    recommendedBuild: build.default(0),
    update: z
      .object({
        title: z.string().min(1).max(60),
        body: z.string().min(1).max(200),
        /** Where Update opens; the app defaults to TestFlight (before the App Store launch). */
        url: z.string().regex(/^(https|itms-apps|itms-beta):\/\/\S*$/).optional(),
      })
      .strict()
      .optional(),
    flags: z.record(key, flag).default({}),
    values: z.record(key, z.json()).default({}),
    packs: z.partialRecord(z.enum(PACKS), z.object({ minBuild: build.optional(), maxBuild: build.optional() }).strict()).default({}),
  })
  .strict();
export type RemoteConfig = z.infer<typeof remoteConfigSchema>;

const idList = z.array(z.looseObject({ id: z.string().min(1) })).min(1);
/** Light shape checks; the app decodes fully and keeps its bundled copy when a pack doesn't decode. */
const packShape: Record<PackName, z.ZodType> = {
  recipes: idList,
  foods: idList,
  'whats-new': z.looseObject({ id: z.string().min(1), items: z.array(z.looseObject({ title: z.string(), body: z.string() })).min(1) }),
  'coach-tips': z
    .array(
      z
        .object({
          id: key,
          text: z.string().min(1).max(120),
          /** Two RGB hex colours for the gradient, e.g. ["3D5AFF", "1E9BFF"]. */
          tint: z.tuple([z.string().regex(/^[0-9A-Fa-f]{6}$/), z.string().regex(/^[0-9A-Fa-f]{6}$/)]).optional(),
          cta: z.string().min(1).max(30),
          /** In-app destination of the tip's button. */
          action: z.enum(['progress', 'calendar', 'levels']),
          minBuild: build.optional(),
          maxBuild: build.optional(),
        })
        .strict(),
    )
    .min(1),
};

export interface Pack {
  name: PackName;
  sha256: string;
  body: Buffer;
  minBuild?: number;
  maxBuild?: number;
}

export interface RemoteContent {
  /** Exact `/v1/app-config` body: signed and hashed as bytes. */
  body: string;
  etag: string;
  signature?: string;
  packs: Map<PackName, Pack>;
}

const sha256 = (b: Buffer | string) => createHash('sha256').update(b).digest('hex');

/** Reads and checks `dir`; throws with the first problem (CI runs this on the real folder). */
export const loadRemoteContent = (dir: string, signingKey?: string): RemoteContent => {
  const file = join(dir, 'config.json');
  const cfg = remoteConfigSchema.parse(existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {});
  if (cfg.minimumBuild > 0 && !cfg.update) throw new Error('minimumBuild needs update title and body');
  const packs = new Map<PackName, Pack>();
  for (const [name, range] of Object.entries(cfg.packs) as [PackName, { minBuild?: number; maxBuild?: number }][]) {
    const path = join(dir, 'packs', `${name}.json`);
    if (!existsSync(path)) throw new Error(`Pack ${name} listed but packs/${name}.json is missing`);
    const body = readFileSync(path);
    const parsed = packShape[name].safeParse(JSON.parse(body.toString('utf8')));
    if (!parsed.success) throw new Error(`Pack ${name}: ${parsed.error.issues[0]?.message} at ${parsed.error.issues[0]?.path.join('.')}`);
    packs.set(name, { name, sha256: sha256(body), body, ...range });
  }
  const payload = {
    minimumBuild: cfg.minimumBuild,
    // A required build is also a recommended one.
    recommendedBuild: Math.max(cfg.recommendedBuild, cfg.minimumBuild),
    update: cfg.update ?? null,
    flags: cfg.flags,
    values: cfg.values,
    packs: [...packs.values()].map((p) => ({
      name: p.name,
      sha256: p.sha256,
      bytes: p.body.length,
      minBuild: p.minBuild ?? null,
      maxBuild: p.maxBuild ?? null,
      url: `/v1/packs/${p.name}/${p.sha256}`,
    })),
  };
  const version = sha256(JSON.stringify(payload)).slice(0, 16);
  const body = JSON.stringify({ version, ...payload });
  const signature = signingKey
    ? sign(null, Buffer.from(body), createPrivateKey({ key: Buffer.from(signingKey, 'base64'), format: 'der', type: 'pkcs8' })).toString('base64')
    : undefined;
  return { body, etag: `"${version}"`, signature, packs };
};

/** Public: the app asks before sign-in (the required update screen must show to signed-out builds too). */
export const remoteRoutes = (app: FastifyInstance, dir: string, signingKey: string | undefined, log: (m: string) => void) => {
  let content: RemoteContent;
  try {
    content = loadRemoteContent(dir, signingKey);
  } catch (e) {
    // CI checks the folder (remote.test.ts), so this is a broken key or volume: serve nothing, the app keeps what it has.
    log(`Remote content not served: ${(e as Error).message}`);
    content = loadRemoteContent(join(dir, '__none__'));
  }
  const limit = { config: { rateLimit: { max: 120, timeWindow: '1 minute' } } };

  app.get('/v1/app-config', limit, async (req, reply) => {
    reply.header('etag', content.etag).header('cache-control', 'public, max-age=300');
    if (content.signature) reply.header('x-content-signature', content.signature);
    if (req.headers['if-none-match'] === content.etag) return reply.status(304).send();
    return reply.type('application/json').send(content.body);
  });

  app.get('/v1/packs/:name/:sha', limit, async (req, reply) => {
    const { name, sha } = req.params as { name: string; sha: string };
    const pack = content.packs.get(name as PackName);
    if (!pack || pack.sha256 !== sha) return reply.status(404).send({ error: 'not_found', message: 'No such pack.' });
    return reply.header('cache-control', 'public, max-age=31536000, immutable').type('application/json').send(pack.body);
  });
};
