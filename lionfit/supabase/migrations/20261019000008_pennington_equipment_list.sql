-- =============================================================================
-- LionFit  |  0008  |  The real Pennington equipment list + catalog to match
-- =============================================================================
-- Depends on: 0003 (tables), 0006 (recollection seed), 0007 (starter catalog).
--
-- Source: assets/Pennington Rec Center Equipment List.docx (2026-10-19), which
-- replaces the from-memory list in docs/rec-center-equipment.md. The earlier
-- DEMO placeholder migration was never applied and has been deleted; nothing
-- in this file is invented -- every machine, count and weight range below is a
-- row in that document. Where the document is ambiguous it says so in `notes`.
--
-- What this file does, in order:
--   1. Adds load columns to rec_center_equipment so the progression engine can
--      snap a suggestion to a weight the machine can actually be set to.
--   2. Renames four 0006 rows whose machine has a different name on the real
--      list (ids kept, exercises re-pointed), and retires the squat rack, which
--      is not on the list at all.
--   3. Upserts every row of the document.
--   4. Re-points 0007 exercises at real equipment, retires the three that no
--      longer have equipment, and adds exercises for the new machines.
--
-- ON CONFLICT DO UPDATE this time, not DO NOTHING (the opposite of 0006/0007).
-- Deliberate: 0006 was recollection and this document is the authoritative
-- correction of it. An admin edit made after this migration is still safe --
-- this file only ever runs once through the migration history.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Load model
-- -----------------------------------------------------------------------------
-- load_kind says how the range is reachable, because the document's
-- "increment" column means different things for different gear:
--
--   stack     -- selectorized pin stack. Loads are load_min + k * load_step.
--   plates    -- plate loaded. load_step is the SMALLEST PLATE; plates go on
--                both sides, so the smallest total jump is 2 * load_step.
--                load_min is the empty bar / sled.
--   fixed_set -- separate fixed implements (dumbbells, EZ bars, kettlebells).
--                Loads are load_min + k * load_step, plus load_max itself.
--   NULL      -- nothing to load (cardio, benches, dip station).
--
-- load_unit exists because the kettlebells are labelled in kg. Everything
-- else on the list is in pounds.
alter table public.rec_center_equipment
  add column if not exists load_kind text
    constraint rec_center_equipment_load_kind_check
    check (load_kind is null or load_kind in ('stack', 'plates', 'fixed_set')),
  add column if not exists load_min  numeric(7,2),
  add column if not exists load_max  numeric(7,2),
  add column if not exists load_step numeric(6,2),
  add column if not exists load_unit public.weight_unit not null default 'lb';

do $$
begin
  alter table public.rec_center_equipment
    add constraint rec_center_equipment_load_range_check
    check (
      load_kind is null
      or (load_min is not null and load_max is not null and load_step > 0
          and load_min >= 0 and load_max >= load_min)
    );
exception
  when duplicate_object then null;
end
$$;

comment on column public.rec_center_equipment.load_kind is
  'stack | plates | fixed_set | NULL. For plates, load_step is the smallest plate and the smallest total jump is 2 x load_step.';


-- -----------------------------------------------------------------------------
-- 2. Renames and retirements of 0006 rows
-- -----------------------------------------------------------------------------
-- Rename in place (keeps the row id) and rewrite every exercise that pointed
-- at the old slug. Guarded so a re-run is a no-op.
do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('hamstring_curl',  'seated_leg_curl'),          -- real list: Seated Leg Curl
      ('back_row',        'hammer_iso_row'),           -- Hammer Strength Iso-Lateral Row
      ('rear_delt_fly',   'dual_axis_row_rear_delt'),  -- Dual axis row/rear delts
      ('tricep_pushdown', 'high_pulley')               -- Multi-Jungle station 3
    ) as t(old_slug, new_slug)
  loop
    if exists (select 1 from public.rec_center_equipment where equipment_type = r.old_slug)
       and not exists (select 1 from public.rec_center_equipment where equipment_type = r.new_slug)
    then
      update public.rec_center_equipment
         set equipment_type = r.new_slug
       where equipment_type = r.old_slug;
    end if;
    update public.exercises
       set required_equipment = array_replace(required_equipment, r.old_slug, r.new_slug)
     where r.old_slug = any (required_equipment);
  end loop;
