-- =============================================================================
-- LionFit  |  ONE-OFF SCRIPT  |  Delete every user and all of their data
-- =============================================================================
-- NOT A MIGRATION, on purpose. Files in supabase/migrations/ are replayed by
-- `supabase db push` on every fresh database; a wipe there would run again.
-- Run this by hand: Dashboard -> SQL Editor -> paste -> Run.
--
-- THIS CANNOT BE UNDONE. Every account, including the seeded Pao admin, is
-- deleted, along with:
--   user_plan_swaps, user_strength_baselines   (migration 0009, if applied)
--   workout_logs, user_workouts, user_health_metrics
--   muscle_group_intensity, profiles
--   auth.users and, by Supabase's own cascades, auth.identities, sessions,
--   refresh tokens and MFA factors
--
-- KEPT: the shared reference data (exercises, rec_center_equipment), the
-- schema, the policies, and the enums. The app works the moment this
-- finishes; it simply has no accounts.
--
-- Safety catch: the script refuses to run until you edit the line marked
-- >>> below so `confirm` says exactly: DELETE ALL USERS
-- =============================================================================

begin;

do $$
declare
  confirm constant text := 'no';   -- >>> change 'no' to 'DELETE ALL USERS'
  t text;
  remaining bigint;
begin
  if confirm is distinct from 'DELETE ALL USERS' then
    raise exception 'Not confirmed. Edit the confirm line to ''DELETE ALL USERS'' to run this.';
  end if;

  -- Children first, so the muscle-map rollup triggers on workout_logs run
  -- while each owner still exists. Tables from migrations that are not
  -- applied yet are skipped rather than failing the script.
  foreach t in array array[
    'public.user_plan_swaps',
    'public.user_strength_baselines',
    'public.workout_logs',
    'public.user_workouts',
    'public.user_health_metrics',
    'public.muscle_group_intensity',
    'public.profiles'
  ]
  loop
    if to_regclass(t) is not null then
      execute format('delete from %s', t);
      raise notice 'cleared %', t;
    else
      raise notice 'skipped % (does not exist)', t;
    end if;
  end loop;

  -- The accounts themselves. Cascades to auth.identities, auth.sessions,
  -- auth.refresh_tokens and auth.mfa_factors.
  delete from auth.users;

  -- Prove it: nothing user-owned may be left.
  select count(*) into remaining from auth.users;
  if remaining > 0 then
    raise exception 'auth.users still has % rows - rolled back', remaining;
  end if;
  foreach t in array array[
    'public.profiles',
    'public.user_workouts',
    'public.workout_logs',
    'public.user_health_metrics',
    'public.muscle_group_intensity',
    'public.user_strength_baselines',
    'public.user_plan_swaps'
  ]
  loop
    if to_regclass(t) is not null then
      execute format('select count(*) from %s', t) into remaining;
      if remaining > 0 then
        raise exception '% still has % rows - rolled back', t, remaining;
      end if;
    end if;
  end loop;

  raise notice 'All users and user data deleted. Reference data kept.';
end
$$;

commit;

-- =============================================================================
-- Afterwards, to get the Pao admin back:
--   1. Sign up as Pao in the app (the signup trigger creates the profile).
--   2. In the SQL Editor:
--        update public.profiles set role = 'admin'
--         where id = (select id from auth.users where email = '<pao''s email>');
--   Role is never client-writable, so step 2 has to happen here.
-- =============================================================================
