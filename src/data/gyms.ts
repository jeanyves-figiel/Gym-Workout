import type { Equipment } from '../domain/types';

export interface GymProfile {
  id: string;
  name: string;
  location: string;
  equipment: Equipment[];
  amenities: string[];
  /** Assumptions to verify on site. */
  note: string;
}

export const ALL_EQUIPMENT: Equipment[] = [
  'barbell', 'trap-bar', 'rack', 'bench', 'dumbbells', 'kettlebells', 'cable', 'smith',
  'leg-press', 'hack-squat', 'leg-curl', 'leg-extension', 'lat-pulldown', 'seated-row',
  'chest-press', 'pec-deck', 'hip-thrust-machine', 'back-extension', 'pullup-bar', 'dip-station',
  'rings', 'trx', 'landmine', 'plyo-box', 'med-ball', 'slam-ball', 'sled', 'battle-rope',
  'ab-wheel', 'bands', 'foam-roller', 'mat', 'treadmill', 'bike', 'air-bike', 'rower', 'ski-erg',
  'stair-climber', 'elliptical',
];

export const EQUIPMENT_LABEL: Record<Equipment, string> = {
  barbell: 'Barbell & plates', 'trap-bar': 'Trap bar', rack: 'Squat/power rack', bench: 'Adjustable bench',
  dumbbells: 'Dumbbells', kettlebells: 'Kettlebells', cable: 'Cable tower', smith: 'Smith machine',
  'leg-press': 'Leg press', 'hack-squat': 'Hack squat', 'leg-curl': 'Leg curl', 'leg-extension': 'Leg extension',
  'lat-pulldown': 'Lat pulldown', 'seated-row': 'Seated row', 'chest-press': 'Chest press machine',
  'pec-deck': 'Pec deck / rear delt', 'hip-thrust-machine': 'Hip thrust machine', 'back-extension': 'Back extension (45°)',
  'pullup-bar': 'Pull-up bar', 'dip-station': 'Dip station', rings: 'Gymnastic rings', trx: 'TRX / suspension',
  landmine: 'Landmine', 'plyo-box': 'Plyo box', 'med-ball': 'Medicine ball', 'slam-ball': 'Slam ball', sled: 'Sled & turf',
  'battle-rope': 'Battle rope', 'ab-wheel': 'Ab wheel', bands: 'Resistance bands', 'foam-roller': 'Foam roller',
  mat: 'Stretch mat', treadmill: 'Treadmill', bike: 'Upright/spin bike', 'air-bike': 'Air bike',
  rower: 'Rower', 'ski-erg': 'SkiErg', 'stair-climber': 'Stair climber', elliptical: 'Cross-trainer',
};

export const GYMS: GymProfile[] = [
  {
    id: 'fitnesspark-puls5',
    name: 'Fitnesspark Puls 5',
    location: 'Giessereistrasse 18, 8005 Zürich',
    equipment: ALL_EQUIPMENT,
    amenities: ['Sauna ×2', 'Steam bath', 'Whirlpool', 'Group classes'],
    note: 'Large full-service club: free-weight area, machine circuits (incl. eccentric-capable machines), functional zone, full cardio floor. Exact inventory assumed — untick anything missing in Settings.',
  },
  {
    id: 'custom',
    name: 'Custom gym',
    location: '',
    equipment: ALL_EQUIPMENT,
    amenities: [],
    note: 'Select the equipment your gym has.',
  },
];

export const DEFAULT_GYM = GYMS[0]!;
