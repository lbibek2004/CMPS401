-- =============================================================================
-- LionFit  |  0007  |  SEED: exercises (starter catalog, 59 rows)
-- =============================================================================
-- Depends on: 0006 -- every slug in required_equipment below exists in
-- rec_center_equipment, so seed order matters.
--
-- Column order in the VALUES list:
--   slug, name,
--   primary_muscle_groups, secondary_muscle_groups, unmapped_muscle_groups,
--   required_equipment, movement_pattern, is_outdoor, notes
--
-- Array literals are written in Postgres short form ('{a,b}'); Postgres coerces
-- them to the column's enum/text array type on insert.
--
-- -----------------------------------------------------------------------------
-- Three rules this catalog follows. Read them before adding rows.
-- -----------------------------------------------------------------------------
-- 1. primary/secondary_muscle_groups contain ONLY the 16 renderable groups.
--    Anything the 3D model cannot draw goes in unmapped_muscle_groups:
--      rows            -> lats          (+ rhomboids recorded as unmapped)
--      twists / planks -> abs           (+ obliques recorded as unmapped)
--      deadlift        -> glutes + hamstrings (+ erector_spinae unmapped)
--    These fallbacks are the ones CHECKLIST.md proposes. The volume is never
--    dropped; it is just attributed to a muscle the user can actually see light
--    up, with the true target kept alongside it.
--
-- 2. CALVES, ADDUCTORS AND ABS HAVE NO DEDICATED MACHINE in the current
--    inventory (docs/rec-center-equipment.md says so outright, and the
--    CHECKLIST flags it). Every row for those three groups therefore uses
--    dumbbells, bodyweight, an adjustable cable station, or outdoor work. If
--    the floor walk turns up a calf raise / adductor machine / ab station, add
--    machine rows then -- do not guess now. Glutes are thin for the same reason
--    (no hip thrust station): barbell_hip_thrust borrows a bench and a rack.
--
-- 3. No pull-ups, chin-ups or hanging leg raises. A pull-up bar is NOT in the
--    inventory doc and inventing one would put an exercise in someone's plan
--    that they cannot perform. Lats are covered by the pulldowns and rows
--    instead. Add them after the floor walk.
--
-- ASSUMPTION, stated once and applying to every barbell row below: the
-- squat_rack and bench_press / incline_bench_press stations come with a
-- loadable barbell. The doc does not say so (open questions 3 and 4) and has no
-- plate denominations, so barbell load suggestions cannot be rounded to real
-- plates yet. Dumbbell rows do not have this problem -- their denominations are
-- recorded on the dumbbell_pair row in migration 0006.
--
-- ON CONFLICT (slug) DO NOTHING so re-running never clobbers an admin's edits.
-- =============================================================================

insert into public.exercises
  (slug, name,
   primary_muscle_groups, secondary_muscle_groups, unmapped_muscle_groups,
   required_equipment, movement_pattern, is_outdoor, notes)
values

-- ---- Chest -------------------------------------------------------------------
('barbell_bench_press',        'Barbell Bench Press',          '{chest_lower}', '{triceps,delts_front}',    '{}', '{bench_press}',                      'horizontal_push', false, 'Assumes a loadable barbell at the bench station -- unconfirmed.'),
('incline_barbell_bench_press','Incline Barbell Bench Press',  '{chest_upper}', '{delts_front,triceps}',    '{}', '{incline_bench_press}',              'horizontal_push', false, 'Assumes a loadable barbell at the incline station -- unconfirmed.'),
('dumbbell_bench_press',       'Dumbbell Bench Press',         '{chest_lower}', '{triceps,delts_front}',    '{}', '{dumbbell_pair,bench_press}',        'horizontal_push', false, null),
('incline_dumbbell_press',     'Incline Dumbbell Press',       '{chest_upper}', '{delts_front,triceps}',    '{}', '{dumbbell_pair,incline_bench_press}','horizontal_push', false, null),
('pec_deck_fly',               'Pec Deck Fly',                 '{chest_lower}', '{chest_upper,delts_front}','{}', '{pec_deck_fly}',                     'isolation',       false, 'Only one in the building -- the swap engine should expect it to be busy.'),
('cable_fly_high_to_low',      'Cable Fly (High to Low)',      '{chest_lower}', '{chest_upper,delts_front}','{}', '{adjustable_cable_station}',         'isolation',       false, null),
('cable_fly_low_to_high',      'Cable Fly (Low to High)',      '{chest_upper}', '{delts_front}',            '{}', '{adjustable_cable_station}',         'isolation',       false, null),
('push_up',                    'Push-Up',                      '{chest_lower}', '{triceps,delts_front,abs}','{}', '{bodyweight}',                       'horizontal_push', false, 'Always available -- the fallback when every bench and cable is taken.'),