end
$$;

-- Not on the real list. Kept as a row (exercises may still reference it in
-- history) but marked absent so no plan or swap ever offers it.
update public.rec_center_equipment
   set quantity = 0,
       availability_status = 'out_of_service',
       is_verified = true,
       notes = 'Not on the Pennington equipment list (2026-10-19). Squats use the Smith machine; deadlifts use the deadlift platform.'
 where equipment_type = 'squat_rack';


-- -----------------------------------------------------------------------------
-- 3. The document, row by row
-- -----------------------------------------------------------------------------
-- is_verified = true: these come from the written list, not from memory. If
-- the list itself turns out to be stale, flip individual rows back.
insert into public.rec_center_equipment
  (equipment_type, label, quantity, availability_status, is_verified, is_inventory_item,
   load_kind, load_min, load_max, load_step, load_unit, load_increments_lb, notes)
values

-- ---- Barbell stations (plate loaded) ------------------------------------------
('bench_press',            'Flat Barbell Bench Press',       2, 'available', true, true, 'plates', 45, 600, 2.5, 'lb', null, null),
('incline_bench_press',    'Incline Barbell Bench Press',    2, 'available', true, true, 'plates', 45, 600, 2.5, 'lb', null, null),
('decline_bench_press',    'Decline Bench Press',            1, 'available', true, true, 'plates', 45, 500, 2.5, 'lb', null, null),
('barbell_shoulder_press', 'Shoulder Press (Barbell)',       1, 'available', true, true, 'plates', 45, 500, 2.5, 'lb', null, null),
('deadlift_platform',      'Deadlift Platform',              1, 'available', true, true, 'plates', 45, 500, 2.5, 'lb', null,
 'Listed as "Dead Lift". Also where barbell Romanian deadlifts happen.'),
('smith_machine',          'Smith Machine',                  2, 'available', true, true, 'plates', 45, 600, 2.5, 'lb', null,
 'The only squat station on the list -- there is no free squat rack.'),
('t_bar_row',              'T-Bar Row',                      1, 'available', true, true, 'plates', 45, 250, 2.5, 'lb', null, null),

-- ---- Multi-Jungle (2 units, 4 stations each) ------------------------------------
('lat_pulldown',             'Lat Pulldown (Multi-Jungle station 1)',          2, 'available', true, true, 'stack', 10, 295, 5, 'lb', null,
 'Standard 4 Station Multi-Jungle, station 1. Wide, close and neutral attachments.'),
('pull_up_bar',              'Pull-Up / Chin-Up Bar (Multi-Jungle bridge)',    2, 'available', true, true, null, null, null, null, 'lb', null,
 'Overhead bar on the bridge of each Multi-Jungle. Shares space with the lat pulldown.'),
('cable_row',                'Seated Cable Row (Multi-Jungle station 2)',      2, 'available', true, true, 'stack', 10, 295, 5, 'lb', null, null),
('high_pulley',              'Fixed High Pulley (Multi-Jungle station 3)',     2, 'available', true, true, 'stack', 10, 200, 5, 'lb', null,
 'Fixed height: pushdowns and other high-cable work.'),
('adjustable_cable_station', 'Adjustable Cable Column (Multi-Jungle station 4)', 2, 'available', true, true, 'stack', 10, 200, 5, 'lb', null,
 'Height-adjustable. Flies, face pulls, crunches, lateral raises.'),
('functional_trainer',       'Paramount PFT-200 Functional Trainer',           3, 'available', true, true, 'stack', 5, 85, 5, 'lb', null,
 'Dual adjustable cables. Range is per stack as listed (5-85 lb).'),

