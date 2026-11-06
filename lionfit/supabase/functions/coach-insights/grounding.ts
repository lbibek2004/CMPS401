// =============================================================================
// coach-insights | grounding
// =============================================================================
// Everything that keeps Gemini inside the facts we hand it, as pure functions
// with no Deno or network dependency so they run under `node --test` too.
//
// The model is fenced in five layers. Any one of them failing is caught by the
// next:
//
//   1. INPUT IS DATA, NOT TEXT.  parseBrief() accepts only slugs (regex-checked),
//      enums and bounded numbers from the client. No names, notes or free text
//      survive, so nothing a client sends can become an instruction.
//   2. FACTS COME FROM THE DATABASE.  groundBrief() drops every slug that is not
//      an active exercise on available equipment, and attaches names and
//      equipment labels read server-side from `exercises` and
//      `rec_center_equipment`. The prompt contains only those rows.
//   3. CLOSED VOCABULARY.  buildResponseSchema() makes every exercise and
//      muscle field an `enum` of exactly the grounded slugs. Gemini's
//      constrained decoding cannot emit an exercise that is not in the list.
//   4. THE MODEL NEVER PRODUCES A NUMBER WE USE.  Loads, reps and sets are
//      decided by the Dart engine. The model writes one short sentence per
//      item; validateModelOutput() rejects any sentence containing a number
//      that is not one of that item's facts, or medical language.
//   5. NO OUTPUT IS REQUIRED.  Anything rejected is simply omitted and the app
//      shows the engine's own deterministic sentence instead.
// =============================================================================

export const MUSCLE_GROUPS = [
  'abs', 'adductors', 'biceps', 'calves', 'chest_lower', 'chest_upper',
  'delts_front', 'delts_rear', 'delts_side', 'forearms', 'glutes',
  'hamstrings', 'lats', 'quads', 'traps_upper', 'triceps',
] as const;

const SLUG = /^[a-z][a-z0-9_]{0,63}$/;
const GOALS = ['weight_loss', 'muscle_gain', 'general_fitness'];
const BASES = [
  'progression',
  'repeat',
  'firstTime',
  'estimated',
  'calibrated',
  'bodyweight',
  'cardio',
];
const ACTIONS = ['increase', 'hold', 'reduce', 'deload'];
const STATUSES = ['untrained', 'lessTrained', 'wellTrained'];

export const MAX_NEXT_LOADS = 8;
export const MAX_GAPS = 6;
export const MAX_CANDIDATES = 3;
export const MAX_TIP_CHARS = 220;

export interface NextLoad {
  exercise_slug: string;
  basis: string;
  action: string | null;
  weight: number | null;
  unit: 'lb' | 'kg';
  reps: number;
  sets: number;
  target_reps_min: number;
  target_reps_max: number;
}

export interface MuscleGap {
  muscle_group: string;
  status: string;
  hard_sets: number;
  target_sets: number;
  candidate_slugs: string[];
}

export interface Brief {
  goal: string;
  window_days: number;
  next_loads: NextLoad[];
  muscle_gaps: MuscleGap[];
}

export interface ExerciseRow {
  slug: string;
  name: string;
  primary_muscle_groups: string[];
  required_equipment: string[];
  is_active: boolean;
}

export interface EquipmentRow {
  equipment_type: string;
  label: string;
  availability_status: string;
  quantity: number | null;
}

export interface GroundedLoad extends NextLoad {
  exercise_name: string;
  equipment: string[];
}

export interface GroundedGap extends MuscleGap {
  candidates: { slug: string; name: string; equipment: string[] }[];
}

export interface GroundedBrief {
  goal: string;
  window_days: number;
  next_loads: GroundedLoad[];
  muscle_gaps: GroundedGap[];
}

export class BriefError extends Error {}

function num(value: unknown, min: number, max: number, field: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw new BriefError(`${field} must be a number in ${min}-${max}`);
  }
  return value;
}

function oneOf(value: unknown, allowed: readonly string[], field: string): string {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    throw new BriefError(`${field} is not an allowed value`);
  }
  return value;
}

function slug(value: unknown, field: string): string {
  if (typeof value !== 'string' || !SLUG.test(value)) {
    throw new BriefError(`${field} is not a slug`);
  }
  return value;
}

