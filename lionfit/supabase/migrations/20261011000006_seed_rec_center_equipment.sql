-- =============================================================================
-- LionFit  |  0006  |  SEED: rec_center_equipment
-- =============================================================================
-- Source: docs/rec-center-equipment.md (team recollection, 2026-10-11).
--
--   >> THAT DOC IS PARTIAL AND UNVERIFIED. NOTHING HERE IS INVENTED. <<
--
-- Rules followed while writing this seed:
--   * Every row below appears in the doc with an explicit count.
--   * Anything the doc marks AMBIGUOUS is NOT seeded -- see the block at the
--     bottom listing exactly what was left out and why.
--   * is_verified = false on every real row. Flip to true per row after the
--     floor walk; that flag is what lets the UI say "unconfirmed" instead of
--     lying to a student about what is on the floor.
--
-- availability_status = 'available' on the inventory rows. Reasoning, since
-- this is the one judgement call in the file: the doc asserts these machines
-- exist and gives counts, and asserts nothing about anything being broken.
-- 'unknown' would be the literal reading, but it would make every availability
-- filter return nothing and block the substitution engine from being built at
-- all -- which is the opposite of what the doc says it is for ("good enough to
-- build the substitution engine against"). So: present and usable, but
-- unverified. is_verified carries the doubt; availability_status carries the
-- live state.
--
-- ON CONFLICT DO NOTHING, not DO UPDATE: once an admin corrects a row in the
-- app, re-running this seed must not stomp the correction.
-- =============================================================================

insert into public.rec_center_equipment
  (equipment_type, label, quantity, availability_status, is_verified, is_inventory_item, load_increments_lb, notes)
values

-- ---- Free weights ------------------------------------------------------------

-- The denominations below ARE the load quantization table for every dumbbell
-- exercise: 1, 2.5, 5, then 5 lb steps to 165 (35 pairs, matching the doc's
-- count). The recommendation engine must round every suggested jump to one of
-- these -- proposing 42.5 lb when the rack goes 40 -> 45 is a bug the user
-- feels immediately.
('dumbbell_pair', 'Dumbbells (1-165 lb)', 35, 'available', false, true,
 '{1,2.5,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100,105,110,115,120,125,130,135,140,145,150,155,160,165}'::numeric(6,2)[],
 'Denominations: 1, 2.5, 5 lb then 5 lb increments to 165 lb. 35 pairs. Load quantization table for all dumbbell work.'),

('squat_rack', 'Squat Rack', 4, 'available', false, true, null,
 'Barbell and plate availability at these racks is NOT documented -- see open question 3/4 in docs/rec-center-equipment.md. Catalog rows that need a loaded bar reference this slug.'),

-- ---- Machines and stations ---------------------------------------------------

('hamstring_curl', 'Hamstring Curl Machine', 2, 'available', false, true, null, null),
('leg_extension', 'Leg Extension Machine', 2, 'available', false, true, null, null),
('bench_press', 'Bench Press Station', 2, 'available', false, true, null,
 'Doc does not say whether these are barbell benches or plate-loaded machines. Catalog assumes a flat bench plus a loadable bar.'),
('incline_bench_press', 'Incline Bench Press Station', 2, 'available', false, true, null,
 'Same ambiguity as bench_press: bar vs machine is unconfirmed.'),
('cable_row', 'Seated Cable Row', 2, 'available', false, true, null, null),
('lat_pulldown', 'Lat Pulldown', 2, 'available', false, true, null,
 'Attachments available: wide, close, neutral grip.'),
('back_row', 'Back Row Machine', 2, 'available', false, true, null,
 'Listed as distinct from cable_row in the source.'),
('adjustable_cable_station', 'Adjustable Cable Station', 3, 'available', false, true, null,
 'Height-adjustable. Fly, press, and general cable use. The most substitutable station in the building -- the swap engine leans on it.'),
('pec_deck_fly', 'Pec Deck Fly', 1, 'available', false, true, null, null),
('rear_delt_fly', 'Rear Delt Fly', 2, 'available', false, true, null, null),
('tricep_pushdown', 'Tricep Pushdown', 4, 'available', false, true, null,
 '2 of the 4 are height-adjustable.'),

-- ---- Non-inventory sentinels -------------------------------------------------
-- These two are NOT Pennington equipment. They exist so required_equipment is
-- never an empty array and so the substitution query can be a single uniform
-- array-containment test instead of a special case for bodyweight work.
-- is_inventory_item = false keeps them out of any inventory report.
('bodyweight', 'Bodyweight (no equipment)', null, 'available', true, false, null,
 'Sentinel, not Rec Center inventory. Always available.'),
('outdoor', 'Outdoor / campus', null, 'available', true, false, null,
 'Sentinel, not Rec Center inventory. Covers running, hill and stair work, outdoor circuits.')

on conflict (equipment_type) do nothing;


-- =============================================================================
-- DELIBERATELY NOT SEEDED -- open questions, not data
-- =============================================================================
--
-- 1. "3 free weights" (doc: Racks and platforms).
--    AMBIGUOUS. Flat benches? Barbell platforms? Olympic bars? Three different
--    answers imply three different substitution graphs, so no row is created.
--    Add it once the floor walk says what it is.
--
-- 2. "1 machine" (doc: Racks and platforms).
--    AMBIGUOUS. Unspecified. Unusable as data; no row created.
--
-- 3. Barbells and plate denominations.
--    Not in the doc at all (open questions 3 and 4). Until these exist there is
--    no barbell load quantization table, so the recommendation engine can only
--    round confidently on dumbbell lifts. Barbell suggestions must be treated
--    as approximate until plate denominations are recorded here as a
--    load_increments_lb array on a 'barbell' row.
--
-- 4. Cardio equipment -- treadmills, bikes, rowers, ellipticals (open question
--    7). None catalogued, so EVERY cardio row in the exercise seed is outdoor.
--    The weight-loss plans will look thin indoors until this is answered.
--
-- 5. Calf raise, adductor/abductor machine, ab station, hip thrust station,
--    leg press, Smith machine, pull-up bar (open questions 5, 6, 8).
--    Not listed, so not seeded. The exercise catalog routes those muscle groups
--    through dumbbells, bodyweight and cables instead -- see migration 0007.
--
-- 6. COUNT DISCREPANCY WORTH CHECKING ON THE WALK:
--    docs/rec-center-equipment.md says "Total catalogued stations: 26
--    (excluding dumbbells and the two ambiguous rows)". The per-row counts in
--    that same doc add up to 24 for the Machines and stations table, or 28 if
--    the 4 squat racks are included. Neither is 26. The per-row counts were
--    seeded (they are the more specific claim); the total was not. Two
--    stations are unaccounted for one way or the other.
-- =============================================================================