-- ---- Selectorized machines ------------------------------------------------------
('leg_press_selectorized',  'Precor Discovery Series Leg Press', 1, 'available', true, true, 'stack', 0,    400, 20,   'lb', null, null),
('seated_leg_press',        'Seated Leg Press',                  1, 'available', true, true, 'stack', 20,   400, 20,   'lb', null, null),
('dual_axis_overhead_press','Dual Axis Overhead Press',          2, 'available', true, true, 'stack', 10,   205, 5,    'lb', null, null),
('leg_extension',           'Leg Extension',                     2, 'available', true, true, 'stack', 12.5, 200, 12.5, 'lb', null, null),
('rotary_calf',             'Rotary Calf Machine',               2, 'available', true, true, 'stack', 10,   405, 5,    'lb', null, null),
('lateral_raise_machine',   'Lateral Raise Machine',             2, 'available', true, true, 'stack', 10,   205, 5,    'lb', null, null),
('seated_leg_curl',         'Seated Leg Curl',                   2, 'available', true, true, 'stack', 10,   205, 5,    'lb', null, null),
('hip_adduction_machine',   'Hip Adduction (inner thigh)',       1, 'available', true, true, 'stack', 10,   205, 5,    'lb', null,
 'The list says "Hip Abduction (inner)". Moving the legs together against inner-thigh pads is adduction, so it is recorded as adduction.'),
('hip_abduction_machine',   'Hip Abduction (outer thigh)',       1, 'available', true, true, 'stack', 10,   205, 5,    'lb', null, null),
('torso_rotation',          'Torso Rotation',                    1, 'available', true, true, 'stack', 10,   205, 5,    'lb', null, null),
('rotary_hip',              'Rotary Hip',                        1, 'available', true, true, 'stack', 12.5, 200, 12.5, 'lb', null, null),
('incline_press_machine',   'Incline Press (machine)',           2, 'available', true, true, 'stack', 10,   305, 5,    'lb', null,
 'Listed as "Incline Press", separately from the incline barbell bench; recorded as the selectorized machine.'),
('dual_axis_row_rear_delt', 'Dual Axis Row / Rear Delt',         2, 'available', true, true, 'stack', 10,   305, 5,    'lb', null,
 'One machine for both seated rows and rear-delt flies.'),
('dual_axis_pulldown',      'Dual Axis Pulldown',                2, 'available', true, true, 'stack', 10,   305, 5,    'lb', null, null),
('back_extension_machine',  'Back Extension',                    1, 'available', true, true, 'stack', 10,   305, 5,    'lb', null, null),
('dual_axis_chest_press',   'Dual Axis Chest Press',             2, 'available', true, true, 'stack', 10,   305, 5,    'lb', null, null),
('ab_crunch_machine',       'Ab Crunch',                         2, 'available', true, true, 'stack', 10,   205, 5,    'lb', null, null),
('arm_extension_machine',   'Arm Extension',                     2, 'available', true, true, 'stack', 10,   205, 5,    'lb', null, null),
('arm_curl_machine',        'Arm Curl',                          2, 'available', true, true, 'stack', 10,   205, 5,    'lb', null, null),
('hip_thrust_machine',      'Hip Thrust',                        1, 'available', true, true, 'stack', 0,    420, 20,   'lb', null, null),
('pec_deck_fly',            'Pec Dec Fly',                       1, 'available', true, true, 'stack', 20,   250, 10,   'lb', null, null),
('kickback_machine',        'Kick Backs (glute)',                1, 'available', true, true, 'stack', 12.5, 150, 12.5, 'lb', null,
 'Listed as "Kick Backs". Recorded as a glute kickback machine.'),

