import type { Profile, WeekPlan } from '../domain/types';
import { GOALS } from '../engine/config';
import { MESOCYCLE_WEEKS, weekLabel } from '../engine/generator';

interface Props {
  profile: Profile;
  plan: WeekPlan;
  done: Record<string, boolean>;
  onOpen: (sessionId: string) => void;
  onWeek: (week: number) => void;
  onRegenerate: () => void;
  onEditProfile: () => void;
}

const SHORT: Record<string, string> = {
  warmup: 'Warm-up',
  power: 'Power',
  strength: 'Strength',
  mobility: 'Mobility',
  cardio: 'Cardio',
  cooldown: 'Cool-down',
};

export function WeekView({ profile, plan, done, onOpen, onWeek, onRegenerate, onEditProfile }: Props) {
  return (
    <div className="stack">
      <section className="card stack">
        <div className="row between">
          <button className="ghost icon" aria-label="Previous week" disabled={plan.week <= 1} onClick={() => onWeek(plan.week - 1)}>
            ‹
          </button>
          <div className="center">
            <h2>
              Week {plan.week} / {MESOCYCLE_WEEKS}
            </h2>
            <p className={`muted small ${plan.deload ? 'deload' : ''}`}>{weekLabel(plan.week)}</p>
          </div>
          <button className="ghost icon" aria-label="Next week" disabled={plan.week >= MESOCYCLE_WEEKS} onClick={() => onWeek(plan.week + 1)}>
            ›
          </button>
        </div>
        <p className="muted small center">
          {GOALS[profile.goal].label} · {profile.sessionsPerWeek}×/week · {plan.sessionMinutes} min
          {profile.climbingDaysPerWeek > 0 && ` · ${profile.climbingDaysPerWeek} climbing days`}
        </p>
        <div className="row center-row">
          <button className="ghost small-btn" onClick={onRegenerate}>
            ↻ New variation
          </button>
          <button className="ghost small-btn" onClick={onEditProfile}>
            ⚙ Profile
          </button>
        </div>
      </section>

      {plan.sessions.map((s) => (
        <button key={s.id} className={`card session-card ${done[s.id] ? 'done' : ''}`} onClick={() => onOpen(s.id)}>
          <div className="row between">
            <strong>{s.title}</strong>
            <span className="pill">{done[s.id] ? '✓ Done' : `${s.estMin}′`}</span>
          </div>
          <div className="bar" aria-hidden>
            {s.blocks.map((b) => (
              <span key={b.kind} className={`seg-${b.kind}`} style={{ flex: Math.max(1, b.targetMin) }} />
            ))}
          </div>
          <p className="muted small">{s.blocks.map((b) => `${SHORT[b.kind]} ${b.targetMin}′`).join(' · ')}</p>
        </button>
      ))}
    </div>
  );
}
