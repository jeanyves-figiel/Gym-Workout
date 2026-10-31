import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { DB } from '../db.ts';
import { ApiError } from '../errors.ts';

/**
 * Recipe reviews (#1017): members rate a catalog recipe (stars), say whether its numbers look right and how cooking went.
 * Chips only, no free text (nothing to moderate). Summaries are anonymous; "values look wrong" flags feed the owner's
 * fix list (`node src/admin.ts recipe-flags`).
 */
const recipeId = z.string().regex(/^[a-z0-9][a-z0-9-]{0,79}$/);
const NUMBERS = ['right', 'portion-big', 'portion-small', 'kcal-off'] as const;
const COOKING = ['easy', 'steps-unclear', 'took-longer'] as const;

const review = z
  .object({
    stars: z.number().int().min(1).max(5).nullish(),
    numbers: z.enum(NUMBERS).nullish(),
    cooking: z.enum(COOKING).nullish(),
  })
  .refine((r) => r.stars != null || r.numbers != null || r.cooking != null, 'Pick at least one answer.');

interface Row {
  recipe_id: string;
  stars: number | null;
  numbers: string | null;
  cooking: string | null;
  updated_at: string;
}

const mine = (r: Row) => ({ stars: r.stars, numbers: r.numbers, cooking: r.cooking, updatedAt: r.updated_at });

/** Counts per recipe: reviews, average stars, how many said the numbers are right / flagged them. */
export const recipeSummaries = (db: DB, ids: string[]) => {
  if (!ids.length) return {};
  const rows = db
    .prepare(
      `SELECT recipe_id AS id, COUNT(*) AS reviews, AVG(stars) AS stars, COUNT(stars) AS rated,
         SUM(numbers = 'right') AS valuesRight, SUM(numbers IS NOT NULL AND numbers <> 'right') AS flagged
       FROM recipe_reviews WHERE recipe_id IN (${ids.map(() => '?').join(',')}) GROUP BY recipe_id`,
    )
    .all(...ids) as { id: string; reviews: number; stars: number | null; rated: number; valuesRight: number; flagged: number }[];
  return Object.fromEntries(
    rows.map((r) => [r.id, { reviews: r.reviews, stars: r.stars == null ? null : Math.round(r.stars * 10) / 10, rated: r.rated, valuesRight: r.valuesRight, flagged: r.flagged }]),
  );
};

/** Owner fix list: recipes whose numbers members flagged, most flags first. */
export const recipeFlags = (db: DB) =>
  db
    .prepare(
      `SELECT recipe_id AS id, numbers AS reason, COUNT(*) AS count, MAX(updated_at) AS latest
       FROM recipe_reviews WHERE numbers IS NOT NULL AND numbers <> 'right' GROUP BY recipe_id, numbers ORDER BY count DESC, latest DESC LIMIT 200`,
    )
    .all() as { id: string; reason: string; count: number; latest: string }[];

export const recipeReviewExport = (db: DB, userId: string) =>
  (db.prepare('SELECT recipe_id, stars, numbers, cooking, updated_at FROM recipe_reviews WHERE user_id = ? ORDER BY updated_at').all(userId) as unknown as Row[]).map(
    (r) => ({ recipeId: r.recipe_id, ...mine(r) }),
  );

export const recipeReviewRoutes = (r: FastifyInstance, db: DB, now: () => Date) => {
  r.get('/recipe-reviews', async (req) => {
    const q = z.object({ ids: z.string().max(8_000) }).parse(req.query);
    const ids = [...new Set(q.ids.split(',').filter(Boolean))];
    if (ids.length > 300 || !ids.every((i) => recipeId.safeParse(i).success)) throw new ApiError(400, 'bad_request', 'Up to 300 recipe ids.');
    const own = ids.length
      ? (db
          .prepare(`SELECT recipe_id, stars, numbers, cooking, updated_at FROM recipe_reviews WHERE user_id = ? AND recipe_id IN (${ids.map(() => '?').join(',')})`)
          .all(req.userId!, ...ids) as unknown as Row[])
      : [];
    return { summaries: recipeSummaries(db, ids), mine: Object.fromEntries(own.map((x) => [x.recipe_id, mine(x)])) };
  });

  r.put('/me/recipe-reviews/:recipeId', async (req) => {
    const { recipeId: id } = z.object({ recipeId }).parse(req.params);
    const b = review.parse(req.body);
    const ts = now().toISOString();
    db.prepare(
      `INSERT INTO recipe_reviews (user_id, recipe_id, stars, numbers, cooking, updated_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, recipe_id) DO UPDATE SET stars = excluded.stars, numbers = excluded.numbers, cooking = excluded.cooking, updated_at = excluded.updated_at`,
    ).run(req.userId!, id, b.stars ?? null, b.numbers ?? null, b.cooking ?? null, ts);
    return { mine: { stars: b.stars ?? null, numbers: b.numbers ?? null, cooking: b.cooking ?? null, updatedAt: ts }, summary: recipeSummaries(db, [id])[id] };
  });

  r.delete('/me/recipe-reviews/:recipeId', async (req, reply) => {
    const { recipeId: id } = z.object({ recipeId }).parse(req.params);
    db.prepare('DELETE FROM recipe_reviews WHERE user_id = ? AND recipe_id = ?').run(req.userId!, id);
    return reply.status(204).send();
  });
};