-- ---- Plate-loaded machines ------------------------------------------------------
('hammer_iso_row',              'Hammer Strength Iso-Lateral Row',                   1, 'available', true, true, 'plates', 25, 400, 2.5, 'lb', null, null),
('seated_calf_raise',           'Seated Calf Raise',                                 1, 'available', true, true, 'plates', 45, 550, 2.5, 'lb', null, null),
('hammer_iso_leg_press',        'Hammer Strength Iso-Lateral Leg Press',             1, 'available', true, true, 'plates', 45, 600, 2.5, 'lb', null, null),
('hammer_iso_leg_press_single', 'Hammer Strength Iso-Lateral Leg Press (single leg)',1, 'available', true, true, 'plates', 45, 600, 2.5, 'lb', null, null),
('angled_leg_press',            'Precor Angled Leg Press (DPL0601)',                 1, 'available', true, true, 'plates', 45, 800, 2.5, 'lb', null, null),
('preacher_curl',               'Preacher Curl (free weight)',                       2, 'available', true, true, 'plates', 15, 400, 2.5, 'lb', null, null),

-- ---- Free weights ---------------------------------------------------------------
-- Dumbbells: 5-125 lb in 5 lb steps, two of each weight. This REPLACES the
-- recollected 1/2.5/5...165 rack from 0006; load_increments_lb is the table the
-- dumbbell quantizer rounds to.
('dumbbell_pair',  'Dumbbells (5-125 lb)', 2, 'available', true, true, 'fixed_set', 5, 125, 5, 'lb',
 '{5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100,105,110,115,120,125}'::numeric(6,2)[],
 'Two of each weight ("2 sets each weight"). Per-hand loads, 5 lb steps.'),
('ez_curl_bar',    'EZ Curl Bars (fixed)', 1, 'available', true, true, 'fixed_set', 20, 60,  10, 'lb', null,
 'Fixed-weight bars, 20-60 lb in 10 lb steps.'),
('fixed_barbell',  'Barbells (fixed)',     1, 'available', true, true, 'fixed_set', 20, 110, 10, 'lb', null,
 'Fixed-weight straight bars, 20-110 lb in 10 lb steps. Not the Olympic bars at the stations.'),
('kettlebells',    'Kettlebells',          null, 'available', true, true, 'fixed_set', 3, 24, 2, 'kg', null,
 'Labelled in kg. List gives 3 kg to 24 kg in 2 kg steps, 1-5 bells per weight -- 3 + 2k never reaches 24, so the exact denominations need a look on the floor.'),
('medicine_balls', 'Rubber Medicine Balls', null, 'available', true, true, 'fixed_set', 4, 20, 4, 'lb', null,
 '1-4 balls per weight. The list gives no unit; pounds assumed.'),

-- ---- Benches and bodyweight stations ---------------------------------------------
('adjustable_bench',            'Adjustable Bench',                    5, 'available', true, true, null, null, null, null, 'lb', null,
 'Flat-to-incline. Every dumbbell exercise that needs a bench uses one of these.'),
('seated_shoulder_press_bench', 'Fixed Seated Dumbbell Shoulder Press',2, 'available', true, true, null, null, null, null, 'lb', null, null),
('dip_station',                 'Dip Station',                         2, 'available', true, true, null, null, null, null, 'lb', null, null),
('glute_ham_developer',         'Glute Ham Developer',                 4, 'available', true, true, null, null, null, null, 'lb', null, null),
('decline_ab_bench',            'Decline Abdominal Bench',             1, 'available', true, true, null, null, null, null, 'lb', null, null),
('feet_elevated_crunch',        'Feet Elevated Crunch Machine',        2, 'available', true, true, null, null, null, null, 'lb', null, null),

-- ---- Cardio -------------------------------------------------------------------
('indoor_cycle',   'Indoor Cycling Bike', 6,  'available', true, true, null, null, null, null, 'lb', null, null),
('elliptical',     'Elliptical',          17, 'available', true, true, null, null, null, null, 'lb', null, null),
('treadmill',      'Treadmill',           16, 'available', true, true, null, null, null, null, 'lb', null, null),
('stairmaster',    'StairMaster',         4,  'available', true, true, null, null, null, null, 'lb', null, null),
('rowing_machine', 'Rowing Machine',      4,  'available', true, true, null, null, null, null, 'lb', null, null)

