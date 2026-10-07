import { useEffect, useState } from 'react';
import { getExercise } from '../data/exercises';
import type { Block, PlannedExercise, Profile, Session, SetLog } from '../domain/types';
import { EXPERIENCE_LEVEL } from '../engine/config';
import { alternatives } from '../engine/select';
import { lastWeight } from '../storage';
import { fmtPresc, fmtRest } from './format';

interface Props {
  profile: Profile;
  session: Session;
  ticked: Record<string, boolean>;
  done: boolean;
  logs: SetLog[];
  onBack: () => void;
  onTick: (uid: string) => void;
  onSwap: (uid: string, exerciseId: string) => void;
  onLog: (exerciseId: string, weightKg: number) => void;
  onFinish: () => void;
}

export function SessionView(props: Props) {
  const { session, done, onBack, onFinish } = props;
  const [rest, setRest] = useState<{ end: number; total: number } | null>(null);

  return (
    <div className="stack">
      <div className="row between sticky-head">
        <button className="ghost" onClick={onBack}>
          ‹ Week
        </button>
        <span className="pill">≈ {session.estMin}′</span>
      </div>
      <h1 className="session-title">{session.title}</h1>

      {session.blocks.map((b) => (
        <BlockCard key={b.kind} block={b} {...props} onRest={(sec) => setRest({ end: Date.now() + sec * 1000, total: sec })} />
      ))}

      <button className={done ? 'ghost' : 'primary'} onClick={onFinish}>
        {done ? '✓ Completed — mark as not done' : 'Finish session'}
      </button>

      {rest && <RestTimer end={rest.end} total={rest.total} onClose={() => setRest(null)} />}
    </div>
  );
}

function BlockCard({ block, onRest, ...p }: Props & { block: Block; onRest: (sec: number) => void }) {
  return (
    <section className={`card stack block-${block.kind}`}>
      <div className="row between">
        <h2>{block.title}</h2>
        <span className="muted small">{block.targetMin}′</span>
      </div>
      {block.note && <p className="muted small">{block.note}</p>}
      <ol className="items">
        {block.items.map((it) => (
          <Item key={it.uid} item={it} block={block} onRest={onRest} {...p} />
        ))}
      </ol>
    </section>
  );
}

function Item({
  item,
  block,
  profile,
  ticked,
  logs,
  onTick,
  onSwap,
  onLog,
  onRest,
}: Props & { item: PlannedExercise; block: Block; onRest: (sec: number) => void }) {
  const e = getExercise(item.exerciseId);
  const [open, setOpen] = useState(false);
  const [swapping, setSwapping] = useState(false);
  const paired = item.pairedWith ? getExercise(item.pairedWith) : undefined;
  const weighted = block.kind === 'strength' && e.equipment.length > 0 && e.unit !== 'sec';
  const last = weighted ? lastWeight(logs, e.id) : undefined;
  const alts = swapping
    ? alternatives(e.id, { level: EXPERIENCE_LEVEL[profile.experience], equipment: new Set(profile.equipment) })
    : [];
  const isTicked = !!ticked[item.uid];

  return (
    <li className={`item ${isTicked ? 'ticked' : ''} ${item.supersetWith ? 'superset' : ''}`}>
      <div className="row between top">
        <label className="check grow">
          <input type="checkbox" checked={isTicked} onChange={() => onTick(item.uid)} />
          <span>
            <strong>{e.name}</strong>
            <span className="presc">{fmtPresc(item.prescription)}</span>
          </span>
        </label>
        <div className="row tight">
          {item.prescription.restSec > 0 && (
            <button className="ghost small-btn" aria-label={`Start ${fmtRest(item.prescription.restSec)} rest`} onClick={() => onRest(item.prescription.restSec)}>
              ⏱
            </button>
          )}
          <button className="ghost small-btn" aria-label="Swap exercise" onClick={() => setSwapping((s) => !s)}>
            ⇄
          </button>
          <button className="ghost small-btn" aria-label="Details" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
            {open ? '▴' : '▾'}
          </button>
        </div>
      </div>

      {(item.prescription.intensity || item.prescription.note) && (
        <p className="muted small">{[item.prescription.intensity, item.prescription.note].filter(Boolean).join(' · ')}</p>
      )}
      {paired && (
        <p className="pair small">
          During rest: <strong>{paired.name}</strong> · 5–6 slow reps
        </p>
      )}

      {weighted && (
        <div className="row tight small">
          <label className="weight">
            kg
            <input
              type="number"
              inputMode="decimal"
              step="0.5"
              min="0"
              placeholder={last != null ? String(last) : '—'}
              onBlur={(ev) => {
                const v = parseFloat(ev.currentTarget.value);
                if (!Number.isNaN(v) && v >= 0) onLog(e.id, v);
              }}
            />
          </label>
          {last != null && <span className="muted">last: {last} kg</span>}
        </div>
      )}

      {open && (
        <ul className="cues small">
          {e.cues.map((c) => (
            <li key={c}>{c}</li>
          ))}
          <li className="muted">Targets: {[...e.primary, ...(e.secondary ?? [])].join(', ') || 'recovery'}</li>
        </ul>
      )}

      {swapping && (
        <div className="swap">
          {alts.length === 0 && <p className="muted small">No alternatives with your equipment.</p>}
          {alts.map((a) => (
            <button
              key={a.id}
              className="ghost small-btn"
              onClick={() => {
                onSwap(item.uid, a.id);
                setSwapping(false);
              }}
            >
              {a.name}
            </button>
          ))}
        </div>
      )}
    </li>
  );
}


function RestTimer({ end, total, onClose }: { end: number; total: number; onClose: () => void }) {
  const [now, setNow] = useState(Date.now());
  const left = Math.max(0, Math.ceil((end - now) / 1000));
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(t);
  }, []);
  useEffect(() => {
    if (left === 0) {
      try {
        navigator.vibrate?.([200, 100, 200]);
      } catch {
        /* no vibration support */
      }
    }
  }, [left]);
  return (
    <div className={`rest-timer ${left === 0 ? 'over' : ''}`} role="timer" aria-live="polite">
      <div className="rest-fill" style={{ width: `${(1 - left / total) * 100}%` }} />
      <span>{left === 0 ? 'Go!' : `Rest ${fmtRest(left)}`}</span>
      <button className="ghost small-btn" onClick={onClose} aria-label="Close timer">
        ✕
      </button>
    </div>
  );
}
