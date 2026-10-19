-- =============================================================================
-- LionFit  |  0001  |  Enums and shared helper functions
-- =============================================================================
-- Run order matters. This file creates every enum type the rest of the schema
-- depends on, plus one trivial trigger helper. Nothing here references a table.
--
-- Idempotency note for anyone pasting this into the dashboard SQL editor:
-- Postgres has no `CREATE TYPE IF NOT EXISTS`, so each type is wrapped in a
-- DO block that swallows the "already exists" error. Re-running this file is
-- therefore harmless.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- muscle_group  --  THE 16 KEYS ARE A CONTRACT WITH assets/muscleAnatomy.glb
-- -----------------------------------------------------------------------------
-- These sixteen strings are the *material names* inside the GLB. The 3D muscle
-- map colors the model by writing baseColorFactor on a material looked up by
-- this exact string.
--
--   !!  IF THIS ENUM AND THE GLB MATERIAL NAMES EVER DRIFT, THE MUSCLE MAP   !!
--   !!  FAILS SILENTLY: no error, no crash -- the muscle simply never        !!
--   !!  changes color, and it looks like the logging feature is broken.      !!
--
-- Re-verify after every Blender re-export with:
--     node tool/inspect_glb.js assets/muscleAnatomy.glb
-- Any change here needs a matching change there, in the same commit.
-- -----------------------------------------------------------------------------
do $$
begin
  create type public.muscle_group as enum (
    'abs',
    'adductors',
    'biceps',
    'calves',
    'chest_lower',
    'chest_upper',
    'delts_front',
    'delts_rear',
    'delts_side',
    'forearms',
    'glutes',
    'hamstrings',
    'lats',
    'quads',
    'traps_upper',
    'triceps'
  );
exception
  when duplicate_object then null;
end
$$;

comment on type public.muscle_group is
  'The 16 colorable material names in assets/muscleAnatomy.glb. Verbatim contract with the 3D asset -- verify with tool/inspect_glb.js. Drift here breaks the muscle map silently.';


-- -----------------------------------------------------------------------------
-- unmapped_muscle_group  --  the four groups the 3D model has no geometry for
-- -----------------------------------------------------------------------------
-- DECISION (and the reasoning, because this one is easy to get wrong later):
--
-- Four muscle groups a lifting app genuinely needs have NO geometry in the GLB:
-- erector spinae (deadlift, good morning, back extension), obliques (side bend,
-- Russian twist, woodchop), rhomboids / mid-traps (every row), and tibialis
-- anterior (shin work).
--
-- Option A -- add them to public.muscle_group and flag them "not renderable".
--   Rejected. Every consumer of the enum would then need a renderable/not-
--   renderable filter, and the repaint loop (16 baseColorFactor writes) would
--   have to skip 4 of 20 values. Miss that filter in one place and you are
--   looking up a material that does not exist -- which is the exact silent
--   no-op failure mode this schema is trying to design away. It would also make
--   the enum stop being a verbatim mirror of the asset, which is the one
--   property that makes the contract checkable by a script.
--
-- Option B -- drop the volume on the floor.
--   Rejected. CLAUDE.md is explicit: "a deadlift that lights up nothing reads
--   as a bug to the user."
--
-- Option C (CHOSEN) -- keep public.muscle_group at exactly 16, map each
--   exercise's primary/secondary groups onto the nearest group that DOES have
--   geometry, and record the true anatomical target separately in this second
--   enum via exercises.unmapped_muscle_groups.
--     * The map always colors something sensible (rows -> lats,
--       obliques work -> abs, deadlift -> glutes + hamstrings; these fallbacks
--       are the ones suggested in CHECKLIST.md).
--     * Nothing is lost: the UI can still print "also trains: erector spinae"
--       from exercises.unmapped_muscle_groups.
--     * The 3D code never sees a value it cannot render.
--
-- Migration path if the geometry is ever added in Blender: add the value to
-- public.muscle_group (ALTER TYPE ... ADD VALUE), move the exercise rows over,
-- re-export the GLB, and run the rollup rebuild function from migration 0005.
-- -----------------------------------------------------------------------------
do $$
begin
  create type public.unmapped_muscle_group as enum (
    'erector_spinae',
    'obliques',
    'rhomboids',
    'tibialis_anterior'
  );
exception
  when duplicate_object then null;
end
$$;

comment on type public.unmapped_muscle_group is
  'Muscle groups with no geometry in muscleAnatomy.glb. Recorded on exercises so the volume is not lost, but never written to muscle_group_intensity and never sent to the renderer.';


-- -----------------------------------------------------------------------------
-- Remaining enums. Enums, not free text, so a typo is a hard error at insert
-- time rather than a row that quietly never matches a filter.
-- -----------------------------------------------------------------------------

-- member is the default for every signup; admin is a content-management role
-- only (see migration 0003) -- it is NOT elevated access to other users' data.
do $$
begin
  create type public.user_role as enum ('member', 'admin');
exception
  when duplicate_object then null;
end
$$;

-- Set types, per CLAUDE.md -> Feature scope -> Logging.
do $$
begin
  create type public.set_type as enum ('warm_up', 'working', 'drop_set', 'super_set');
exception
  when duplicate_object then null;
end
$$;

-- The three plan goals the generator supports.
do $$
begin
  create type public.training_goal as enum ('weight_loss', 'muscle_gain', 'general_fitness');
exception
  when duplicate_object then null;
end
$$;

-- Display/entry unit. Weight is STORED as entered plus a generated canonical
-- pound value (see migration 0004) so math never has to guess.
do $$
begin
  create type public.weight_unit as enum ('lb', 'kg');
exception
  when duplicate_object then null;
end
$$;

-- RPE (rate of perceived exertion, 1-10) or RIR (reps in reserve) -- user picks
-- one; the logger shows that field and hides the other.
do $$
begin
  create type public.effort_preference as enum ('rpe', 'rir');
exception
  when duplicate_object then null;
end
$$;

-- Equipment status.
--   available      -- believed present and usable
--   occupied       -- transient live state; nothing writes this yet, it exists
--                     for the future "machine likely occupied" heuristic
--   out_of_service  -- broken / removed
--   unknown         -- we genuinely do not know (not the same as broken)
do $$
begin
  create type public.equipment_availability as enum
    ('available', 'occupied', 'out_of_service', 'unknown');
exception
  when duplicate_object then null;
end
$$;

-- Where a health row came from. The app must be fully usable with no wearable,
-- so 'manual' is the default.
do $$
begin
  create type public.health_data_source as enum ('manual', 'fitbit', 'platform');
exception
  when duplicate_object then null;
end
$$;

-- Coarse movement classification, used by the plan generator to balance a week
-- (do not give someone four horizontal pushes and no pull).
do $$
begin
  create type public.movement_pattern as enum (
    'squat',
    'hinge',
    'lunge',
    'horizontal_push',
    'vertical_push',
    'horizontal_pull',
    'vertical_pull',
    'carry',
    'isolation',
    'core',
    'cardio'
  );
exception
  when duplicate_object then null;
end
$$;


-- -----------------------------------------------------------------------------
-- set_updated_at() -- stamps updated_at on every UPDATE.
-- -----------------------------------------------------------------------------
-- `set search_path = ''` is deliberate on every function in this schema: it
-- stops a caller from shadowing a function or table name with something in
-- their own schema. The cost is that every reference has to be fully qualified
-- (public.foo, auth.uid()). pg_catalog is always implicitly searched, so bare
-- now() still resolves.
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'BEFORE UPDATE trigger helper: keeps updated_at honest without trusting the client to send it.';