on conflict (equipment_type) do update
  set label               = excluded.label,
      quantity            = excluded.quantity,
      availability_status = excluded.availability_status,
      is_verified         = excluded.is_verified,
      is_inventory_item   = excluded.is_inventory_item,
      load_kind           = excluded.load_kind,
      load_min            = excluded.load_min,
      load_max            = excluded.load_max,
      load_step           = excluded.load_step,
      load_unit           = excluded.load_unit,
      load_increments_lb  = excluded.load_increments_lb,
      notes               = excluded.notes;


-- -----------------------------------------------------------------------------
-- 4. Catalog
-- -----------------------------------------------------------------------------

-- 4a. Dumbbell work that only needed "a bench" pointed at the barbell
--     stations in 0007 because no plain bench was known. There are 5
--     adjustable benches; use them and leave the barbell stations free.
update public.exercises
   set required_equipment = array_replace(
         array_replace(required_equipment, 'bench_press', 'adjustable_bench'),
         'incline_bench_press', 'adjustable_bench')
 where slug in (
   'dumbbell_bench_press', 'incline_dumbbell_press', 'one_arm_dumbbell_row',
   'chest_supported_dumbbell_row', 'dumbbell_rear_delt_fly', 'dumbbell_skull_crusher',
   'bench_dip', 'bulgarian_split_squat', 'dumbbell_step_up', 'dumbbell_wrist_curl'
 );

-- 4b. Barbell hinges move from the (absent) squat rack to the platform.
update public.exercises
   set required_equipment = '{deadlift_platform}'
 where slug in ('barbell_deadlift', 'barbell_romanian_deadlift');

-- 4c. Retire what has no equipment now. Retired, not deleted: logged sets
--     reference these rows, and the history screens still need their names.
update public.exercises
   set is_active = false,
       notes = 'Retired 2026-10-19: no free squat rack at Pennington. Use smith_machine_squat.'
 where slug = 'barbell_back_squat';
update public.exercises
   set is_active = false,
       notes = 'Retired 2026-10-19: Pennington has a hip thrust machine. Use machine_hip_thrust.'
 where slug = 'barbell_hip_thrust';
update public.exercises
   set is_active = false,
       notes = 'Retired 2026-10-19: Pennington''s leg curl is seated. Use seated_leg_curl.'
 where slug = 'lying_hamstring_curl';

-- 4d. Notes and names that described the old, incomplete inventory.
update public.exercises set name = 'Hammer Strength Iso-Lateral Row', notes = null
 where slug = 'machine_back_row';
update public.exercises set notes = 'Dual Axis Row / Rear Delt machine, rear-delt setting.'
 where slug = 'machine_rear_delt_fly';
update public.exercises set notes = null
 where slug in (
   'barbell_bench_press', 'incline_barbell_bench_press', 'barbell_romanian_deadlift',
   'tricep_pushdown_rope', 'dumbbell_standing_calf_raise', 'bodyweight_calf_raise',
   'dumbbell_sumo_squat', 'bodyweight_cossack_squat', 'plank', 'lying_leg_raise',
   'cable_crunch', 'bench_dip', 'dumbbell_step_up', 'goblet_squat', 'push_up'
 );
update public.exercises set notes = 'Erector spinae has no 3D geometry; mapped to glutes + hamstrings so the map is not blank after a deadlift day.'
 where slug = 'barbell_deadlift';
update public.exercises set notes = 'Needs an ankle cuff on the adjustable cable column. The hip adduction machine is the easier option.'
 where slug = 'cable_hip_adduction';
update public.exercises set notes = 'Steady-state. Treadmills, ellipticals and bikes are the indoor alternative.'
 where slug = 'outdoor_easy_run';