-- ---- Back --------------------------------------------------------------------
('lat_pulldown_wide_grip',     'Lat Pulldown (Wide Grip)',     '{lats}', '{biceps,delts_rear}',             '{}',          '{lat_pulldown}',             'vertical_pull',   false, 'Wide attachment is documented as available.'),
('lat_pulldown_close_grip',    'Lat Pulldown (Close Grip)',    '{lats}', '{biceps,forearms}',               '{}',          '{lat_pulldown}',             'vertical_pull',   false, 'Close attachment is documented as available.'),
('lat_pulldown_neutral_grip',  'Lat Pulldown (Neutral Grip)',  '{lats}', '{biceps}',                        '{}',          '{lat_pulldown}',             'vertical_pull',   false, 'Neutral attachment is documented as available.'),
('seated_cable_row',           'Seated Cable Row',             '{lats}', '{biceps,delts_rear,traps_upper}', '{rhomboids}', '{cable_row}',                'horizontal_pull', false, 'Rhomboids are the real target of the squeeze but have no 3D geometry -- mapped to lats on the model.'),
('machine_back_row',           'Machine Back Row',             '{lats}', '{biceps,delts_rear}',             '{rhomboids}', '{back_row}',                 'horizontal_pull', false, null),
('one_arm_dumbbell_row',       'One-Arm Dumbbell Row',         '{lats}', '{biceps,delts_rear,forearms}',    '{rhomboids}', '{dumbbell_pair,bench_press}','horizontal_pull', false, null),
('chest_supported_dumbbell_row','Chest-Supported Dumbbell Row','{lats}', '{delts_rear,biceps}',             '{rhomboids}', '{dumbbell_pair,incline_bench_press}','horizontal_pull', false, null),

-- ---- Shoulders ---------------------------------------------------------------
('dumbbell_overhead_press',    'Dumbbell Overhead Press',      '{delts_front}', '{delts_side,triceps,traps_upper}', '{}',          '{dumbbell_pair}',                    'vertical_push',   false, null),
('dumbbell_lateral_raise',     'Dumbbell Lateral Raise',       '{delts_side}',  '{traps_upper}',                    '{}',          '{dumbbell_pair}',                    'isolation',       false, null),
('cable_lateral_raise',        'Cable Lateral Raise',          '{delts_side}',  '{traps_upper}',                    '{}',          '{adjustable_cable_station}',         'isolation',       false, null),
('machine_rear_delt_fly',      'Machine Rear Delt Fly',        '{delts_rear}',  '{traps_upper}',                    '{rhomboids}', '{rear_delt_fly}',                    'isolation',       false, null),
('dumbbell_rear_delt_fly',     'Dumbbell Rear Delt Fly',       '{delts_rear}',  '{traps_upper}',                    '{rhomboids}', '{dumbbell_pair,incline_bench_press}','isolation',       false, 'Chest-supported on an incline bench.'),
('cable_face_pull',            'Cable Face Pull',              '{delts_rear}',  '{traps_upper,biceps}',             '{rhomboids}', '{adjustable_cable_station}',         'horizontal_pull', false, null),
('dumbbell_front_raise',       'Dumbbell Front Raise',         '{delts_front}', '{}',                               '{}',          '{dumbbell_pair}',                    'isolation',       false, null),
('dumbbell_shrug',             'Dumbbell Shrug',               '{traps_upper}', '{forearms}',                       '{}',          '{dumbbell_pair}',                    'isolation',       false, 'Only traps_upper row in the catalog -- the model has no lower/mid trap geometry.'),

