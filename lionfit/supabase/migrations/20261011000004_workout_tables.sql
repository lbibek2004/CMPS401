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
