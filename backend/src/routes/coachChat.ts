import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { ChatTurn, CoachModel } from '../coach/chat.ts';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';
import { inFlight, refundAiCall, reserveAiCall } from '../quota.ts';

const MAX_PHOTO = 1_500_000;

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
      screen: z.string().max(40).optional(),
      focus: z.string().max(300).optional(),
      pronouns: z.string().trim().max(30).optional(),
      callName: z.string().trim().max(30).optional(),
      memory: z.array(z.string().trim().min(1).max(120)).max(20).optional(),
      exercises: z.array(z.string().trim().min(1).max(60)).max(400).optional(),
      todayExercises: z.array(z.string().trim().min(1).max(60)).max(40).optional(),
      weekday: z.number().int().min(1).max(7).optional(),
      /** The member's own data (#1010): week plan, Fuel, workouts, lifts, body weight, and with week-review consent sleep / HRV / Mind. */
      training: z.array(z.string().trim().min(1).max(160)).max(32).optional(),
    })
    .default({}),
  /** JPEG of the machine in front of the member (#856), base64, sent with the last message. */
  photo: z.string().min(100).max(Math.ceil((MAX_PHOTO * 4) / 3) + 4).optional(),
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
  globalLimit: number,
) => {
  const usedToday = (userId: string) =>
    (db.prepare('SELECT count FROM coach_chat_usage WHERE user_id = ? AND day = ?').get(userId, now().toISOString().slice(0, 10)) as
      | { count: number }
      | undefined)?.count ?? 0;

  const busy = inFlight(2);

  /** Whether the chat is switched on, and messages left today. */
  r.get('/me/coach-chat', async (req) => ({ available: !!coach, remainingToday: Math.max(0, dailyLimit - usedToday(req.userId!)) }));

  // Room for one machine photo (#856).
  r.post('/me/coach-chat', { bodyLimit: 2_200_000 }, async (req) => {
    if (!coach) throw new ApiError(503, 'coach_unavailable', 'Coach chat is not available right now.');
    if (!hasAccess(req.userId!)) throw new ApiError(402, 'pro_required', 'Coach chat is part of MonkeyWorkout Pro.');
    const b = body.parse(req.body);
    const turns = modelTurns(b.turns);
    if (turns.at(-1)?.role !== 'member') throw new ApiError(400, 'bad_request', 'The last message must be from the member.');
    const photo = b.photo ? Buffer.from(b.photo, 'base64') : undefined;
    if (photo && (photo.length > MAX_PHOTO || photo[0] !== 0xff || photo[1] !== 0xd8))
      throw new ApiError(400, 'bad_photo', 'Send one JPEG photo up to 1.5 MB.');
    const day = now().toISOString().slice(0, 10);
    if (!busy.enter(req.userId!)) throw new ApiError(429, 'busy', 'Coach is still answering your last message.');
    let answer;
    let count: number | undefined;
    try {
      // Slot taken before the call, given back if it fails: a failed call doesn't use up the member's messages.
      const slot = reserveAiCall(db, 'coach_chat_usage', req.userId!, day, dailyLimit, globalLimit);
      if (slot === 'member') throw new ApiError(429, 'daily_limit', `That's ${dailyLimit} messages today. Coach is back at midnight UTC.`);
      if (slot === 'all') throw new ApiError(429, 'daily_limit', 'Coach is very busy today. Try again tomorrow!');
      count = slot;
      try {
        answer = await coach(turns, b.context, photo);
      } catch (e) {
        refundAiCall(db, 'coach_chat_usage', req.userId!, day);
        req.log.warn(`coach chat failed: ${(e as Error).message}`);
        throw new ApiError(502, 'coach_failed', 'Coach is catching breath. Try again in a moment.');
      }
    } finally {
      busy.leave(req.userId!);
    }
    return { ...answer, remainingToday: Math.max(0, dailyLimit - count) };
  });
};