-- ---- Arms --------------------------------------------------------------------
('tricep_pushdown_rope',       'Tricep Pushdown (Rope)',       '{triceps}',         '{}',                 '{}', '{tricep_pushdown}',          'isolation', false, 'Four stations, 2 height-adjustable -- the least likely machine in the gym to be occupied.'),
('overhead_cable_tricep_extension','Overhead Cable Tricep Extension','{triceps}',  '{}',                 '{}', '{adjustable_cable_station}', 'isolation', false, null),
('dumbbell_skull_crusher',     'Dumbbell Skull Crusher',       '{triceps}',         '{}',                 '{}', '{dumbbell_pair,bench_press}','isolation', false, null),
('bench_dip',                  'Bench Dip',                    '{triceps}',         '{chest_lower,delts_front}','{}','{bench_press}',         'isolation', false, 'Uses the bench only -- no dip station is listed in the inventory.'),
('dumbbell_biceps_curl',       'Dumbbell Biceps Curl',         '{biceps}',          '{forearms}',         '{}', '{dumbbell_pair}',            'isolation', false, null),
('dumbbell_hammer_curl',       'Dumbbell Hammer Curl',         '{biceps,forearms}', '{}',                 '{}', '{dumbbell_pair}',            'isolation', false, null),
('cable_biceps_curl',          'Cable Biceps Curl',            '{biceps}',          '{forearms}',         '{}', '{adjustable_cable_station}', 'isolation', false, null),
('dumbbell_wrist_curl',        'Dumbbell Wrist Curl',          '{forearms}',        '{}',                 '{}', '{dumbbell_pair,bench_press}','isolation', false, 'Forearms are otherwise only incidental volume.'),
('dumbbell_farmer_carry',      'Dumbbell Farmer Carry',        '{forearms}',        '{traps_upper,abs,glutes}','{erector_spinae}','{dumbbell_pair}','carry', false, 'Loaded carry; heavy dumbbells, walk a set distance.'),

-- ---- Legs --------------------------------------------------------------------
('barbell_back_squat',         'Barbell Back Squat',           '{quads}',             '{glutes,hamstrings,abs}',        '{erector_spinae}', '{squat_rack}',                'squat',     false, 'Assumes a loadable barbell at the rack -- unconfirmed.'),
('goblet_squat',               'Goblet Squat',                 '{quads}',             '{glutes,abs}',                   '{}',               '{dumbbell_pair}',             'squat',     false, 'Dumbbell squat pattern for when all 4 racks are taken.'),
('bulgarian_split_squat',      'Bulgarian Split Squat',        '{quads}',             '{glutes,hamstrings,adductors}',  '{}',               '{dumbbell_pair,bench_press}', 'lunge',     false, null),
('dumbbell_walking_lunge',     'Dumbbell Walking Lunge',       '{quads}',             '{glutes,hamstrings,adductors}',  '{}',               '{dumbbell_pair}',             'lunge',     false, null),
('dumbbell_step_up',           'Dumbbell Step-Up',             '{quads}',             '{glutes,calves}',                '{}',               '{dumbbell_pair,bench_press}', 'lunge',     false, 'Steps onto a flat bench -- no plyo box is listed.'),
('leg_extension',              'Leg Extension',                '{quads}',             '{}',                             '{}',               '{leg_extension}',             'isolation', false, null),
('lying_hamstring_curl',       'Lying Hamstring Curl',         '{hamstrings}',        '{calves}',                       '{}',               '{hamstring_curl}',            'isolation', false, null),
('barbell_romanian_deadlift',  'Barbell Romanian Deadlift',    '{hamstrings}',        '{glutes,forearms}',              '{erector_spinae}', '{squat_rack}',                'hinge',     false, 'Assumes a loadable barbell -- unconfirmed.'),
('dumbbell_romanian_deadlift', 'Dumbbell Romanian Deadlift',   '{hamstrings}',        '{glutes,forearms}',              '{erector_spinae}', '{dumbbell_pair}',             'hinge',     false, null),
('barbell_deadlift',           'Barbell Deadlift',             '{glutes,hamstrings}', '{quads,lats,traps_upper,forearms}','{erector_spinae}','{squat_rack}',               'hinge',     false, 'Erector spinae has no 3D geometry; mapped to glutes + hamstrings per CHECKLIST.md so the map is not blank after a deadlift day.'),
('barbell_hip_thrust',         'Barbell Hip Thrust',           '{glutes}',            '{hamstrings}',                   '{}',               '{squat_rack,bench_press}',    'hinge',     false, 'No hip thrust station in the inventory -- bar plus a flat bench. Glute coverage is thin for exactly this reason.'),
('dumbbell_glute_bridge',      'Dumbbell Glute Bridge',        '{glutes}',            '{hamstrings}',                   '{}',               '{dumbbell_pair}',             'hinge',     false, 'Floor version; needs no bench.'),
('cable_pull_through',         'Cable Pull-Through',           '{glutes}',            '{hamstrings}',                   '{erector_spinae}', '{adjustable_cable_station}',  'hinge',     false, null),

-- ---- Calves (NO CALF MACHINE IN THE INVENTORY) --------------------------------
('dumbbell_standing_calf_raise','Dumbbell Standing Calf Raise','{calves}', '{}', '{}', '{dumbbell_pair}', 'isolation', false, 'No calf raise machine is listed at Pennington -- dumbbell and bodyweight versions are the only coverage this group has.'),
('bodyweight_calf_raise',      'Single-Leg Calf Raise',        '{calves}', '{}', '{}', '{bodyweight}',    'isolation', false, 'Bodyweight substitute for the missing calf machine.'),