-- 4e. New exercises for the machines on the real list.
-- Column order as in 0007:
--   slug, name, primary, secondary, unmapped, required_equipment,
--   movement_pattern, is_outdoor, notes
-- Same rule as 0007: only the 16 renderable groups in primary/secondary.
insert into public.exercises
  (slug, name,
   primary_muscle_groups, secondary_muscle_groups, unmapped_muscle_groups,
   required_equipment, movement_pattern, is_outdoor, notes)
values

-- ---- Chest -------------------------------------------------------------------
('smith_machine_bench_press',  'Smith Machine Bench Press',   '{chest_lower}', '{triceps,delts_front}',     '{}', '{smith_machine,adjustable_bench}', 'horizontal_push', false, null),
('decline_barbell_bench_press','Decline Barbell Bench Press', '{chest_lower}', '{triceps,delts_front}',     '{}', '{decline_bench_press}',            'horizontal_push', false, null),
('machine_chest_press',        'Dual Axis Chest Press',       '{chest_lower}', '{triceps,delts_front}',     '{}', '{dual_axis_chest_press}',          'horizontal_push', false, null),
('machine_incline_press',      'Machine Incline Press',       '{chest_upper}', '{delts_front,triceps}',     '{}', '{incline_press_machine}',          'horizontal_push', false, null),
('cable_crossover',            'Cable Crossover',             '{chest_lower}', '{chest_upper,delts_front}', '{}', '{functional_trainer}',             'isolation',       false, null),
('parallel_bar_dip',           'Dip',                         '{triceps,chest_lower}', '{delts_front}',     '{}', '{dip_station}',                    'vertical_push',   false, null),

-- ---- Back --------------------------------------------------------------------
('pull_up',                'Pull-Up',            '{lats}',             '{biceps,forearms,delts_rear}', '{rhomboids}',                '{pull_up_bar}',             'vertical_pull',   false, null),
('chin_up',                'Chin-Up',            '{lats,biceps}',      '{forearms}',                   '{}',                         '{pull_up_bar}',             'vertical_pull',   false, null),
('dual_axis_pulldown',     'Dual Axis Pulldown', '{lats}',             '{biceps,delts_rear}',          '{}',                         '{dual_axis_pulldown}',      'vertical_pull',   false, null),
('dual_axis_row',          'Dual Axis Row',      '{lats}',             '{biceps,delts_rear}',          '{rhomboids}',                '{dual_axis_row_rear_delt}', 'horizontal_pull', false, null),
('t_bar_row',              'T-Bar Row',          '{lats}',             '{biceps,delts_rear,forearms}', '{rhomboids,erector_spinae}', '{t_bar_row}',               'horizontal_pull', false, null),
('machine_back_extension', 'Back Extension',     '{glutes,hamstrings}','{}',                           '{erector_spinae}',           '{back_extension_machine}',  'hinge',           false, 'Lower back has no 3D geometry; shown on the map as glutes + hamstrings.'),
('glute_ham_raise',        'Glute-Ham Raise',    '{hamstrings}',       '{glutes,calves}',              '{}',                         '{glute_ham_developer}',     'hinge',           false, null),

-- ---- Shoulders ---------------------------------------------------------------
('machine_shoulder_press',          'Dual Axis Overhead Press',       '{delts_front}', '{delts_side,triceps}',             '{}', '{dual_axis_overhead_press}',                 'vertical_push', false, null),
('barbell_shoulder_press',          'Barbell Shoulder Press',         '{delts_front}', '{delts_side,triceps,traps_upper}', '{}', '{barbell_shoulder_press}',                   'vertical_push', false, null),
('seated_dumbbell_shoulder_press',  'Seated Dumbbell Shoulder Press', '{delts_front}', '{delts_side,triceps}',             '{}', '{dumbbell_pair,seated_shoulder_press_bench}','vertical_push', false, null),
('machine_lateral_raise',           'Machine Lateral Raise',          '{delts_side}',  '{traps_upper}',                    '{}', '{lateral_raise_machine}',                    'isolation',     false, null),