/** Layer 1: the client's payload, reduced to slugs, enums and numbers. */
export function parseBrief(body: unknown): Brief {
  if (typeof body !== 'object' || body === null) throw new BriefError('Body must be an object');
  const b = body as Record<string, unknown>;
  const loads = Array.isArray(b.next_loads) ? b.next_loads.slice(0, MAX_NEXT_LOADS) : [];
  const gaps = Array.isArray(b.muscle_gaps) ? b.muscle_gaps.slice(0, MAX_GAPS) : [];
  return {
    goal: oneOf(b.goal, GOALS, 'goal'),
    window_days: num(b.window_days, 1, 30, 'window_days'),
    next_loads: loads.map((raw, i) => {
      const l = (raw ?? {}) as Record<string, unknown>;
      return {
        exercise_slug: slug(l.exercise_slug, `next_loads[${i}].exercise_slug`),
        basis: oneOf(l.basis, BASES, `next_loads[${i}].basis`),
        action: l.action == null ? null : oneOf(l.action, ACTIONS, `next_loads[${i}].action`),
        weight: l.weight == null ? null : num(l.weight, 0, 2000, `next_loads[${i}].weight`),
        unit: oneOf(l.unit, ['lb', 'kg'], `next_loads[${i}].unit`) as 'lb' | 'kg',
        reps: num(l.reps, 0, 1000, `next_loads[${i}].reps`),
        sets: num(l.sets, 1, 20, `next_loads[${i}].sets`),
        target_reps_min: num(l.target_reps_min, 1, 100, `next_loads[${i}].target_reps_min`),
        target_reps_max: num(l.target_reps_max, 1, 100, `next_loads[${i}].target_reps_max`),
      };
    }),
    muscle_gaps: gaps.map((raw, i) => {
      const g = (raw ?? {}) as Record<string, unknown>;
      const candidates = Array.isArray(g.candidate_slugs)
        ? g.candidate_slugs.slice(0, MAX_CANDIDATES)
        : [];
      return {
        muscle_group: oneOf(g.muscle_group, MUSCLE_GROUPS, `muscle_gaps[${i}].muscle_group`),
        status: oneOf(g.status, STATUSES, `muscle_gaps[${i}].status`),
        hard_sets: num(g.hard_sets, 0, 1000, `muscle_gaps[${i}].hard_sets`),
        target_sets: num(g.target_sets, 0, 1000, `muscle_gaps[${i}].target_sets`),
        candidate_slugs: candidates.map((c, j) => slug(c, `muscle_gaps[${i}].candidate_slugs[${j}]`)),
      };
    }),
  };
}

/** Layer 2: keep only what the database says exists and is usable today. */
export function groundBrief(
  brief: Brief,
  exercises: ExerciseRow[],
  equipment: EquipmentRow[],
): GroundedBrief {
  const usable = new Set(
    equipment
      .filter((e) => e.availability_status === 'available' && e.quantity !== 0)
      .map((e) => e.equipment_type),
  );
  usable.add('bodyweight');
  usable.add('outdoor');
  const labels = new Map(equipment.map((e) => [e.equipment_type, e.label]));
  const bySlug = new Map(
    exercises
      .filter((e) => e.is_active && e.required_equipment.every((s) => usable.has(s)))
      .map((e) => [e.slug, e]),
  );
  const equipmentOf = (e: ExerciseRow) => e.required_equipment.map((s) => labels.get(s) ?? s);

  return {
    goal: brief.goal,
    window_days: brief.window_days,
    next_loads: brief.next_loads.flatMap((l) => {
      const e = bySlug.get(l.exercise_slug);
      return e ? [{ ...l, exercise_name: e.name, equipment: equipmentOf(e) }] : [];
    }),
    muscle_gaps: brief.muscle_gaps.map((g) => ({
      ...g,
      candidates: g.candidate_slugs.flatMap((s) => {
        const e = bySlug.get(s);
        // A candidate must really train the gap, not just exist.
        return e && e.primary_muscle_groups.includes(g.muscle_group)
          ? [{ slug: e.slug, name: e.name, equipment: equipmentOf(e) }]
          : [];
      }),
    })),
  };
}

export const SYSTEM_INSTRUCTION = [
  'You are the LionFit training coach for Southeastern Louisiana University students who train at the',
  'Pennington Student Activity Center.',
  '',
  'Rules you must follow:',
  '- Use ONLY the facts in the FACTS JSON. Do not mention any exercise, machine, weight, rep count or',
  '  muscle that is not in it.',
  '- Never change or invent a number. Every load, rep and set count was computed by the app and is',
  '  final. Repeat a number only exactly as given, or do not mention it.',
  '- One short, encouraging sentence per item, under 30 words. Plain language a beginner understands.',
  '- Explain the why: what the lifter did last time and what the number asks of them now.',
  '- No medical, injury, diet, supplement or pain advice. No diagnoses.',
  '- If the FACTS are empty, return empty lists and a one-sentence summary inviting them to log a session.',
].join('\n');

