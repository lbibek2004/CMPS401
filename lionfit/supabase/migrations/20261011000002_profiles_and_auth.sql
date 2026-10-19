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
