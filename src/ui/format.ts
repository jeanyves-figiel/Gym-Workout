import type { Prescription } from '../domain/types';

export const fmtRest = (sec: number): string =>
  sec >= 60 ? `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}` : `${sec} s`;

export const fmtPresc = (p: Prescription): string => {
  const parts = [p.sets > 1 ? `${p.sets} × ${p.reps}` : p.reps];
  if (p.restSec > 0) parts.push(`rest ${fmtRest(p.restSec)}`);
  return parts.join(' · ');
};
