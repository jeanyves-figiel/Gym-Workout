import { useEffect, useState } from 'react';
import type { Profile } from './domain/types';
import { generateWeek } from './engine/generator';
import { load, save, type AppState } from './storage';
import { ProfileForm } from './ui/ProfileForm';
import { SessionView } from './ui/SessionView';
import { WeekView } from './ui/WeekView';

type View = { name: 'setup' } | { name: 'week' } | { name: 'session'; id: string };

const newSeed = () => Math.floor(Math.random() * 2 ** 31);

export default function App() {
  const [state, setState] = useState<AppState>(load);
  const [view, setView] = useState<View>(() => (state.profile && state.plan ? { name: 'week' } : { name: 'setup' }));

  useEffect(() => save(state), [state]);
  useEffect(() => window.scrollTo(0, 0), [view]);

  const regenerate = (profile: Profile, week: number, seed: number) =>
    setState((s) => ({ ...s, profile, plan: generateWeek(profile, { week, seed }), done: {}, ticked: {} }));

  const { profile, plan } = state;
  const session = view.name === 'session' ? plan?.sessions.find((s) => s.id === view.id) : undefined;

  return (
    <div className="app">
      <header className="topbar">
        <span className="brand">◆ Gym-Workout</span>
        {profile && view.name !== 'setup' && <span className="muted small">Fitnesspark Puls 5</span>}
      </header>
      <main>
        {view.name === 'setup' && (
          <ProfileForm
            initial={profile}
            onCancel={plan ? () => setView({ name: 'week' }) : undefined}
            onSubmit={(p) => {
              regenerate(p, 1, newSeed());
              setView({ name: 'week' });
            }}
          />
        )}
        {view.name === 'week' && profile && plan && (
          <WeekView
            profile={profile}
            plan={plan}
            done={state.done}
            onOpen={(id) => setView({ name: 'session', id })}
            onWeek={(w) => regenerate(profile, w, plan.seed)}
            onRegenerate={() => regenerate(profile, plan.week, newSeed())}
            onEditProfile={() => setView({ name: 'setup' })}
          />
        )}
        {view.name === 'session' && profile && session && (
          <SessionView
            profile={profile}
            session={session}
            ticked={state.ticked}
            done={!!state.done[session.id]}
            logs={state.logs}
            onBack={() => setView({ name: 'week' })}
            onTick={(uid) => setState((s) => ({ ...s, ticked: { ...s.ticked, [uid]: !s.ticked[uid] } }))}
            onSwap={(uid, exerciseId) =>
              setState((s) => ({
                ...s,
                plan: s.plan && {
                  ...s.plan,
                  sessions: s.plan.sessions.map((ss) => ({
                    ...ss,
                    blocks: ss.blocks.map((b) => ({
                      ...b,
                      items: b.items.map((it) => (it.uid === uid ? { ...it, exerciseId } : it)),
                    })),
                  })),
                },
              }))
            }
            onLog={(exerciseId, weightKg) =>
              setState((s) => ({ ...s, logs: [...s.logs, { date: new Date().toISOString(), exerciseId, weightKg }] }))
            }
            onFinish={() => {
              setState((s) => ({ ...s, done: { ...s.done, [session.id]: !s.done[session.id] } }));
              setView({ name: 'week' });
            }}
          />
        )}
      </main>
    </div>
  );
}
