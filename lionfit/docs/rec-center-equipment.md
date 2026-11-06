# Pennington Rec Center — Equipment Inventory

**Source: `assets/Pennington Rec Center Equipment List.docx` (added 2026-10-19).** This replaces
the earlier from-memory list. It is the source of truth for the `rec_center_equipment` seed
(migration `20261019000008_pennington_equipment_list.sql`); if the two drift, the document wins
and the migration gets a follow-up.

Every row below has `is_verified = true` in the database because it comes from a written list.
If that list was itself compiled from memory, flip rows back to `false` until someone checks.

## How the weight columns are read

The document gives min, max and "increment" per machine. The increment means different things
for different gear, so each row records a `load_kind`:

| Kind | Reachable loads | Example |
| --- | --- | --- |
| `stack` | min + k × step | Leg extension 12.5 → 200 in 12.5 lb pins |
| `plates` | min + k × **2** × step — step is the smallest plate, loaded on both sides | Bench 45 lb bar, 2.5 lb plates → 5 lb jumps |
| `fixed_set` | min + k × step, plus max | Dumbbells 5 → 125 in 5 lb steps |

Suggested loads are always rounded to one of these (`lib/core/training/equipment_loads.dart`).

## Barbell stations (plate loaded)

| Equipment | Count | Range (lb) | Smallest plate |
| --- | --- | --- | --- |
| Flat barbell bench press | 2 | 45–600 | 2.5 |
| Incline barbell bench press | 2 | 45–600 | 2.5 |
| Decline bench press | 1 | 45–500 | 2.5 |
| Shoulder press (barbell) | 1 | 45–500 | 2.5 |
| Deadlift | 1 | 45–500 | 2.5 |
| Smith machine | 2 | 45–600 | 2.5 |
| T-bar | 1 | 45–250 | 2.5 |

**There is no free squat rack.** Squats are on the Smith machine; the old `squat_rack` row is
kept as `out_of_service` with quantity 0 so history still resolves.

## Standard 4-station Multi-Jungle × 2

| Station | Range (lb) | Step |
| --- | --- | --- |
| 1. Lat pulldown (bridge has a pull-up / chin-up bar) | 10–295 | 5 |
| 2. Seated cable row | 10–295 | 5 |
| 3. Fixed high pulley | 10–200 | 5 |
| 4. Adjustable cable column | 10–200 | 5 |

Paramount PFT-200 functional trainer: 3 units, 5–85 lb, 5 lb steps.

## Selectorized machines

| Equipment | Count | Range (lb) | Step |
| --- | --- | --- | --- |
| Precor Discovery leg press | 1 | 0–400 | 20 |
| Seated leg press | 1 | 20–400 | 20 |
| Dual axis overhead press | 2 | 10–205 | 5 |
| Leg extension | 2 | 12.5–200 | 12.5 |
| Rotary calf | 2 | 10–405 | 5 |
| Lateral raise | 2 | 10–205 | 5 |
| Seated leg curl | 2 | 10–205 | 5 |
| Hip adduction (inner thigh)* | 1 | 10–205 | 5 |
| Hip abduction (outer thigh) | 1 | 10–205 | 5 |
| Torso rotation | 1 | 10–205 | 5 |
| Rotary hip | 1 | 12.5–200 | 12.5 |
| Incline press | 2 | 10–305 | 5 |
| Dual axis row / rear delt | 2 | 10–305 | 5 |
| Dual axis pulldown | 2 | 10–305 | 5 |
| Back extension | 1 | 10–305 | 5 |
| Dual axis chest press | 2 | 10–305 | 5 |
| Ab crunch | 2 | 10–205 | 5 |
| Arm extension | 2 | 10–205 | 5 |
| Arm curl | 2 | 10–205 | 5 |
| Hip thrust | 1 | 0–420 | 20 |
| Pec dec fly | 1 | 20–250 | 10 |
| Kick backs (glute) | 1 | 12.5–150 | 12.5 |

\* The document says "Hip Abduction (inner)". Inner-thigh pads that you squeeze together are
adduction, so it is recorded as adduction.

## Plate-loaded machines

| Equipment | Count | Range (lb) | Smallest plate |
| --- | --- | --- | --- |
| Hammer Strength iso-lateral row | 1 | 25–400 | 2.5 |
| Seated calf raise | 1 | 45–550 | 2.5 |
| Hammer Strength iso-lateral leg press | 1 | 45–600 | 2.5 |
| Hammer Strength iso-lateral leg press (single leg) | 1 | 45–600 | 2.5 |
| Precor angled leg press (DPL0601) | 1 | 45–800 | 2.5 |
| Free-weight preacher curl | 2 | 15–400 | 2.5 |

## Free weights

| Equipment | Count | Range | Step |
| --- | --- | --- | --- |
| Dumbbells | 2 of each weight | 5–125 lb | 5 lb |
| EZ curl bars (fixed) | 1 | 20–60 lb | 10 lb |
| Barbells (fixed) | 1 | 20–110 lb | 10 lb |
| Kettlebells | 1–5 per weight | 3–24 **kg** | 2 kg |
| Rubber medicine balls | 1–4 per weight | 4–20 (unit not given; lb assumed) | 4 |

## Benches, stations, cardio

| Equipment | Count |
| --- | --- |
| Adjustable benches | 5 |
| Fixed seated dumbbell shoulder press | 2 |
| Dip station | 2 |
| Glute ham developer | 4 |
| Decline abdominal bench | 1 |
| Feet-elevated crunch machine | 2 |
| Indoor cycling | 6 |
| Elliptical | 17 |
| Treadmill | 16 |
| StairMaster | 4 |
| Rowing machine | 4 |

## Still worth checking on the floor

- **Kettlebell denominations.** 3 kg + 2 kg steps never reaches 24 kg; the real set is probably
  4, 6, 8 … 24 or 4, 8, 12, 16, 20, 24. The seed generates 3, 5 … 23 plus 24.
- **Medicine ball unit** (lb assumed).
- **Plate denominations.** Only the smallest (2.5 lb) is listed. That sets the smallest jump,
  which is what matters most, but the 45/35/25/10/5 assumption in `load_quantization.dart` is
  still an assumption.
- **"Incline Press"** is listed separately from the incline barbell bench — recorded as a
  selectorized machine.
