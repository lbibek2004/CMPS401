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