/** Layer 3: every slug and muscle field is a closed enum. */
export function buildResponseSchema(g: GroundedBrief): Record<string, unknown> {
  const properties: Record<string, unknown> = {
    summary: { type: 'STRING', description: 'One sentence overview of the week, under 30 words.' },
  };
  const required = ['summary'];
  const loadSlugs = g.next_loads.map((l) => l.exercise_slug);
  if (loadSlugs.length > 0) {
    properties.next_loads = {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          exercise_slug: { type: 'STRING', enum: loadSlugs },
          tip: { type: 'STRING' },
        },
        required: ['exercise_slug', 'tip'],
      },
    };
    required.push('next_loads');
  }
  const gaps = g.muscle_gaps.filter((m) => m.candidates.length > 0);
  if (gaps.length > 0) {
    properties.muscle_gaps = {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          muscle_group: { type: 'STRING', enum: gaps.map((m) => m.muscle_group) },
          exercise_slug: {
            type: 'STRING',
            enum: [...new Set(gaps.flatMap((m) => m.candidates.map((c) => c.slug)))],
          },
          tip: { type: 'STRING' },
        },
        required: ['muscle_group', 'exercise_slug', 'tip'],
      },
    };
    required.push('muscle_gaps');
  }
  return { type: 'OBJECT', properties, required };
}

/** The user turn: the grounded facts and nothing else. */
export function buildUserPrompt(g: GroundedBrief): string {
  const facts = {
    goal: g.goal,
    window_days: g.window_days,
    next_loads: g.next_loads.map((l) => ({
      exercise_slug: l.exercise_slug,
      exercise: l.exercise_name,
      equipment: l.equipment,
      decision: l.action ?? l.basis,
      load: l.weight == null ? 'bodyweight' : `${l.weight} ${l.unit}`,
      sets: l.sets,
      reps: l.reps,
      target_reps: `${l.target_reps_min}-${l.target_reps_max}`,
    })),
    muscle_gaps: g.muscle_gaps
      .filter((m) => m.candidates.length > 0)
      .map((m) => ({
        muscle_group: m.muscle_group,
        status: m.status,
        hard_sets_this_window: m.hard_sets,
        target_sets: m.target_sets,
        options: m.candidates,
      })),
  };
  return `FACTS:\n${JSON.stringify(facts)}\n\nWrite the summary and one tip per item.`;
}

const MEDICAL = /\b(diagnos\w*|prescri\w*|medication|medicine|supplement\w*|steroid\w*|injur\w*|pain\w*|doctor|physician|calorie\w*|diet\w*)\b/i;

function numbersIn(text: string): number[] {
  return [...text.matchAll(/\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));
}

/** Layer 4: a sentence passes only if every number in it is one of [allowed]. */
export function tipIsGrounded(tip: unknown, allowed: number[]): tip is string {
  if (typeof tip !== 'string') return false;
  const text = tip.trim();
  if (text.length === 0 || text.length > MAX_TIP_CHARS) return false;
  if (MEDICAL.test(text)) return false;
  return numbersIn(text).every((n) => allowed.some((a) => Math.abs(a - n) < 1e-9));
}

export interface CoachInsights {
  summary: string | null;
  next_loads: Record<string, string>;
  muscle_gaps: Record<string, { exercise_slug: string; tip: string }>;
}

/** Layers 4 + 5: parse, check every item against its own facts, drop the rest. */
export function validateModelOutput(raw: string, g: GroundedBrief): CoachInsights {
  const result: CoachInsights = { summary: null, next_loads: {}, muscle_gaps: {} };
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return result;
  }
  if (typeof parsed !== 'object' || parsed === null) return result;

  const loads = new Map(g.next_loads.map((l) => [l.exercise_slug, l]));
  const gaps = new Map(g.muscle_gaps.map((m) => [m.muscle_group, m]));
  const windowNumbers = [g.window_days];

  if (tipIsGrounded(parsed.summary, windowNumbers)) result.summary = parsed.summary.trim();

  for (const item of Array.isArray(parsed.next_loads) ? parsed.next_loads : []) {
    const slugValue = (item as Record<string, unknown>)?.exercise_slug;
    const fact = typeof slugValue === 'string' ? loads.get(slugValue) : undefined;
    if (!fact || result.next_loads[fact.exercise_slug]) continue;
    const allowed = [
      fact.reps, fact.sets, fact.target_reps_min, fact.target_reps_max,
      ...(fact.weight == null ? [] : [fact.weight]),
    ];
    const tip = (item as Record<string, unknown>).tip;
    if (tipIsGrounded(tip, allowed)) result.next_loads[fact.exercise_slug] = tip.trim();
  }

  for (const item of Array.isArray(parsed.muscle_gaps) ? parsed.muscle_gaps : []) {
    const record = (item ?? {}) as Record<string, unknown>;
    const fact = typeof record.muscle_group === 'string' ? gaps.get(record.muscle_group) : undefined;
    if (!fact || result.muscle_gaps[fact.muscle_group]) continue;
    const pick = fact.candidates.find((c) => c.slug === record.exercise_slug);
    // The enum allows any candidate slug from any gap; this pins it to its own.
    if (!pick) continue;
    if (tipIsGrounded(record.tip, [fact.hard_sets, fact.target_sets, g.window_days])) {
      result.muscle_gaps[fact.muscle_group] = { exercise_slug: pick.slug, tip: (record.tip as string).trim() };
    }
  }
  return result;
}
