import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { ChatTurn, CoachModel } from '../coach/chat.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';

const turn = z.object({ role: z.enum(['member', 'coach']), text: z.string().trim().min(1).max(600) });
const body = z.object({
  turns: z.array(turn).min(1).max(30),
  context: z
    .object({
      goal: z.string().max(40).optional(),
      level: z.string().max(40).optional(),
      sessionMinutes: z.number().int().min(10).max(240).optional(),
      equipment: z.array(z.string().max(40)).max(80).optional(),
      readiness: z.string().max(60).optional(),
      todayPlanned: z.string().max(80).optional(),
      method: z.string().max(40).optional(),
    })
    .default({}),
});

/** Messages the model sees: the last 12, starting with the member, same-role turns merged (the API alternates roles). */
export const modelTurns = (turns: ChatTurn[]): ChatTurn[] => {
  const out: ChatTurn[] = [];
  for (const t of turns.slice(-12)) {
    if (out.length === 0 && t.role === 'coach') continue;
    const last = out.at(-1);
    if (last && last.role === t.role) last.text += `\n${t.text}`;
    else out.push({ ...t });
  }
  return out;
};

/**
 * Workout chat (#381): POST /v1/me/coach-chat. Daily cap per member bounds the spend; Pro once subscriptions are
 * enforced (open while they are off, like generated workouts).
 */
export const coachChatRoutes = (
  r: FastifyInstance,
  db: DB,
  now: () => Date,
  coach: CoachModel | undefined,
  dailyLimit: number,
  hasAccess: (userId: string) => boolean,
) => {
  const usedToday = (userId: string) =>
    (db.prepare('SELECT count FROM coach_chat_usage WHERE user_id = ? AND day = ?').get(userId, now().toISOString().slice(0, 10)) as
      | { count: number }
      | undefined)?.count ?? 0;

  /** Whether the chat is switched on, and messages left today. */
  r.get('/me/coach-chat', async (req) => ({ available: !!coach, remainingToday: Math.max(0, dailyLimit - usedToday(req.userId!)) }));

  r.post('/me/coach-chat', async (req) => {
    if (!coach) throw new ApiError(503, 'coach_unavailable', 'Coach chat is not available right now.');
    if (!hasAccess(req.userId!)) throw new ApiError(402, 'pro_required', 'Coach chat is part of MonkeyWorkout Pro.');
    const b = body.parse(req.body);
    const turns = modelTurns(b.turns);
    if (turns.at(-1)?.role !== 'member') throw new ApiError(400, 'bad_request', 'The last message must be from the member.');
    const day = now().toISOString().slice(0, 10);
    const used = usedToday(req.userId!);
    if (used >= dailyLimit) throw new ApiError(429, 'daily_limit', `That's ${dailyLimit} messages today. Coach is back tomorrow!`);
    let answer;
    try {
      answer = await coach(turns, b.context);
    } catch (e) {
      req.log.warn(`coach chat failed: ${(e as Error).message}`);
      throw new ApiError(502, 'coach_failed', 'Coach is catching breath. Try again in a moment.');
    }
    // Counted once answered: a failed call doesn't use up the member's messages.
    db.prepare(
      `INSERT INTO coach_chat_usage (user_id, day, count) VALUES (?, ?, 1)
       ON CONFLICT(user_id, day) DO UPDATE SET count = count + 1`,
    ).run(req.userId!, day);
    return { ...answer, remainingToday: Math.max(0, dailyLimit - used - 1) };
  });
};
