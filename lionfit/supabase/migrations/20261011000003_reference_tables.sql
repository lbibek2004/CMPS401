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
