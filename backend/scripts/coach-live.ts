// One live Ask Coach call with ANTHROPIC_API_KEY; prints the answer or the API error (#385).
import { claudeCoach } from '../src/coach/chat.ts';

const key = process.env.ANTHROPIC_API_KEY;
if (!key) {
  console.log('ANTHROPIC_API_KEY not set');
  process.exit(1);
}
try {
  const answer = await claudeCoach(key, process.env.ANTHROPIC_WORKSPACE_ID || undefined)(
    [{ role: 'member', text: 'Quick 30 min upper body, no barbell please' }],
    { goal: 'strength', level: 'intermediate', sessionMinutes: 45, equipment: ['dumbbell', 'cable'], readiness: 'good', method: 'block' },
  );
  console.log(JSON.stringify(answer, null, 2));
} catch (e) {
  const err = e as { status?: number; error?: unknown; message?: string };
  console.log('FAILED', err.status, err.message, JSON.stringify(err.error));
  process.exit(1);
}
