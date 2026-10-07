import { useMemo, useState } from 'react';
import { DEFAULT_GYM, EQUIPMENT_LABEL, GYMS } from '../data/gyms';
import type { Equipment, Experience, Goal, Profile } from '../domain/types';
import { GOALS } from '../engine/config';
import { sessionMinutes } from '../engine/generator';

interface Props {
  initial?: Profile;
  onSubmit: (p: Profile) => void;
  onCancel?: () => void;
}

const SESSIONS = [2, 3, 4, 5, 6] as const;
const EXPERIENCE: Experience[] = ['beginner', 'intermediate', 'advanced'];
const CLIMB = [0, 1, 2, 3, 4];
const CAPS = [undefined, 45, 60, 75, 90];

export const DEFAULT_PROFILE: Profile = {
  goal: 'balanced',
  sessionsPerWeek: 3,
  experience: 'intermediate',
  climbingDaysPerWeek: 2,
  equipment: DEFAULT_GYM.equipment,
};

export function ProfileForm({ initial, onSubmit, onCancel }: Props) {
  const [p, setP] = useState<Profile>(initial ?? DEFAULT_PROFILE);
  const [showEq, setShowEq] = useState(false);
  const minutes = useMemo(() => sessionMinutes(p), [p]);
  const set = <K extends keyof Profile>(k: K, v: Profile[K]) => setP((x) => ({ ...x, [k]: v }));
  const toggleEq = (e: Equipment) =>
    set('equipment', p.equipment.includes(e) ? p.equipment.filter((x) => x !== e) : [...p.equipment, e]);

  return (
    <form
      className="stack"
      onSubmit={(ev) => {
        ev.preventDefault();
        onSubmit(p);
      }}
    >
      <section className="card stack">
        <h2>Goal</h2>
        <div className="goal-grid" role="radiogroup" aria-label="Goal">
          {(Object.keys(GOALS) as Goal[]).map((g) => (
            <label key={g} className={`goal ${p.goal === g ? 'on' : ''}`}>
              <input type="radio" name="goal" checked={p.goal === g} onChange={() => set('goal', g)} />
              <strong>{GOALS[g].label}</strong>
              <span className="muted">{GOALS[g].blurb}</span>
            </label>
          ))}
        </div>
      </section>

      <section className="card stack">
        <Segmented label="Gym sessions per week" options={SESSIONS} value={p.sessionsPerWeek} onChange={(v) => set('sessionsPerWeek', v)} />
        <Segmented label="Experience" options={EXPERIENCE} value={p.experience} onChange={(v) => set('experience', v)} />
        <Segmented label="Climbing days per week" options={CLIMB} value={p.climbingDaysPerWeek} onChange={(v) => set('climbingDaysPerWeek', v)} />
        <Segmented
          label="Max session length"
          options={CAPS}
          value={p.maxSessionMinutes}
          render={(v) => (v ? `${v}′` : 'Auto')}
          onChange={(v) => set('maxSessionMinutes', v)}
        />
        <p className="summary" data-testid="session-length">
          ≈ <strong>{minutes} min</strong> × {p.sessionsPerWeek} = {((minutes * p.sessionsPerWeek) / 60).toFixed(1)} h / week
        </p>
      </section>

      <section className="card stack">
        <h2>Gym</h2>
        <p>
          <strong>{DEFAULT_GYM.name}</strong> <span className="muted">· {DEFAULT_GYM.location}</span>
        </p>
        <p className="muted small">{GYMS[0]!.note}</p>
        <button type="button" className="link" onClick={() => setShowEq((s) => !s)}>
          {showEq ? 'Hide' : 'Edit'} equipment ({p.equipment.length})
        </button>
        {showEq && (
          <div className="eq-grid">
            {(Object.keys(EQUIPMENT_LABEL) as Equipment[]).map((e) => (
              <label key={e} className="check">
                <input type="checkbox" checked={p.equipment.includes(e)} onChange={() => toggleEq(e)} />
                {EQUIPMENT_LABEL[e]}
              </label>
            ))}
          </div>
        )}
      </section>

      <div className="row end">
        {onCancel && (
          <button type="button" className="ghost" onClick={onCancel}>
            Cancel
          </button>
        )}
        <button type="submit" className="primary">
          Generate plan
        </button>
      </div>
    </form>
  );
}

interface SegProps<T> {
  label: string;
  options: readonly T[];
  value: T;
  onChange: (v: T) => void;
  render?: (v: T) => string;
}

function Segmented<T extends string | number | undefined>({ label, options, value, onChange, render }: SegProps<T>) {
  return (
    <fieldset className="seg">
      <legend>{label}</legend>
      <div className="seg-row">
        {options.map((o) => (
          <button
            type="button"
            key={String(o)}
            className={o === value ? 'on' : ''}
            aria-pressed={o === value}
            onClick={() => onChange(o)}
          >
            {render ? render(o) : String(o)}
          </button>
        ))}
      </div>
    </fieldset>
  );
}
