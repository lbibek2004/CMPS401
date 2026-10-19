# Pennington Rec Center — Equipment Inventory

**Status: PARTIAL — from memory, not yet verified on the floor.**

Source: team recollection, 2026-10-11. A verified walk-through is still pending. This file is
the source of truth for the `rec_center_equipment` seed until that happens.

Good enough to build the substitution engine against. Not good enough to ship a filter that
tells a student a machine exists when it doesn't — treat counts as provisional and re-verify
before that feature goes live.

> **DEMO DATA (2026-10-17).** Migration `0008_demo_equipment_and_exercises.sql` adds
> placeholder equipment that is **not** in this doc: Olympic barbells + plates (45/35/25/10/5/2.5),
> flat benches, calf raise, hip adduction, ab crunch, hip thrust, leg press, Smith machine,
> pull-up/dip station, treadmills, bikes, rowers, ellipticals — plus 17 exercises that use them.
> Every such row has `notes` starting with `DEMO` and `is_verified = false`; the app shows a
> "Demo" badge on those exercises. The removal SQL is at the top of that migration. This doc is
> still the source of truth for the **real** inventory.

## Free weights

### Dumbbells

| | |
| --- | --- |
| Denominations | 1 lb, 2.5 lb, 5 lb, then **5 lb increments to 165 lb** |
| Resolved set | 1, 2.5, 5, 10, 15, 20, 25, … 160, 165 |
| Count | 35 pairs |

This is the **load quantization table for every dumbbell exercise.** When the recommendation
engine suggests a jump, it must round to one of these — proposing 42.5 lb when the rack jumps
10 → 15 is a bug the user feels immediately. See `ai-coach-engineer`.

### Racks and platforms

| Equipment | Count | Notes |
| --- | --- | --- |
| Squat rack | 4 | |
| "Free weights" | 3 | **AMBIGUOUS** — benches? platforms? barbell stations? See open questions. |
| "Machine" | 1 | **AMBIGUOUS** — unspecified. See open questions. |

## Machines and stations

| Equipment | Count | Notes |
| --- | --- | --- |
| Hamstring curl | 2 | |
| Leg extension | 2 | |
| Bench press | 2 | |
| Incline bench press | 2 | |
| Cable row | 2 | |
| Lat pulldown | 2 | Attachments: **wide**, **close**, **neutral** grip |
| Back row | 2 | Distinct from cable row per the source |
| Adjustable cable station | 3 | Height-adjustable; fly, press, and general use |
| Pec deck fly | 1 | |
| Rear delt fly | 2 | |
| Tricep pushdown | 4 | **2 of the 4 are height-adjustable** |

Total catalogued stations: **24** machines/stations, or **28** counting the 4 squat racks
(excluding dumbbells and the two ambiguous rows).

> Corrected 2026-10-11: an earlier revision of this file said 26, which did not reconcile
> with its own per-row counts. The per-row numbers above are authoritative; settle the true
> total on the floor walk.

## What this covers, and what it leaves exposed

Mapping against the 16 muscle groups in `CLAUDE.md` → **Assets**:

| Muscle group | Covered by | Depth |
| --- | --- | --- |
| `chest_lower` | bench press ×2, pec deck ×1, cables ×3 | good |
| `chest_upper` | incline bench ×2, cables ×3 | good |
| `lats` | lat pulldown ×2, cable row ×2, back row ×2 | good |
| `biceps` | dumbbells, cables ×3 | adequate |
| `triceps` | tricep pushdown ×4, cables | good |
| `delts_front` / `delts_side` | dumbbells, cables | adequate |
| `delts_rear` | rear delt fly ×2, cables | good |
| `quads` | squat rack ×4, leg extension ×2 | good |
| `hamstrings` | hamstring curl ×2, squat rack | adequate |
| `glutes` | squat rack ×4 | **thin** — no hip thrust or glute machine listed |
| `calves` | — | **NOT COVERED** — no calf raise machine listed |
| `adductors` | — | **NOT COVERED** — no adductor machine listed |
| `forearms` | dumbbells | incidental only |
| `abs` | — | **NOT COVERED** — no ab station listed |
| `traps_upper` | dumbbells (shrugs) | adequate |

**Four of the sixteen muscle groups have no dedicated equipment in this list.** Either the Rec
Center has gear not yet recalled, or those groups need bodyweight / dumbbell / outdoor
alternatives in the exercise catalog. The muscle map will show cold spots for `calves`,
`adductors`, and `abs` until that is resolved — which would look like a bug.

## Open questions for the floor walk

1. **"3 free weights" — what are these?** Flat benches? Barbell platforms? Olympic bars?
   The substitution engine needs the actual equipment type.
2. **"1 machine" — which machine?** Currently unusable as data.
3. **Barbells**: how many, and are they standard 45 lb Olympic bars? Needed for barbell load
   quantization the same way the dumbbell table is.
4. **Plate denominations** — 45 / 35 / 25 / 10 / 5 / 2.5 lb? This sets the minimum jump on
   every barbell lift.
5. **Calf raise, adductor/abductor, ab station, hip thrust** — present or genuinely absent?
6. **Leg press** — not mentioned; present?
7. **Cardio equipment** — treadmills, bikes, rowers, ellipticals, and counts. Needed for the
   weight-loss goal plans.
8. **Smith machine** — present?
9. **Busiest hours**, if known — feeds the "machine likely occupied" heuristic.

## How this becomes data

Each row above becomes a `rec_center_equipment` record with an availability status.
`exercises.required_equipment` references those types, and the swap logic answers
"this is occupied — what else trains the same primary muscles with available equipment?"

Keep this file in sync with the seed migration. If they drift, this file wins and the migration
gets regenerated.