-- ---- Adductors (NO ADDUCTOR MACHINE IN THE INVENTORY) -------------------------
('dumbbell_sumo_squat',        'Dumbbell Sumo Squat',          '{adductors,quads}', '{glutes}',       '{}', '{dumbbell_pair}',            'squat',     false, 'No adductor machine is listed -- wide-stance loading is the substitute.'),
('bodyweight_cossack_squat',   'Cossack Squat',                '{adductors}',       '{quads,glutes}', '{}', '{bodyweight}',               'lunge',     false, 'Bodyweight adductor work; no machine exists for this group.'),
('cable_hip_adduction',        'Cable Hip Adduction',          '{adductors}',       '{glutes}',       '{}', '{adjustable_cable_station}', 'isolation', false, 'Needs a low pulley and an ankle cuff; cuff availability is NOT confirmed in the inventory doc.'),

-- ---- Abs (NO AB STATION IN THE INVENTORY) -------------------------------------
('plank',                      'Plank',                        '{abs}', '{delts_front,glutes}', '{}',          '{bodyweight}',               'core', false, 'No ab station is listed at Pennington -- all core work here is bodyweight or cable.'),
('side_plank',                 'Side Plank',                   '{abs}', '{delts_side}',         '{obliques}',  '{bodyweight}',               'core', false, 'Obliques have no 3D geometry; shown on the map as abs.'),
('lying_leg_raise',            'Lying Leg Raise',              '{abs}', '{quads}',              '{}',          '{bodyweight}',               'core', false, 'Floor version -- there is no pull-up bar in the inventory for a hanging variant.'),
('cable_crunch',               'Cable Crunch',                 '{abs}', '{}',                   '{}',          '{adjustable_cable_station}', 'core', false, 'The only loadable (progressable) ab movement available.'),
('dumbbell_russian_twist',     'Dumbbell Russian Twist',       '{abs}', '{}',                   '{obliques}',  '{dumbbell_pair}',            'core', false, 'Obliques have no 3D geometry; shown on the map as abs.'),
('cable_woodchop',             'Cable Woodchop',               '{abs}', '{delts_front}',        '{obliques}',  '{adjustable_cable_station}', 'core', false, 'Obliques have no 3D geometry; shown on the map as abs.'),

-- ---- Outdoor -----------------------------------------------------------------
-- No cardio equipment is catalogued at all (open question 7), so every cardio
-- row in this seed is outdoor. If treadmills/bikes/rowers turn up on the floor
-- walk, add indoor cardio rows then.
('outdoor_easy_run',           'Outdoor Easy Run',             '{quads,calves}',           '{hamstrings,glutes}',      '{tibialis_anterior}', '{outdoor}',           'cardio', true, 'Steady-state. Primary cardio option for weight-loss plans until indoor cardio equipment is confirmed.'),
('outdoor_hill_sprints',       'Outdoor Hill Sprints',         '{quads,calves}',           '{glutes,hamstrings}',      '{}',                  '{outdoor}',           'cardio', true, 'High intensity intervals.'),
('outdoor_bodyweight_circuit', 'Outdoor Bodyweight Circuit',   '{quads,chest_lower,abs}',  '{glutes,triceps,delts_front}','{}',               '{outdoor,bodyweight}','cardio', true, 'Push-ups, squats, planks, carries. Works when the Rec Center is closed or packed.')

on conflict (slug) do nothing;


-- =============================================================================
-- Coverage check, for whoever extends this catalog.
-- =============================================================================
-- Every one of the 16 renderable muscle groups appears as a PRIMARY group on at
-- least one row above (verify with the query below after seeding -- it should
-- return zero rows):
--
--   select g
--   from unnest(enum_range(null::public.muscle_group)) g
--   where not exists (
--     select 1 from public.exercises e
--     where e.primary_muscle_groups @> array[g]::public.muscle_group[]
--   );
--
-- The thin ones, and why:
--   traps_upper  1 row   -- shrugs; no trap-specific machine exists
--   adductors    3 rows  -- no adductor machine in the inventory
--   calves       2 rows  -- no calf raise machine in the inventory
--   glutes       4 rows  -- no hip thrust or glute machine in the inventory
-- These are inventory gaps, not oversights. Fix them by answering open
-- questions 5 and 6 in docs/rec-center-equipment.md, then adding machine rows.
-- =============================================================================