-- ---- Arms --------------------------------------------------------------------
('machine_arm_curl',      'Machine Arm Curl',      '{biceps}',  '{forearms}', '{}', '{arm_curl_machine}',             'isolation', false, null),
('machine_arm_extension', 'Machine Arm Extension', '{triceps}', '{}',         '{}', '{arm_extension_machine}',        'isolation', false, null),
('preacher_curl',         'Preacher Curl',         '{biceps}',  '{forearms}', '{}', '{preacher_curl}',                'isolation', false, null),
('ez_bar_curl',           'EZ Bar Curl',           '{biceps}',  '{forearms}', '{}', '{ez_curl_bar}',                  'isolation', false, null),
('ez_bar_skull_crusher',  'EZ Bar Skull Crusher',  '{triceps}', '{}',         '{}', '{ez_curl_bar,adjustable_bench}', 'isolation', false, null),
('barbell_curl',          'Barbell Curl',          '{biceps}',  '{forearms}', '{}', '{fixed_barbell}',                'isolation', false, 'Fixed-weight straight bar, 20-110 lb.'),

-- ---- Legs --------------------------------------------------------------------
('smith_machine_squat',   'Smith Machine Squat',                '{quads}',     '{glutes,hamstrings,adductors}', '{}', '{smith_machine}',               'squat',     false, null),
('leg_press',             'Leg Press (Precor)',                 '{quads}',     '{glutes,hamstrings,adductors}', '{}', '{leg_press_selectorized}',      'squat',     false, null),
('seated_leg_press',      'Seated Leg Press',                   '{quads}',     '{glutes,hamstrings,adductors}', '{}', '{seated_leg_press}',            'squat',     false, null),
('iso_lateral_leg_press', 'Iso-Lateral Leg Press',              '{quads}',     '{glutes,hamstrings,adductors}', '{}', '{hammer_iso_leg_press}',        'squat',     false, null),
('single_leg_press',      'Single-Leg Iso-Lateral Leg Press',   '{quads}',     '{glutes,hamstrings}',           '{}', '{hammer_iso_leg_press_single}', 'squat',     false, null),
('angled_leg_press',      'Angled Leg Press',                   '{quads}',     '{glutes,hamstrings,adductors}', '{}', '{angled_leg_press}',            'squat',     false, null),
('seated_leg_curl',       'Seated Leg Curl',                    '{hamstrings}','{calves}',                      '{}', '{seated_leg_curl}',             'isolation', false, null),
('machine_hip_adduction', 'Hip Adduction Machine',              '{adductors}', '{}',                            '{}', '{hip_adduction_machine}',       'isolation', false, null),
('machine_hip_abduction', 'Hip Abduction Machine',              '{glutes}',    '{}',                            '{}', '{hip_abduction_machine}',       'isolation', false, 'Trains the outer hip (glute medius); shown on the map as glutes.'),
('machine_hip_thrust',    'Hip Thrust Machine',                 '{glutes}',    '{hamstrings}',                  '{}', '{hip_thrust_machine}',          'hinge',     false, null),
('machine_glute_kickback','Glute Kickback Machine',             '{glutes}',    '{hamstrings}',                  '{}', '{kickback_machine}',            'isolation', false, null),
('rotary_hip_extension',  'Rotary Hip Extension',               '{glutes}',    '{hamstrings}',                  '{}', '{rotary_hip}',                  'isolation', false, 'The rotary hip machine supports several hip movements; this is the extension setting.'),
('rotary_calf_raise',     'Rotary Calf Raise',                  '{calves}',    '{}',                            '{}', '{rotary_calf}',                 'isolation', false, null),
('seated_calf_raise',     'Seated Calf Raise',                  '{calves}',    '{}',                            '{}', '{seated_calf_raise}',           'isolation', false, null),
('kettlebell_swing',      'Kettlebell Swing',                   '{glutes,hamstrings}', '{abs,forearms}',        '{erector_spinae}', '{kettlebells}',         'hinge',     false, null),
('kettlebell_goblet_squat','Kettlebell Goblet Squat',           '{quads}',     '{glutes,abs}',                  '{}', '{kettlebells}',                 'squat',     false, null),

