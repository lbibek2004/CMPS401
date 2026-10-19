-- =============================================================================
-- LionFit — full schema, all migrations concatenated in order.
--
-- GENERATED FILE. Do not edit. Regenerate with:
--   node tool/build_combined_sql.js      (or re-concatenate supabase/migrations/*.sql)
--
-- HOW TO APPLY (no CLI, no credentials to share):
--   1. Supabase dashboard -> SQL Editor -> New query
--   2. Paste this entire file
--   3. Run
--
-- Safe to re-run: types are guarded, tables use "if not exists", policies are
-- dropped before being recreated.
-- =============================================================================


-- ==========================================================================
-- SOURCE: 20261011000001_enums_and_helpers.sql
-- ==========================================================================

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


-- ==========================================================================
-- SOURCE: 20261011000002_profiles_and_auth.sql
-- ==========================================================================

-- =============================================================================
-- LionFit  |  0002  |  profiles, the role model, and the signup trigger
-- =============================================================================
-- Depends on: 0001 (enums).
--
-- This is the security-critical file. Read the comments before changing it.
--
-- The whole admin model rests on three facts:
--   1. The role lives in public.profiles.role -- NEVER in
--      auth.users.raw_user_meta_data, which the client can write. A user who
--      could set their own metadata could promote themselves to admin.
--   2. Clients are not granted UPDATE on the role column at all, and the RLS
--      UPDATE policy re-checks it anyway. Two independent locks.
--   3. Admin means "may write the shared reference tables" (migration 0003).
--      It does NOT mean "may read other people's data". No policy anywhere in
--      this schema gives an admin access to another user's rows.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- profiles -- exactly one row per auth.users row.
-- -----------------------------------------------------------------------------
-- CLAUDE.md mentions a possible separate user_preferences table. For now the
-- preference columns live here: it is one row per user either way, and a second
-- table would mean a second RLS policy set and a join on app start for no gain.
-- Split it out later if preferences grow past a handful of columns.
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  display_name       text not null
                       constraint profiles_display_name_len
                       check (char_length(display_name) between 1 and 60),
  role               public.user_role        not null default 'member',
  unit_preference    public.weight_unit      not null default 'lb',
  effort_preference  public.effort_preference not null default 'rpe',
  goal               public.training_goal    not null default 'general_fitness',
  -- 3 is the floor, 7 the ceiling (CLAUDE.md -> Feature scope -> Planning).
  days_per_week      smallint not null default 3
                       constraint profiles_days_per_week_range
                       check (days_per_week between 3 and 7),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.profiles is
  'One row per auth user. Carries display name, role, and UI preferences. Users sign in with email; display_name is what the UI calls them.';
comment on column public.profiles.role is
  'member or admin. Clients have no UPDATE privilege on this column -- promotion is a service-role / SQL-editor operation. See supabase/README.md.';
comment on column public.profiles.unit_preference is
  'Display unit only. Logged weight is stored as entered plus a canonical weight_lb (workout_logs); conversion happens at the UI boundary.';

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- is_admin() -- the one place RLS asks "is the caller an admin?"
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER is not decoration here. If a policy on `exercises` ran a
-- plain `select role from profiles where id = auth.uid()`, that inner select
-- would itself be filtered by profiles' own RLS policies -- policy evaluation
-- recursing into policy evaluation. SECURITY DEFINER runs the body as the
-- function owner (postgres), who is exempt from RLS, so the lookup is a plain
-- indexed read and there is no recursion.
--
-- STABLE lets Postgres call it once per statement instead of once per row.
-- -----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'::public.user_role
  );
$$;

comment on function public.is_admin() is
  'True when the calling user has profiles.role = admin. SECURITY DEFINER so RLS policies do not recurse through profiles RLS. Content-management only -- never used to widen access to another user''s rows.';

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;


-- -----------------------------------------------------------------------------
-- current_profile_role() -- the role as currently STORED for the caller.
-- -----------------------------------------------------------------------------
-- Used by the profiles UPDATE policy to prove the submitted row did not change
-- the role. Being STABLE, it reads the statement's snapshot, i.e. the row as it
-- was BEFORE the UPDATE -- which is exactly the comparison we want.
-- -----------------------------------------------------------------------------
create or replace function public.current_profile_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = auth.uid();
$$;

revoke all on function public.current_profile_role() from public;
grant execute on function public.current_profile_role() to authenticated;


-- -----------------------------------------------------------------------------
-- RLS on profiles
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;

-- LOCK 1 (privileges): the client role may not write the role column at all.
-- Supabase grants ALL on new public tables to anon/authenticated by default,
-- and a table-wide grant cannot be narrowed column by column -- so we revoke
-- the table-level write privileges first and then re-grant only the columns a
-- member is allowed to touch.
--
--   >> IF YOU ADD A COLUMN TO profiles, ADD IT TO THESE TWO GRANTS <<
--   >> or the app will fail with "permission denied for column".  <<
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant insert (id, display_name, unit_preference, effort_preference, goal, days_per_week)
  on table public.profiles to authenticated;
grant update (display_name, unit_preference, effort_preference, goal, days_per_week)
  on table public.profiles to authenticated;
-- No DELETE grant: a profile dies with its auth.users row (ON DELETE CASCADE).

-- LOCK 2 (RLS): a user sees and edits exactly one row -- their own.
--
-- Note the `(select auth.uid())` wrapping. It is not cosmetic: the subselect
-- form is evaluated once per statement instead of once per row, which matters
-- on the bigger tables and is the pattern Supabase's own performance advisor
-- asks for. We use it consistently everywhere in this schema.

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));
-- Deliberately NO admin branch. Admin is content management; there is no
-- in-app user directory, so an admin has no reason to read other profiles.

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert to authenticated
  with check (
    id = (select auth.uid())
    -- Belt and braces: even though `role` is not in the INSERT grant above,
    -- state the rule in the policy too. A self-created profile is a member.
    and role = 'member'::public.user_role
  );
-- Normally the signup trigger below has already created the row; this policy
-- exists so the app can self-heal an account that predates the trigger.

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (
    id = (select auth.uid())
    -- The anti-self-promotion rule, stated declaratively: the role in the row
    -- being written must equal the role already stored for this user.
    and role = (select public.current_profile_role())
  );

-- No DELETE policy, matching the absent DELETE grant.


-- -----------------------------------------------------------------------------
-- handle_new_user() -- create the profile row when someone signs up.
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER because the trigger fires inside Supabase's auth code, in a
-- transaction that has no app user context yet; the insert has to run as the
-- owner. Fully qualified names + empty search_path keep that safe.
--
-- display_name comes from raw_user_meta_data->>'display_name' (that is the key
-- lib/core/auth/auth_controller.dart sends on signUp), falling back to the
-- local part of the email, then to a constant so the NOT NULL never trips.
--
-- NOTE WHAT IS *NOT* READ HERE: raw_user_meta_data->>'role'. That blob is
-- client-writable. If this trigger honoured it, anyone could sign up with
-- {"role":"admin"} and own the reference tables. The role column is left to
-- its 'member' default, always.
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Lion'
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'AFTER INSERT ON auth.users: creates the matching public.profiles row. Ignores any role key in raw_user_meta_data -- role is never client-supplied.';

-- Creating a trigger on auth.users needs ownership of that table. `supabase db
-- push` and the dashboard SQL editor both connect as postgres, so this works.
-- If you ever get "must be owner of relation users", you are running as the
-- wrong role -- use the SQL editor.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- -----------------------------------------------------------------------------
-- Backfill: any account that signed up before this trigger existed.
-- -----------------------------------------------------------------------------
insert into public.profiles (id, display_name)
select
  u.id,
  coalesce(
    nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
    'Lion'
  )
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;


-- ==========================================================================
-- SOURCE: 20261011000003_reference_tables.sql
-- ==========================================================================

-- =============================================================================
-- LionFit  |  0003  |  Shared reference data: exercises, rec_center_equipment
-- =============================================================================
-- Depends on: 0001 (enums), 0002 (is_admin).
--
-- These two tables are the same for every user. Members read them; only an
-- admin writes them. That is the entire meaning of "admin" in this app.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- rec_center_equipment -- the Pennington inventory.
-- -----------------------------------------------------------------------------
-- Seeded in migration 0006 from docs/rec-center-equipment.md. That doc is
-- explicitly PARTIAL and from memory; keep the two in sync, and if they drift,
-- the doc wins and the seed gets regenerated.
-- -----------------------------------------------------------------------------
create table if not exists public.rec_center_equipment (
  id                  uuid primary key default gen_random_uuid(),

  -- Stable machine-readable key. This is what exercises.required_equipment
  -- holds, so renaming one means rewriting the other.
  equipment_type      text not null unique
                        constraint rec_center_equipment_type_format
                        check (equipment_type ~ '^[a-z][a-z0-9_]*$'),

  -- Human label for the UI ("Lat Pulldown"); equipment_type is for code.
  label               text not null,

  -- NULL means "we know it exists, we do not know how many". Not the same as 0.
  quantity            integer
                        constraint rec_center_equipment_quantity_nonneg
                        check (quantity is null or quantity >= 0),

  availability_status public.equipment_availability not null default 'unknown',

  -- false = recalled from memory, not confirmed on the floor. Every seeded row
  -- starts false; flip to true after the walk-through. The UI should be able to
  -- say "unverified" rather than pretending the list is authoritative.
  is_verified         boolean not null default false,

  -- false for the two non-gym sentinels ('bodyweight', 'outdoor'), which exist
  -- so that required_equipment is never empty and so the substitution query can
  -- be one uniform array containment test. Exclude them from inventory reports.
  is_inventory_item   boolean not null default true,

  -- Load quantization table, in pounds, for equipment that comes in fixed
  -- denominations. Populated for dumbbells from the denominations in
  -- docs/rec-center-equipment.md. The load-progression math MUST round to one
  -- of these -- suggesting 42.5 lb when the rack jumps 40 -> 45 is a bug the
  -- user feels immediately.
  load_increments_lb  numeric(6,2)[],

  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.rec_center_equipment is
  'Pennington Student Activity Center inventory. Source of truth: docs/rec-center-equipment.md (PARTIAL, unverified). Members read; admins write.';

drop trigger if exists rec_center_equipment_set_updated_at on public.rec_center_equipment;
create trigger rec_center_equipment_set_updated_at
  before update on public.rec_center_equipment
  for each row execute function public.set_updated_at();

create index if not exists idx_rec_center_equipment_availability
  on public.rec_center_equipment (availability_status)
  where is_inventory_item;


-- -----------------------------------------------------------------------------
-- exercises -- the catalog.
-- -----------------------------------------------------------------------------
create table if not exists public.exercises (
  id                      uuid primary key default gen_random_uuid(),

  -- Stable key used by seeds, tests, and the plan generator. The display name
  -- can be reworded without breaking anything; the slug cannot.
  slug                    text not null unique
                            constraint exercises_slug_format
                            check (slug ~ '^[a-z][a-z0-9_]*$'),
  name                    text not null,

  -- Renderable groups only -- these drive the 3D map.
  primary_muscle_groups   public.muscle_group[] not null
                            constraint exercises_primary_not_empty
                            check (array_length(primary_muscle_groups, 1) >= 1),
  secondary_muscle_groups public.muscle_group[] not null default '{}',

  -- The true anatomical target(s) that the GLB cannot draw. See the long
  -- decision note on public.unmapped_muscle_group in migration 0001. The UI can
  -- surface these as text ("also trains: erector spinae"); the renderer never
  -- sees them and the rollup never stores them.
  unmapped_muscle_groups  public.unmapped_muscle_group[] not null default '{}',

  -- Array of rec_center_equipment.equipment_type values. Postgres cannot put a
  -- foreign key on array elements, so this is enforced by convention + the seed
  -- order (equipment is seeded first). Two sentinel values are always present
  -- in the equipment table: 'bodyweight' and 'outdoor'.
  --
  -- The substitution query ("this machine is taken, what else works?") is then:
  --   select * from exercises
  --   where primary_muscle_groups && array['chest_lower']::muscle_group[]
  --     and required_equipment <@ (
  --       select array_agg(equipment_type) from rec_center_equipment
  --       where availability_status = 'available')
  --     and is_active;
  required_equipment      text[] not null default '{}',

  movement_pattern        public.movement_pattern not null,
  is_outdoor              boolean not null default false,

  -- Soft delete. workout_logs references exercises with ON DELETE RESTRICT, so
  -- an exercise anyone has ever logged cannot be deleted -- retire it instead.
  is_active               boolean not null default true,

  notes                   text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table public.exercises is
  'Exercise catalog. primary/secondary muscle groups are restricted to the 16 renderable groups; anything the 3D model cannot draw goes in unmapped_muscle_groups.';
comment on column public.exercises.required_equipment is
  'rec_center_equipment.equipment_type slugs, plus the sentinels bodyweight and outdoor. Not a real FK -- Postgres cannot FK array elements.';

drop trigger if exists exercises_set_updated_at on public.exercises;
create trigger exercises_set_updated_at
  before update on public.exercises
  for each row execute function public.set_updated_at();

-- GIN indexes: both of these columns are searched with array operators
-- (&& overlaps, <@ contained-by), which only a GIN index can serve.
create index if not exists idx_exercises_primary_muscle_groups
  on public.exercises using gin (primary_muscle_groups);
create index if not exists idx_exercises_required_equipment
  on public.exercises using gin (required_equipment);
create index if not exists idx_exercises_movement_pattern
  on public.exercises (movement_pattern) where is_active;


-- =============================================================================
-- RLS -- the member/admin split
-- =============================================================================
-- CLAUDE.md -> Auth model:
--      |  exercises / rec_center_equipment  |  other users' data
--   member |  read                           |  none
--   admin  |  read + write                   |  none  (<- note: still none)
--
-- A table with RLS enabled and no policies denies everything. That is broken,
-- not secure, so every verb below gets a real policy.
-- =============================================================================

alter table public.exercises           enable row level security;
alter table public.rec_center_equipment enable row level security;

-- Privileges: writes are *also* gated by RLS below, but granting them here is
-- what lets an admin's write reach the policy check at all.
revoke all on table public.exercises from anon, authenticated;
grant select, insert, update, delete on table public.exercises to authenticated;

revoke all on table public.rec_center_equipment from anon, authenticated;
grant select, insert, update, delete on table public.rec_center_equipment to authenticated;

-- anon gets nothing: the app requires a login before any screen loads data.


-- ---- exercises ---------------------------------------------------------------

drop policy if exists exercises_select_authenticated on public.exercises;
create policy exercises_select_authenticated on public.exercises
  for select to authenticated
  using (true);                                   -- every signed-in user reads

drop policy if exists exercises_insert_admin on public.exercises;
create policy exercises_insert_admin on public.exercises
  for insert to authenticated
  with check ((select public.is_admin()));        -- admins only

drop policy if exists exercises_update_admin on public.exercises;
create policy exercises_update_admin on public.exercises
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists exercises_delete_admin on public.exercises;
create policy exercises_delete_admin on public.exercises
  for delete to authenticated
  using ((select public.is_admin()));


-- ---- rec_center_equipment ----------------------------------------------------

drop policy if exists rec_center_equipment_select_authenticated on public.rec_center_equipment;
create policy rec_center_equipment_select_authenticated on public.rec_center_equipment
  for select to authenticated
  using (true);

drop policy if exists rec_center_equipment_insert_admin on public.rec_center_equipment;
create policy rec_center_equipment_insert_admin on public.rec_center_equipment
  for insert to authenticated
  with check ((select public.is_admin()));

drop policy if exists rec_center_equipment_update_admin on public.rec_center_equipment;
create policy rec_center_equipment_update_admin on public.rec_center_equipment
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists rec_center_equipment_delete_admin on public.rec_center_equipment;
create policy rec_center_equipment_delete_admin on public.rec_center_equipment
  for delete to authenticated
  using ((select public.is_admin()));


-- ==========================================================================
-- SOURCE: 20261011000004_workout_tables.sql
-- ==========================================================================

-- =============================================================================
-- LionFit  |  0004  |  User-owned data: workouts, set logs, health metrics
-- =============================================================================
-- Depends on: 0001 (enums), 0002 (profiles/auth), 0003 (exercises).
--
-- Everything in this file is private to one user. The RLS at the bottom is the
-- privacy boundary CLAUDE.md -> Auth model demands:
--
--   >> THERE IS NO is_admin() ANYWHERE IN THIS FILE, ON PURPOSE. <<
--   >> An admin reading another member's sets or heart rate is a privacy <<
--   >> breach, not a feature. The only predicate is "this row is mine".  <<
-- =============================================================================


-- -----------------------------------------------------------------------------
-- user_workouts -- one planned or completed session.
-- -----------------------------------------------------------------------------
create table if not exists public.user_workouts (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,

  -- A plain date, not a timestamp: this is the calendar day the session belongs
  -- to. Timezone-free on purpose -- "Tuesday's workout" must not drift across a
  -- UTC boundary just because the user logged at 11pm.
  scheduled_date  date not null,

  -- NULL = planned but not finished. Set when the user closes the session.
  completed_at    timestamptz,

  goal            public.training_goal not null default 'general_fitness',

  -- 0-based week inside the generated block, used for week-over-week variation.
  week_index      integer not null default 0
                    constraint user_workouts_week_index_nonneg check (week_index >= 0),

  -- Which variation of the plan this session is ('push_a', 'upper_b', ...).
  -- Free text: the generator owns the vocabulary and it is still moving.
  plan_variation  text,

  title           text,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- Not redundant with the primary key: it is the target of the composite
  -- foreign key on workout_logs below, which is what makes it impossible for a
  -- set row to claim a different owner than its parent session.
  constraint user_workouts_id_user_key unique (id, user_id)
);

comment on table public.user_workouts is
  'A planned or completed training session for one user. completed_at NULL means still planned.';

drop trigger if exists user_workouts_set_updated_at on public.user_workouts;
create trigger user_workouts_set_updated_at
  before update on public.user_workouts
  for each row execute function public.set_updated_at();

create index if not exists idx_user_workouts_user_date
  on public.user_workouts (user_id, scheduled_date desc);

create index if not exists idx_user_workouts_user_completed
  on public.user_workouts (user_id, completed_at desc)
  where completed_at is not null;


-- -----------------------------------------------------------------------------
-- workout_logs -- ONE ROW PER SET. This is the table that grows.
-- -----------------------------------------------------------------------------
create table if not exists public.workout_logs (
  id              uuid primary key default gen_random_uuid(),

  workout_id      uuid not null,

  -- Denormalized from the parent session. Two reasons, both load-bearing:
  --   1. RLS: `user_id = auth.uid()` is an index lookup. The alternative
  --      (`exists (select 1 from user_workouts ...)`) runs a subquery per row
  --      on the biggest table in the schema.
  --   2. The rollup in migration 0005 can recompute a day without joining back
  --      to user_workouts -- which matters when the parent has been deleted and
  --      these rows are disappearing by cascade.
  -- It cannot drift: the composite FK below forces it to match the parent, and
  -- the BEFORE trigger overwrites whatever the client sent.
  user_id         uuid not null references auth.users (id) on delete cascade,

  -- Also denormalized from user_workouts.scheduled_date, same reasoning.
  -- Maintained by trigger; never trusted from the client.
  performed_on    date not null,

  -- RESTRICT, not CASCADE: deleting an exercise someone has logged would silently
  -- erase their history. Retire it with is_active = false instead.
  exercise_id     uuid not null references public.exercises (id) on delete restrict,

  set_index       smallint not null
                    constraint workout_logs_set_index_positive check (set_index >= 1),
  set_type        public.set_type not null default 'working',

  -- Weight AS THE USER ENTERED IT, with the unit they entered it in. The
  -- canonical pound value is the generated column below, so nothing downstream
  -- has to remember to convert. NULL weight = bodyweight / unweighted.
  weight          numeric(7,2)
                    constraint workout_logs_weight_nonneg check (weight is null or weight >= 0),
  unit            public.weight_unit not null default 'lb',

  reps            smallint
                    constraint workout_logs_reps_range check (reps is null or reps between 0 and 1000),

  -- RPE 1-10 (half points allowed) or RIR 0-10. The user picks which one the
  -- logger shows (profiles.effort_preference); both columns are allowed to be
  -- populated because rpe ~= 10 - rir and a client may compute the other.
  rpe             numeric(3,1)
                    constraint workout_logs_rpe_range check (rpe is null or (rpe >= 1 and rpe <= 10)),
  rir             smallint
                    constraint workout_logs_rir_range check (rir is null or (rir between 0 and 10)),

  -- Sets sharing a superset_group are performed back to back. Only meaningful
  -- when set_type = 'super_set'.
  superset_group  smallint,

  -- Offline sync idempotency key, generated on the device BEFORE the set is
  -- sent. "The gym has bad signal" (CLAUDE.md -> Conventions): a retry after a
  -- dropped connection reuses the same client_uuid, and the unique constraint
  -- below turns a double-send into a no-op instead of a duplicate set.
  client_uuid     uuid not null default gen_random_uuid(),

  -- Wall-clock moment the set happened (drives rest timers and ordering within
  -- a session). The muscle map buckets by performed_on, not by this.
  performed_at    timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- Canonical pounds. Generated, so it can never disagree with weight/unit.
  weight_lb       numeric generated always as (
                    case when unit = 'kg' then round(weight * 2.20462262185, 4) else weight end
                  ) stored,

  -- Tonnage for this set, in pounds. The rollup and the progress charts read
  -- this instead of recomputing the conversion every time.
  volume_lb       numeric generated always as (
                    coalesce(
                      case when unit = 'kg' then weight * 2.20462262185 else weight end,
                      0
                    ) * coalesce(reps, 0)
                  ) stored,

  -- A set belongs to a session, and inherits that session's owner. Pointing the
  -- FK at (id, user_id) instead of just (id) is what makes "my log row, your
  -- workout" a constraint violation rather than a policy puzzle.
  constraint workout_logs_workout_fkey
    foreign key (workout_id, user_id)
    references public.user_workouts (id, user_id) on delete cascade,

  -- The idempotency guarantee described above.
  constraint workout_logs_client_uuid_key unique (user_id, client_uuid)
);

comment on table public.workout_logs is
  'One row per performed set. weight/unit are as entered; weight_lb and volume_lb are generated canonical pounds. client_uuid makes offline resends idempotent.';
comment on column public.workout_logs.performed_on is
  'Calendar day of the parent session, denormalized. Maintained by trigger -- client values are overwritten.';

drop trigger if exists workout_logs_set_updated_at on public.workout_logs;
create trigger workout_logs_set_updated_at
  before update on public.workout_logs
  for each row execute function public.set_updated_at();


-- ---- Indexes on the actual query paths ---------------------------------------
-- (Not "index everything". Each of these answers a screen.)

-- The session screen: every set in this workout, in the order it was logged.
create index if not exists idx_workout_logs_workout_created
  on public.workout_logs (workout_id, created_at);

-- History / rollup: this user's sets over a date window.
create index if not exists idx_workout_logs_user_performed_on
  on public.workout_logs (user_id, performed_on desc);

-- The per-exercise progress line graph: this user, this lift, over time.
create index if not exists idx_workout_logs_user_exercise
  on public.workout_logs (user_id, exercise_id, performed_on desc);

-- Makes the ON DELETE RESTRICT check on exercises cheap, and answers
-- "is anyone using this exercise?" for the admin catalog screen.
create index if not exists idx_workout_logs_exercise
  on public.workout_logs (exercise_id);


-- -----------------------------------------------------------------------------
-- Keeping user_id / performed_on honest.
-- -----------------------------------------------------------------------------
-- Both are copies of the parent session's values, so the client never gets to
-- supply them. The trigger reads the parent and overwrites.
--
-- Security note: this runs BEFORE the RLS WITH CHECK, which is what makes it a
-- lock and not just a convenience. If a malicious client posts a set into
-- someone else's workout_id, this trigger stamps the row with the *victim's*
-- user_id, and the INSERT policy's `user_id = auth.uid()` then rejects it.
-- -----------------------------------------------------------------------------
create or replace function public.workout_logs_inherit_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_date    date;
begin
  select w.user_id, w.scheduled_date
    into v_user_id, v_date
  from public.user_workouts w
  where w.id = new.workout_id;

  if v_user_id is null then
    raise exception 'workout_logs.workout_id % does not exist', new.workout_id
      using errcode = 'foreign_key_violation';
  end if;

  new.user_id     := v_user_id;
  new.performed_on := v_date;
  return new;
end;
$$;

revoke all on function public.workout_logs_inherit_parent() from public;

drop trigger if exists workout_logs_inherit_parent on public.workout_logs;
create trigger workout_logs_inherit_parent
  before insert or update on public.workout_logs
  for each row execute function public.workout_logs_inherit_parent();


-- If the session is moved to another day, its set rows move with it. The
-- resulting UPDATE on workout_logs is what re-triggers the muscle-map rollup
-- for both the old and the new day (migration 0005).
create or replace function public.user_workouts_resync_logs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.workout_logs
     set performed_on = new.scheduled_date
   where workout_id = new.id
     and performed_on is distinct from new.scheduled_date;
  return null;
end;
$$;

revoke all on function public.user_workouts_resync_logs() from public;

drop trigger if exists user_workouts_resync_logs on public.user_workouts;
create trigger user_workouts_resync_logs
  after update of scheduled_date on public.user_workouts
  for each row
  when (old.scheduled_date is distinct from new.scheduled_date)
  execute function public.user_workouts_resync_logs();


-- -----------------------------------------------------------------------------
-- user_health_metrics -- Fitbit / manual / platform health data.
-- -----------------------------------------------------------------------------
-- The app must be fully usable with zero wearables connected, so every column
-- is nullable and 'manual' is the default source.
-- -----------------------------------------------------------------------------
create table if not exists public.user_health_metrics (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users (id) on delete cascade,
  day                date not null,

  resting_heart_rate smallint
                       constraint user_health_metrics_rhr_range
                       check (resting_heart_rate is null or resting_heart_rate between 20 and 250),
  average_heart_rate smallint
                       constraint user_health_metrics_ahr_range
                       check (average_heart_rate is null or average_heart_rate between 20 and 250),
  steps              integer
                       constraint user_health_metrics_steps_nonneg
                       check (steps is null or steps >= 0),
  active_minutes     integer
                       constraint user_health_metrics_active_minutes_nonneg
                       check (active_minutes is null or active_minutes >= 0),
  sleep_minutes      integer
                       constraint user_health_metrics_sleep_minutes_nonneg
                       check (sleep_minutes is null or sleep_minutes >= 0),

  body_weight        numeric(6,2)
                       constraint user_health_metrics_body_weight_nonneg
                       check (body_weight is null or body_weight > 0),
  body_weight_unit   public.weight_unit not null default 'lb',

  source             public.health_data_source not null default 'manual',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  -- One row per user per day per source, so a Fitbit sync upserts cleanly and
  -- does not fight a manual entry for the same day.
  constraint user_health_metrics_user_day_source_key unique (user_id, day, source)
);

comment on table public.user_health_metrics is
  'Daily health rollup per source. Private to the user -- no admin read path, same as workout data.';

drop trigger if exists user_health_metrics_set_updated_at on public.user_health_metrics;
create trigger user_health_metrics_set_updated_at
  before update on public.user_health_metrics
  for each row execute function public.set_updated_at();

create index if not exists idx_user_health_metrics_user_day
  on public.user_health_metrics (user_id, day desc);


-- =============================================================================
-- RLS -- "this row is mine", and nothing else
-- =============================================================================
-- Same four policies on all three tables. Written out per table rather than
-- generated in a loop so that `select * from pg_policies` reads like the spec.
--
-- The USING clause controls which existing rows you can see/affect; the
-- WITH CHECK clause controls what the row is allowed to look like after you
-- write it. INSERT needs only WITH CHECK, DELETE needs only USING, UPDATE needs
-- both (otherwise you could take a row you own and hand it to someone else).
-- =============================================================================

alter table public.user_workouts        enable row level security;
alter table public.workout_logs         enable row level security;
alter table public.user_health_metrics  enable row level security;

revoke all on table public.user_workouts from anon, authenticated;
grant select, insert, update, delete on table public.user_workouts to authenticated;

revoke all on table public.workout_logs from anon, authenticated;
grant select, insert, update, delete on table public.workout_logs to authenticated;

revoke all on table public.user_health_metrics from anon, authenticated;
grant select, insert, update, delete on table public.user_health_metrics to authenticated;


-- ---- user_workouts -----------------------------------------------------------

drop policy if exists user_workouts_select_own on public.user_workouts;
create policy user_workouts_select_own on public.user_workouts
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_workouts_insert_own on public.user_workouts;
create policy user_workouts_insert_own on public.user_workouts
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists user_workouts_update_own on public.user_workouts;
create policy user_workouts_update_own on public.user_workouts
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists user_workouts_delete_own on public.user_workouts;
create policy user_workouts_delete_own on public.user_workouts
  for delete to authenticated
  using (user_id = (select auth.uid()));


-- ---- workout_logs ------------------------------------------------------------
-- user_id is stamped from the parent session by the BEFORE trigger above, so
-- these checks are evaluated against the true owner, not against whatever the
-- client claimed.

drop policy if exists workout_logs_select_own on public.workout_logs;
create policy workout_logs_select_own on public.workout_logs
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists workout_logs_insert_own on public.workout_logs;
create policy workout_logs_insert_own on public.workout_logs
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists workout_logs_update_own on public.workout_logs;
create policy workout_logs_update_own on public.workout_logs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists workout_logs_delete_own on public.workout_logs;
create policy workout_logs_delete_own on public.workout_logs
  for delete to authenticated
  using (user_id = (select auth.uid()));


-- ---- user_health_metrics -----------------------------------------------------

drop policy if exists user_health_metrics_select_own on public.user_health_metrics;
create policy user_health_metrics_select_own on public.user_health_metrics
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_health_metrics_insert_own on public.user_health_metrics;
create policy user_health_metrics_insert_own on public.user_health_metrics
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists user_health_metrics_update_own on public.user_health_metrics;
create policy user_health_metrics_update_own on public.user_health_metrics
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists user_health_metrics_delete_own on public.user_health_metrics;
create policy user_health_metrics_delete_own on public.user_health_metrics
  for delete to authenticated
  using (user_id = (select auth.uid()));


-- ==========================================================================
-- SOURCE: 20261011000005_muscle_group_intensity.sql
-- ==========================================================================

-- =============================================================================
-- LionFit  |  0005  |  muscle_group_intensity -- the 3D map's rollup
-- =============================================================================
-- Depends on: 0001 (enums), 0003 (exercises), 0004 (workout_logs).
--
-- -----------------------------------------------------------------------------
-- DECISION: trigger-maintained table.  Not a materialized view, not on-read.
-- -----------------------------------------------------------------------------
-- The hot path is "colour the model for the last N days", 1 <= N <= 30, and the
-- user changes N with a slider -- so the query fires repeatedly, interactively,
-- while someone watches a 3D model that is already costing the frame budget.
--
-- Option A -- compute on read.
--   Every slider move would scan this user's workout_logs for the window, join
--   exercises, unnest two muscle-group arrays per row, aggregate, and normalize.
--   Correct, and fine on day one with 40 rows. It gets slower exactly as a user
--   becomes more invested in the app, which is the worst possible scaling curve
--   for a feature whose whole job is to make progress feel visible.
--
-- Option B -- materialized view.
--   Rejected for one hard reason and one soft one.
--   HARD: Postgres does not apply row-level security to materialized views. A
--   matview holding every user's training data would need wrapper views and
--   careful grants to avoid being a cross-user leak -- we would be hand-building
--   the privacy boundary that RLS gives us for free on a real table, in the one
--   place CLAUDE.md is strictest about privacy.
--   SOFT: REFRESH MATERIALIZED VIEW recomputes *every* user, cannot be scoped to
--   the one who just logged a set, and needs a scheduler. The data would also be
--   stale right after logging -- the moment the user most wants to look at it.
--
-- Option C (CHOSEN) -- a real table maintained by triggers on workout_logs.
--   Writes are tiny and rare: a set every 60-90 seconds during a session.
--   Reads are frequent and latency-sensitive. Pay on write, read a PK range
--   scan of at most 16 x 30 = 480 narrow rows. Being an ordinary table it gets
--   ordinary RLS, so the privacy rule is the same one sentence as everywhere
--   else. And because the triggers are statement-level with transition tables,
--   an offline-sync flush of 40 queued sets costs ONE recompute per affected
--   day, not 40.
--
--   The cost of this choice: a derived table can drift from its source if
--   something writes workout_logs in a way the triggers miss, or if an admin
--   edits an exercise's muscle mapping. Mitigations: the recompute is a full
--   recompute of the affected (user, day) rather than incremental delta
--   arithmetic (so it is self-correcting, not self-accumulating), and
--   public.rebuild_all_muscle_group_intensity() at the bottom rebuilds
--   everything after a catalog edit.
-- =============================================================================


create table if not exists public.muscle_group_intensity (
  user_id              uuid not null references auth.users (id) on delete cascade,

  -- Calendar day, copied from workout_logs.performed_on (which is the parent
  -- session's scheduled_date). Timezone-free, matches what the calendar shows.
  day                  date not null,

  muscle_group         public.muscle_group not null,

  -- 0..1, RELATIVE TO THE HARDEST-HIT GROUP ON THIS SAME DAY. So a day with one
  -- exercise has a 1.000 in it. That is intentional: it answers "what did this
  -- session emphasise?".
  --
  -- For a MULTI-DAY window (the 1-30 day map), do NOT average this column --
  -- normalize total_volume across the window instead:
  --     select muscle_group, sum(total_volume) v
  --       from muscle_group_intensity
  --      where user_id = auth.uid() and day >= current_date - 13
  --      group by muscle_group;
  --   then divide each v by max(v). At most 480 rows; it is free.
  normalized_intensity numeric(4,3) not null default 0
                         constraint muscle_group_intensity_normalized_range
                         check (normalized_intensity >= 0 and normalized_intensity <= 1),

  -- Absolute tonnage in POUNDS attributed to this group on this day. This is
  -- the authoritative number; normalized_intensity is derived from it.
  total_volume         numeric(12,2) not null default 0
                         constraint muscle_group_intensity_total_volume_nonneg
                         check (total_volume >= 0),

  -- How many sets touched this group (primary or secondary), counted once per
  -- set. Fallback basis for bodyweight-only days, where total_volume is 0.
  set_count            integer not null default 0
                         constraint muscle_group_intensity_set_count_nonneg
                         check (set_count >= 0),

  updated_at           timestamptz not null default now(),

  -- The primary key IS the index for the hot path. Column order matters:
  -- (user_id, day) is the leftmost prefix, so
  --     where user_id = $1 and day between $2 and $3
  -- is a single range scan over this index. A separate
  -- `create index ... (user_id, day)` would be redundant with it and would just
  -- cost another index to maintain on every write.
  constraint muscle_group_intensity_pkey primary key (user_id, day, muscle_group)
);

comment on table public.muscle_group_intensity is
  'Derived rollup feeding the 3D muscle map. Maintained by triggers on workout_logs -- clients read it, never write it. See the decision note at the top of migration 0005.';


-- -----------------------------------------------------------------------------
-- recompute_muscle_group_intensity(user, day)
-- -----------------------------------------------------------------------------
-- Full recompute of one (user, day) cell. Full, not incremental: a day holds a
-- few dozen sets at most, and delta arithmetic is how derived tables silently
-- drift out of sync with their source over months.
--
-- SECURITY DEFINER: the trigger runs as the logging user, who has no write
-- privilege on muscle_group_intensity at all (see the grants below). Running as
-- the owner is what lets the rollup be written while the table stays read-only
-- to every client. It is parameterised by the trigger with the row's own
-- user_id, and it only ever reads that user's rows, so it cannot leak across
-- users even if someone found a way to call it directly (EXECUTE is revoked).
--
-- Secondary muscle groups count at 0.5x. One constant, stated once, here.
-- Warm-up sets are included: volume is weight x reps, so a light warm-up barely
-- moves the number, and filtering by set type would mean the map disagrees with
-- the volume shown on the session screen.
-- -----------------------------------------------------------------------------
create or replace function public.recompute_muscle_group_intensity(p_user_id uuid, p_day date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.muscle_group_intensity
   where user_id = p_user_id
     and day = p_day;

  with contributions as (
    -- primary groups, full weight
    select l.id                     as log_id,
           mg.g                     as muscle_group,
           1.0::numeric             as factor,
           coalesce(l.volume_lb, 0) as volume
      from public.workout_logs l
      join public.exercises e on e.id = l.exercise_id
      cross join lateral unnest(e.primary_muscle_groups) as mg(g)
     where l.user_id = p_user_id
       and l.performed_on = p_day

    union all

    -- secondary groups, half weight
    select l.id,
           mg.g,
           0.5::numeric,
           coalesce(l.volume_lb, 0)
      from public.workout_logs l
      join public.exercises e on e.id = l.exercise_id
      cross join lateral unnest(e.secondary_muscle_groups) as mg(g)
     where l.user_id = p_user_id
       and l.performed_on = p_day
  ),
  agg as (
    select c.muscle_group,
           round(sum(c.volume * c.factor), 2) as total_volume,
           count(distinct c.log_id)::integer  as set_count
      from contributions c
     group by c.muscle_group
  ),
  scale as (
    select max(a.total_volume) as max_volume,
           max(a.set_count)    as max_sets
      from agg a
  )
  insert into public.muscle_group_intensity
    (user_id, day, muscle_group, total_volume, set_count, normalized_intensity, updated_at)
  select p_user_id,
         p_day,
         a.muscle_group,
         a.total_volume,
         a.set_count,
         case
           -- Normal case: relative tonnage.
           when s.max_volume > 0 then round(a.total_volume / s.max_volume, 3)
           -- Bodyweight-only day (planks, push-ups): tonnage is 0 for every
           -- group, so fall back to set counts. Without this the model would
           -- render completely cold after a real session, which reads as a bug.
           when s.max_sets > 0   then round(a.set_count::numeric / s.max_sets, 3)
           else 0
         end,
         now()
    from agg a
    cross join scale s;
end;
$$;

comment on function public.recompute_muscle_group_intensity(uuid, date) is
  'Full recompute of one user-day of the muscle map rollup. Called by the workout_logs statement triggers.';

revoke all on function public.recompute_muscle_group_intensity(uuid, date) from public;
-- No GRANT EXECUTE to authenticated: clients never call this. Trigger functions
-- do not need EXECUTE privilege on the calling role to fire.


-- -----------------------------------------------------------------------------
-- The triggers.
-- -----------------------------------------------------------------------------
-- FOR EACH STATEMENT with transition tables (REFERENCING ... TABLE AS ...),
-- not FOR EACH ROW. The offline sync engine flushes a whole session at once;
-- row-level triggers would recompute the same day 40 times for one INSERT.
-- Statement-level sees all changed rows at once and recomputes each affected
-- (user, day) exactly once.
-- -----------------------------------------------------------------------------
create or replace function public.workout_logs_rollup_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select distinct c.user_id, c.performed_on
      from changed_rows c
  loop
    perform public.recompute_muscle_group_intensity(r.user_id, r.performed_on);
  end loop;
  return null;
end;
$$;

-- UPDATE needs both sides: a set edited from Monday to Tuesday invalidates both
-- days, and a changed weight/reps/exercise invalidates the day it sits on.
create or replace function public.workout_logs_rollup_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select distinct s.user_id, s.performed_on
      from (
        select o.user_id, o.performed_on from old_rows o
        union all
        select n.user_id, n.performed_on from new_rows n
      ) s
  loop
    perform public.recompute_muscle_group_intensity(r.user_id, r.performed_on);
  end loop;
  return null;
end;
$$;

revoke all on function public.workout_logs_rollup_changed() from public;
revoke all on function public.workout_logs_rollup_updated() from public;

drop trigger if exists workout_logs_rollup_insert on public.workout_logs;
create trigger workout_logs_rollup_insert
  after insert on public.workout_logs
  referencing new table as changed_rows
  for each statement execute function public.workout_logs_rollup_changed();

drop trigger if exists workout_logs_rollup_delete on public.workout_logs;
create trigger workout_logs_rollup_delete
  after delete on public.workout_logs
  referencing old table as changed_rows
  for each statement execute function public.workout_logs_rollup_changed();

drop trigger if exists workout_logs_rollup_update on public.workout_logs;
create trigger workout_logs_rollup_update
  after update on public.workout_logs
  referencing old table as old_rows new table as new_rows
  for each statement execute function public.workout_logs_rollup_updated();

-- Why there is no trigger on user_workouts here: deleting a session cascades to
-- its workout_logs, which fires the DELETE trigger above with those rows in the
-- transition table -- and because performed_on and user_id live ON the log rows,
-- the recompute still knows which day to fix even though the parent is already
-- gone. Moving a session to another day is handled the same way, through the
-- resync UPDATE in migration 0004. That is the payoff for denormalizing those
-- two columns.


-- -----------------------------------------------------------------------------
-- Maintenance: full rebuild.
-- -----------------------------------------------------------------------------
-- Run this after an admin edits an exercise's muscle-group mapping (existing
-- rollup rows were computed against the old mapping and will not fix
-- themselves), after a bulk import, or if you ever suspect drift.
-- Service role / SQL editor only:   select public.rebuild_all_muscle_group_intensity();
-- -----------------------------------------------------------------------------
create or replace function public.rebuild_all_muscle_group_intensity()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r     record;
  n_days integer := 0;
begin
  for r in
    select distinct l.user_id, l.performed_on
      from public.workout_logs l
     order by l.user_id, l.performed_on
  loop
    perform public.recompute_muscle_group_intensity(r.user_id, r.performed_on);
    n_days := n_days + 1;
  end loop;
  return n_days;
end;
$$;

revoke all on function public.rebuild_all_muscle_group_intensity() from public;


-- =============================================================================
-- RLS -- read-only to clients, by design
-- =============================================================================
alter table public.muscle_group_intensity enable row level security;

-- SELECT only. There is deliberately NO insert/update/delete privilege and NO
-- write policy: this table is derived data, and the only legitimate writer is
-- the SECURITY DEFINER recompute function above. A client that could write here
-- could paint its own muscle map, which would be a confusing bug, not an
-- attack -- but there is no reason to allow it.
revoke all on table public.muscle_group_intensity from anon, authenticated;
grant select on table public.muscle_group_intensity to authenticated;

drop policy if exists muscle_group_intensity_select_own on public.muscle_group_intensity;
create policy muscle_group_intensity_select_own on public.muscle_group_intensity
  for select to authenticated
  using (user_id = (select auth.uid()));
-- Again: no admin branch. Training history is private, full stop.


-- ==========================================================================
-- SOURCE: 20261011000006_seed_rec_center_equipment.sql
-- ==========================================================================

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


-- ==========================================================================
-- SOURCE: 20261011000007_seed_exercises.sql
-- ==========================================================================

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


-- ==========================================================================
-- SOURCE: 20261017000008_demo_equipment_and_exercises.sql
-- ==========================================================================

-- =============================================================================
-- LionFit  |  0008  |  DEMO DATA: placeholder equipment + exercises that use it
-- =============================================================================
-- Depends on: 0003 (tables), 0006 (real equipment seed), 0007 (real catalog).
--
--   >> EVERYTHING IN THIS FILE IS MADE UP, FOR THE DEMO. <<
--   >> It is NOT a record of what is on the Pennington floor.   <<
--
-- Why it exists: docs/rec-center-equipment.md is partial and leaves calves,
-- adductors, abs and glutes without dedicated equipment, and there is no
-- cardio or barbell/plate data at all. For a demo the catalog needs to look
-- like a real gym, so this file fills those gaps with plausible placeholders.
--
-- How to tell it apart from real data, everywhere:
--   * rec_center_equipment: is_verified = false AND notes start with 'DEMO'.
--   * exercises:            notes start with 'DEMO'. The app shows a "Demo"
--                           badge on these in the exercise picker
--                           (CatalogExercise.isDemoData).
--
-- How to remove it after the floor walk (in this order -- workout_logs
-- references exercises with ON DELETE RESTRICT, so logged demo exercises are
-- retired, not deleted):
--
--   update public.exercises set is_active = false where notes like 'DEMO%';
--   delete from public.exercises e where notes like 'DEMO%'
--     and not exists (select 1 from public.workout_logs l where l.exercise_id = e.id);
--   delete from public.rec_center_equipment where notes like 'DEMO%';
--
-- Then add the real rows as a new migration. Do not edit this file once it is
-- applied.
--
-- ON CONFLICT DO NOTHING, same as the real seeds, so re-running is harmless
-- and never stomps an admin's correction.
-- =============================================================================

insert into public.rec_center_equipment
  (equipment_type, label, quantity, availability_status, is_verified, is_inventory_item, load_increments_lb, notes)
values

-- ---- Barbells and plates (open questions 3 + 4) ------------------------------
('olympic_barbell', 'Olympic Barbell (45 lb)', 8, 'available', false, true, '{45}'::numeric(6,2)[],
 'DEMO placeholder. Bar weight assumed 45 lb -- matches the assumption already in lib/core/training/load_quantization.dart.'),
('weight_plates', 'Weight Plates', null, 'available', false, true, '{2.5,5,10,25,35,45}'::numeric(6,2)[],
 'DEMO placeholder. load_increments_lb holds PLATE denominations, not total loads.'),
('flat_bench', 'Flat Bench', 6, 'available', false, true, null,
 'DEMO placeholder. Possibly what the doc''s ambiguous "3 free weights" means -- unconfirmed.'),

-- ---- Machines for the groups the real list does not cover (open q. 5, 6, 8) --
('calf_raise_machine', 'Calf Raise Machine', 1, 'available', false, true, null,
 'DEMO placeholder. Covers calves, which have no machine in the real list.'),
('hip_adduction_machine', 'Hip Adduction / Abduction Machine', 1, 'available', false, true, null,
 'DEMO placeholder. Covers adductors, which have no machine in the real list.'),
('ab_crunch_machine', 'Ab Crunch Machine', 1, 'available', false, true, null,
 'DEMO placeholder. Covers abs, which have no station in the real list.'),
('hip_thrust_machine', 'Hip Thrust Machine', 1, 'available', false, true, null,
 'DEMO placeholder. Covers glutes, which are thin in the real list.'),
('leg_press', 'Leg Press', 2, 'available', false, true, null,
 'DEMO placeholder.'),
('smith_machine', 'Smith Machine', 1, 'available', false, true, null,
 'DEMO placeholder.'),
('pull_up_station', 'Pull-Up / Dip Station', 2, 'available', false, true, null,
 'DEMO placeholder. 0007 has no pull-ups because no bar was listed; this unblocks them for the demo.'),

-- ---- Cardio (open question 7) ------------------------------------------------
('treadmill', 'Treadmill', 10, 'available', false, true, null, 'DEMO placeholder.'),
('stationary_bike', 'Stationary Bike', 6, 'available', false, true, null, 'DEMO placeholder.'),
('rowing_machine', 'Rowing Machine', 4, 'available', false, true, null, 'DEMO placeholder.'),
('elliptical', 'Elliptical', 6, 'available', false, true, null, 'DEMO placeholder.')

on conflict (equipment_type) do nothing;


-- Column order as in 0007:
--   slug, name, primary, secondary, unmapped, required_equipment,
--   movement_pattern, is_outdoor, notes
-- Same rule as 0007: only the 16 renderable groups go in primary/secondary.
insert into public.exercises
  (slug, name,
   primary_muscle_groups, secondary_muscle_groups, unmapped_muscle_groups,
   required_equipment, movement_pattern, is_outdoor, notes)
values
('machine_calf_raise',      'Machine Calf Raise',      '{calves}',           '{}',                              '{}',                 '{calf_raise_machine}',          'isolation',       false, 'DEMO: uses placeholder equipment.'),
('machine_hip_adduction',   'Machine Hip Adduction',   '{adductors}',        '{}',                              '{}',                 '{hip_adduction_machine}',       'isolation',       false, 'DEMO: uses placeholder equipment.'),
('machine_ab_crunch',       'Machine Ab Crunch',       '{abs}',              '{}',                              '{}',                 '{ab_crunch_machine}',           'core',            false, 'DEMO: uses placeholder equipment.'),
('machine_hip_thrust',      'Machine Hip Thrust',      '{glutes}',           '{hamstrings}',                    '{}',                 '{hip_thrust_machine}',          'hinge',           false, 'DEMO: uses placeholder equipment.'),
('leg_press',               'Leg Press',               '{quads}',            '{glutes,hamstrings,adductors}',   '{}',                 '{leg_press}',                   'squat',           false, 'DEMO: uses placeholder equipment.'),
('smith_machine_squat',     'Smith Machine Squat',     '{quads}',            '{glutes,hamstrings}',             '{}',                 '{smith_machine}',               'squat',           false, 'DEMO: uses placeholder equipment.'),
('pull_up',                 'Pull-Up',                 '{lats}',             '{biceps,forearms,delts_rear}',    '{rhomboids}',        '{pull_up_station}',             'vertical_pull',   false, 'DEMO: uses placeholder equipment.'),
('chin_up',                 'Chin-Up',                 '{lats,biceps}',      '{forearms}',                      '{}',                 '{pull_up_station}',             'vertical_pull',   false, 'DEMO: uses placeholder equipment.'),
('parallel_bar_dip',        'Parallel Bar Dip',        '{triceps,chest_lower}','{delts_front}',                 '{}',                 '{pull_up_station}',             'vertical_push',   false, 'DEMO: uses placeholder equipment.'),
('hanging_leg_raise',       'Hanging Leg Raise',       '{abs}',              '{forearms}',                      '{obliques}',         '{pull_up_station}',             'core',            false, 'DEMO: uses placeholder equipment.'),
('barbell_overhead_press',  'Barbell Overhead Press',  '{delts_front}',      '{delts_side,triceps,traps_upper}','{}',                 '{olympic_barbell,weight_plates}','vertical_push',  false, 'DEMO: uses placeholder equipment.'),
('barbell_bent_over_row',   'Barbell Bent-Over Row',   '{lats}',             '{biceps,delts_rear,forearms}',    '{rhomboids,erector_spinae}','{olympic_barbell,weight_plates}','horizontal_pull',false,'DEMO: uses placeholder equipment.'),
('barbell_curl',            'Barbell Curl',            '{biceps}',           '{forearms}',                      '{}',                 '{olympic_barbell,weight_plates}','isolation',      false, 'DEMO: uses placeholder equipment.'),
('treadmill_run',           'Treadmill Run',           '{quads,calves}',     '{hamstrings,glutes}',             '{tibialis_anterior}','{treadmill}',                   'cardio',          false, 'DEMO: uses placeholder equipment. Log minutes as reps.'),
('stationary_bike_ride',    'Stationary Bike',         '{quads}',            '{hamstrings,glutes,calves}',      '{}',                 '{stationary_bike}',             'cardio',          false, 'DEMO: uses placeholder equipment. Log minutes as reps.'),
('rowing_machine_row',      'Rowing Machine',          '{lats,quads}',       '{biceps,delts_rear,hamstrings,glutes}','{rhomboids}',   '{rowing_machine}',              'cardio',          false, 'DEMO: uses placeholder equipment. Log minutes as reps.'),
('elliptical_session',      'Elliptical',              '{quads}',            '{glutes,hamstrings,calves}',      '{}',                 '{elliptical}',                  'cardio',          false, 'DEMO: uses placeholder equipment. Log minutes as reps.')

on conflict (slug) do nothing;
