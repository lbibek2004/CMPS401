-- =============================================================================
-- LionFit  |  0009  |  Onboarding survey, profile settings, plan swaps
-- =============================================================================
-- Depends on: 0001 (enums), 0002 (profiles), 0003 (exercises).
-- Does NOT depend on 0008: it can be applied before or after it.
--
-- What the app needs this for:
--
--   1. The onboarding survey (lib/features/onboarding/). New columns on
--      profiles for experience level, target effort, bodyweight, and the
--      moment the survey was finished. A NULL onboarding_completed_at is what
--      sends a signed-in user to /welcome.
--   2. The profile page (lib/features/profile/). W-number, rest-timer length,
--      and theme preference.
--   3. user_strength_baselines -- "what can you lift now?" answers from the
--      survey. The coach estimates first-session loads from these instead of
--      starting everyone at the lightest pin.
--   4. user_plan_swaps -- "replace this exercise" on the weekly plan. The plan
--      itself is still computed, not stored; only the swaps are stored.
--
-- The app tolerates this migration being absent: it reads profiles with
-- select(*) and treats missing columns as "survey not available", so nobody is
-- trapped on a survey that cannot be saved. Apply it to turn the features on.
--
-- Safe to re-run.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- training_experience -- how long the user has been lifting.
-- -----------------------------------------------------------------------------
do $$
begin
  create type public.training_experience as enum (
    'new',           -- never trained, or not in over a year
    'beginner',      -- under 6 months
    'intermediate',  -- 6 months to 2 years
    'advanced'       -- 2+ years of consistent training
  );
exception
  when duplicate_object then null;
end
$$;


-- -----------------------------------------------------------------------------
-- profiles: new columns.
-- -----------------------------------------------------------------------------
alter table public.profiles
  -- Southeastern student ID: "W" followed by 7 digits. Optional.
  add column if not exists w_number text
    constraint profiles_w_number_format
    check (w_number is null or w_number ~ '^W[0-9]{7}$'),

  -- NULL until the survey is answered.
  add column if not exists experience public.training_experience,

  -- How hard working sets should be. RPE 8 = 2 reps in reserve. The RIR view
  -- of the same number is 10 - target_rpe; one column, two presentations.
  add column if not exists target_rpe numeric(3,1) not null default 8
    constraint profiles_target_rpe_range
    check (target_rpe between 6 and 10),

  -- Canonical pounds, like every other weight in this schema
  -- (CLAUDE.md -> Conventions). Optional; only used to estimate starting loads.
  add column if not exists bodyweight_lb numeric(5,1)
    constraint profiles_bodyweight_lb_range
    check (bodyweight_lb is null or bodyweight_lb between 50 and 700),

  -- Rest between sets, in seconds. The timer adds 10 s at a time on top.
  add column if not exists rest_timer_seconds smallint not null default 90
    constraint profiles_rest_timer_seconds_range
    check (rest_timer_seconds between 15 and 600),

  add column if not exists theme_preference text not null default 'system'
    constraint profiles_theme_preference_values
    check (theme_preference in ('system', 'light', 'dark')),

  -- NULL = the survey is still owed. The app redirects to /welcome until set.
  add column if not exists onboarding_completed_at timestamptz;

comment on column public.profiles.w_number is
  'Southeastern student ID (W + 7 digits). Optional, user-editable.';
comment on column public.profiles.target_rpe is
  'Target effort for working sets on the RPE scale. RIR = 10 - target_rpe.';
comment on column public.profiles.onboarding_completed_at is
  'When the onboarding survey was finished. NULL sends the user to /welcome.';

-- Migration 0002 revoked table-wide writes on profiles and re-granted them
-- column by column, so a new column is NOT writable until it is granted here.
-- Column grants add to the existing ones; role stays ungranted.
grant insert (w_number, experience, target_rpe, bodyweight_lb,
              rest_timer_seconds, theme_preference, onboarding_completed_at)
  on table public.profiles to authenticated;
grant update (w_number, experience, target_rpe, bodyweight_lb,
              rest_timer_seconds, theme_preference, onboarding_completed_at)
  on table public.profiles to authenticated;