-- ---- Core --------------------------------------------------------------------
('machine_ab_crunch',      'Ab Crunch Machine',      '{abs}',      '{}',                   '{}',          '{ab_crunch_machine}',   'core', false, null),
('machine_torso_rotation', 'Torso Rotation Machine', '{abs}',      '{}',                   '{obliques}',  '{torso_rotation}',      'core', false, 'Obliques have no 3D geometry; shown on the map as abs.'),
('decline_sit_up',         'Decline Sit-Up',         '{abs}',      '{}',                   '{}',          '{decline_ab_bench}',    'core', false, null),
('feet_elevated_crunch',   'Feet-Elevated Crunch',   '{abs}',      '{}',                   '{}',          '{feet_elevated_crunch}','core', false, null),
('hanging_leg_raise',      'Hanging Leg Raise',      '{abs}',      '{forearms}',           '{obliques}',  '{pull_up_bar}',         'core', false, null),
('medicine_ball_slam',     'Medicine Ball Slam',     '{abs,lats}', '{delts_front,triceps}','{}',          '{medicine_balls}',      'core', false, null),

-- ---- Indoor cardio (log minutes as reps) ---------------------------------------
('treadmill_run',      'Treadmill Run',  '{quads,calves}',  '{hamstrings,glutes}',                '{tibialis_anterior}', '{treadmill}',      'cardio', false, 'Log minutes as reps.'),
('elliptical_session', 'Elliptical',     '{quads}',         '{glutes,hamstrings,calves}',         '{}',                  '{elliptical}',     'cardio', false, 'Log minutes as reps.'),
('indoor_cycling',     'Indoor Cycling', '{quads}',         '{hamstrings,glutes,calves}',         '{}',                  '{indoor_cycle}',   'cardio', false, 'Log minutes as reps.'),
('stairmaster_climb',  'StairMaster',    '{quads,glutes}',  '{calves,hamstrings}',                '{}',                  '{stairmaster}',    'cardio', false, 'Log minutes as reps.'),
('rowing_machine_row', 'Rowing Machine', '{lats,quads}',    '{biceps,delts_rear,hamstrings,glutes}','{rhomboids}',       '{rowing_machine}', 'cardio', false, 'Log minutes as reps.')

on conflict (slug) do nothing;


-- -----------------------------------------------------------------------------
-- 5. Rollup
-- -----------------------------------------------------------------------------
-- No muscle mapping of an existing exercise changed above (only equipment,
-- names and notes), so muscle_group_intensity is still correct and no rebuild
-- is needed. If you edit a mapping later, run:
--   select public.rebuild_all_muscle_group_intensity();


-- =============================================================================
-- Checks to run after applying (each should return zero rows):
--
--   -- every exercise's equipment exists
--   select e.slug, x.slug_missing
--     from public.exercises e
--     cross join lateral unnest(e.required_equipment) as x(slug_missing)
--    where not exists (select 1 from public.rec_center_equipment r
--                       where r.equipment_type = x.slug_missing);
--
--   -- every active exercise's equipment is actually on the floor
--   select e.slug from public.exercises e
--    where e.is_active
--      and exists (select 1 from unnest(e.required_equipment) s
--                   join public.rec_center_equipment r on r.equipment_type = s
--                  where r.availability_status = 'out_of_service');
--
--   -- every muscle group still has a primary exercise
--   select g from unnest(enum_range(null::public.muscle_group)) g
--    where not exists (select 1 from public.exercises e
--                       where e.is_active and e.primary_muscle_groups @> array[g]);
-- =============================================================================