-- -----------------------------------------------------------------------------
-- user_strength_baselines -- one self-reported working set per exercise.
-- -----------------------------------------------------------------------------
-- Kept out of workout_logs on purpose: a survey answer is not a logged
-- session, and putting it there would light up the muscle map and the history
-- screen with a workout that never happened.
-- -----------------------------------------------------------------------------
create table if not exists public.user_strength_baselines (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  exercise_id  uuid not null references public.exercises (id) on delete cascade,
  -- As entered, with its unit -- the same convention as workout_logs.
  weight       numeric(7,2) not null
                 constraint user_strength_baselines_weight_range
                 check (weight > 0 and weight <= 2000),
  unit         public.weight_unit not null default 'lb',
  reps         smallint not null
                 constraint user_strength_baselines_reps_range
                 check (reps between 1 and 50),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint user_strength_baselines_user_exercise_key unique (user_id, exercise_id)
);

comment on table public.user_strength_baselines is
  'Survey answers: a working set the user can do today. Seeds first-session loads. Private to the user.';

drop trigger if exists user_strength_baselines_set_updated_at
  on public.user_strength_baselines;
create trigger user_strength_baselines_set_updated_at
  before update on public.user_strength_baselines
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- user_plan_swaps -- "replace this exercise" on a plan day.
-- -----------------------------------------------------------------------------
create table if not exists public.user_plan_swaps (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null default auth.uid()
                            references auth.users (id) on delete cascade,
  plan_date               date not null,
  original_exercise_id    uuid not null
                            references public.exercises (id) on delete cascade,
  replacement_exercise_id uuid not null
                            references public.exercises (id) on delete cascade,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint user_plan_swaps_distinct
    check (original_exercise_id <> replacement_exercise_id),
  -- Swapping the same slot twice replaces the first swap (upsert target).
  constraint user_plan_swaps_user_day_original_key
    unique (user_id, plan_date, original_exercise_id)
);

comment on table public.user_plan_swaps is
  'Exercise replacements on the computed weekly plan, per day. Private to the user.';

drop trigger if exists user_plan_swaps_set_updated_at on public.user_plan_swaps;
create trigger user_plan_swaps_set_updated_at
  before update on public.user_plan_swaps
  for each row execute function public.set_updated_at();

create index if not exists idx_user_plan_swaps_user_date
  on public.user_plan_swaps (user_id, plan_date);


-- -----------------------------------------------------------------------------
-- RLS: owner only. Same rule as workout data -- no is_admin() branch.
-- -----------------------------------------------------------------------------
alter table public.user_strength_baselines enable row level security;
alter table public.user_plan_swaps         enable row level security;

revoke all on table public.user_strength_baselines from anon, authenticated;
grant select, insert, update, delete on table public.user_strength_baselines
  to authenticated;

revoke all on table public.user_plan_swaps from anon, authenticated;
grant select, insert, update, delete on table public.user_plan_swaps
  to authenticated;

drop policy if exists user_strength_baselines_select_own on public.user_strength_baselines;
create policy user_strength_baselines_select_own on public.user_strength_baselines
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_strength_baselines_insert_own on public.user_strength_baselines;
create policy user_strength_baselines_insert_own on public.user_strength_baselines
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists user_strength_baselines_update_own on public.user_strength_baselines;
create policy user_strength_baselines_update_own on public.user_strength_baselines
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists user_strength_baselines_delete_own on public.user_strength_baselines;
create policy user_strength_baselines_delete_own on public.user_strength_baselines
  for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_plan_swaps_select_own on public.user_plan_swaps;
create policy user_plan_swaps_select_own on public.user_plan_swaps
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_plan_swaps_insert_own on public.user_plan_swaps;
create policy user_plan_swaps_insert_own on public.user_plan_swaps
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists user_plan_swaps_update_own on public.user_plan_swaps;
create policy user_plan_swaps_update_own on public.user_plan_swaps
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists user_plan_swaps_delete_own on public.user_plan_swaps;
create policy user_plan_swaps_delete_own on public.user_plan_swaps
  for delete to authenticated
  using (user_id = (select auth.uid()));


-- =============================================================================
-- Checks to run after applying:
--
--   -- the seven new profile columns exist (expect 7 rows)
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name = 'profiles'
--      and column_name in ('w_number','experience','target_rpe','bodyweight_lb',
--                          'rest_timer_seconds','theme_preference',
--                          'onboarding_completed_at');
--
--   -- RLS is on for both new tables (expect 2 rows, both true)
--   select relname, relrowsecurity from pg_class
--    where relname in ('user_strength_baselines','user_plan_swaps');
--
--   -- privacy: signed in as a second, non-admin user, this returns zero rows
--   -- even when Pao has baselines and swaps.
--   select * from public.user_strength_baselines;
--   select * from public.user_plan_swaps;
-- =============================================================================
