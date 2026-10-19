# LionFit — Supabase schema

Everything the database needs lives in `supabase/migrations/` as ordered SQL files. There are
no dashboard-only changes: if it is not in a migration, it does not exist for the rest of the
team.

> **Not yet applied.** These files have been written and statically checked (enum values,
> seed row arity, equipment slugs, muscle-group coverage) but **have not been executed against
> any database**. Nothing here is "working" until someone runs it and the verification section
> at the bottom passes.

---

## What is in here

Apply in filename order. Each file depends on the ones before it.

| File | What it creates |
| --- | --- |
| `20261011000001_enums_and_helpers.sql` | All 11 enums (`muscle_group`, `unmapped_muscle_group`, `user_role`, `set_type`, `training_goal`, `weight_unit`, `effort_preference`, `equipment_availability`, `health_data_source`, `movement_pattern`) + `set_updated_at()` |
| `20261011000002_profiles_and_auth.sql` | `profiles`, `is_admin()`, `current_profile_role()`, profile RLS, the `auth.users` signup trigger, backfill for existing accounts |
| `20261011000003_reference_tables.sql` | `exercises`, `rec_center_equipment`, member-read / admin-write RLS |
| `20261011000004_workout_tables.sql` | `user_workouts`, `workout_logs` (one row per set), `user_health_metrics`, owner-only RLS, indexes |
| `20261011000005_muscle_group_intensity.sql` | The muscle-map rollup table, its recompute function, the statement-level triggers that maintain it, and `rebuild_all_muscle_group_intensity()` |
| `20261011000006_seed_rec_center_equipment.sql` | 13 Pennington inventory rows + 2 sentinels, from `docs/rec-center-equipment.md` |
| `20261011000007_seed_exercises.sql` | 59-exercise starter catalog mapped to the 16 muscle groups and the real equipment list |
| `20261017000008_demo_equipment_and_exercises.sql` | **DEMO placeholders**: 14 made-up equipment rows + 17 exercises using them. All marked `DEMO` in `notes`; removal SQL in the file header |

Every file is safe to run twice: types are created inside `DO` blocks that swallow
"already exists", tables use `create table if not exists`, policies are dropped before being
created, and both seeds use `on conflict … do nothing`.

---

## Applying them

### Option A — Supabase CLI (preferred)

The CLI is **not installed on the dev machine yet**. On Windows:

```powershell
scoop install supabase          # or: choco install supabase
supabase --version
```

Then, from the repo root:

```bash
supabase init          # creates supabase/config.toml next to migrations/ (safe: it does
                       # not touch the migrations that are already there)
supabase login         # opens a browser, stores a personal access token
supabase link --project-ref wtrhgkquswrqqjdndate
supabase db push       # applies every migration not yet recorded in the remote history
```

`db push` records what it applied in `supabase_migrations.schema_migrations`, so it is safe to
re-run — it only pushes files the remote has not seen.

To check what would run without running it:

```bash
supabase migration list
```

### Option B — dashboard SQL editor (no CLI needed)

Dashboard → **SQL Editor** → New query. Open each migration file, paste the **whole** file,
Run, confirm it succeeded, then move to the next. **In filename order**, one file per query:

```
20261011000001_enums_and_helpers.sql
20261011000002_profiles_and_auth.sql
20261011000003_reference_tables.sql
20261011000004_workout_tables.sql
20261011000005_muscle_group_intensity.sql
20261011000006_seed_rec_center_equipment.sql
20261011000007_seed_exercises.sql
```

Notes for this route:

- The SQL editor connects as `postgres`, which owns `auth.users` — so the signup trigger in
  `0002` will create fine. If you ever see `must be owner of relation users`, you are running
  as the wrong role.
- The editor runs as the table owner, which means **RLS does not apply to you there**. Queries
  that look fine in the SQL editor prove nothing about what a logged-in member can see. Use the
  impersonation recipe at the bottom.
- If you apply by hand this way, the CLI's migration history will not know about it. Pick one
  route and stay on it; mixing the two is how a team ends up with "it works on my project".

---

## Creating Pao, the admin

Do not write a password or an auth user in SQL. The account is created by signing up through
the app like any other user, and is then promoted with one UPDATE.

### 1. Turn email confirmation OFF first

Dashboard → **Authentication → Sign In / Providers → Email** → toggle **Confirm email** OFF →
Save.

This is still on as of the last check (`mailer_autoconfirm: false`), and until it is off a
signup with a dummy address can never log in — the account exists but is unconfirmed. This is
the known blocker in `CHECKLIST.md`.

### 2. Sign up through the app

Run the app, use the signup screen, and register with the address in `.env`
(`SEED_USER_EMAIL`, currently `pao@selu.edu`) and `SEED_USER_DISPLAY_NAME` as the display name.

The `on_auth_user_created` trigger creates the matching `public.profiles` row automatically,
with `display_name` taken from the signup metadata and `role` left at its default `member`.

### 3. Promote that profile to admin

Dashboard → SQL Editor (it runs as `postgres`, which is what makes this work — no client,
service-role key, or app code can do it):

```sql
update public.profiles p
   set role = 'admin'
  from auth.users u
 where u.id = p.id
   and lower(u.email) = lower('pao@selu.edu');   -- SEED_USER_EMAIL from .env

-- verify
select p.id, p.display_name, p.role, u.email
  from public.profiles p join auth.users u on u.id = p.id
 where p.role = 'admin';
```

### Why it has to be done this way

- `profiles.role` is the **only** place the role lives. It is deliberately not read from
  `auth.users.raw_user_meta_data`, which the client can write — a user could otherwise sign up
  with `{"role":"admin"}` and own the shared catalog.
- The `authenticated` database role has **no UPDATE privilege on the `role` column at all**
  (migration `0002` revokes table-level UPDATE and re-grants only the preference columns), and
  the `profiles_update_own` policy independently re-checks that the submitted role equals the
  stored one. So there is no in-app path to promotion, by design.
- Admin means: may write `exercises` and `rec_center_equipment`. **It does not grant any access
  to another user's workouts, sets, or health data.** No policy in this schema has an admin
  branch on a user-owned table.

---

## Verifying it actually works

The SQL editor bypasses RLS, so you have to explicitly become a logged-in user. Pick two real
user UUIDs from `auth.users` first.

```sql
-- Impersonate user B and confirm they see only their own rows.
begin;
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', '<USER_B_UUID>', 'role', 'authenticated')::text,
    true);
  set local role authenticated;

  select count(*) from public.workout_logs;            -- only B's sets
  select count(*) from public.user_workouts;           -- only B's sessions
  select count(*) from public.muscle_group_intensity;  -- only B's rollup
  select count(*) from public.profiles;                -- exactly 1 (B)
  select count(*) from public.exercises;               -- 59 — shared reference data
rollback;
```

The checks that matter:

1. **Member cannot read another member's data.** With B impersonated, `select * from
   public.workout_logs where user_id = '<USER_A_UUID>'` must return **0 rows** — not an error,
   zero rows. That is RLS filtering, which is what it should look like.
2. **Admin cannot read another member's data either.** Repeat the block with Pao's UUID. The
   workout/health/rollup counts must still only cover Pao's own rows. This is the privacy
   boundary from `CLAUDE.md`; if an admin can see someone else's sets, the schema is wrong.
3. **Member cannot write the catalog.** As a non-admin:
   `insert into public.exercises (slug, name, primary_muscle_groups, movement_pattern)
   values ('hack','Hack','{quads}','squat');` must fail with
   `new row violates row-level security policy`.
4. **Admin can write the catalog.** The same insert as Pao must succeed.
5. **Member cannot promote themselves.** As a non-admin:
   `update public.profiles set role = 'admin' where id = auth.uid();` must fail — with
   `permission denied for column role` (the privilege lock fires before the policy does).
6. **The rollup fills in.** Insert a workout and a few sets, then
   `select * from public.muscle_group_intensity where user_id = '<USER>' order by day desc;`
   should have one row per trained muscle group with `normalized_intensity` between 0 and 1.
   Insert several sets in one statement to exercise the statement-level trigger path.
7. **The enum still matches the 3D asset:**
   ```bash
   node tool/inspect_glb.js assets/muscleAnatomy.glb
   ```
   The 16 material names it prints must equal `select unnest(enum_range(null::public.muscle_group));`
   exactly. If they ever differ, the muscle map stops colouring and nothing errors.

---

## Things to know before you change this

- **`public.muscle_group` is a contract with `assets/muscleAnatomy.glb`.** 16 values, verbatim
  material names. Drift breaks the muscle map **silently**. Four groups the model has no
  geometry for (erector spinae, obliques, rhomboids, tibialis) live in a separate
  `unmapped_muscle_group` enum — the reasoning is written out at the top of migration `0001`.
- **`muscle_group_intensity` is derived data**, maintained by triggers on `workout_logs`.
  Clients have `select` and nothing else. After an admin edits an exercise's muscle mapping,
  run `select public.rebuild_all_muscle_group_intensity();` or old rollup rows keep the old
  mapping. The full decision (vs. materialized view, vs. computing on read) is at the top of
  migration `0005`.
- **Weight is stored twice on purpose.** `weight` + `unit` are what the user typed;
  `weight_lb` and `volume_lb` are generated columns in canonical pounds. Do the math on the
  generated columns, convert for display only.
- **`workout_logs.user_id` and `performed_on` are denormalized from the parent session** and
  overwritten by a trigger. Do not send them from the client; they will be ignored.
- **Adding a column to `profiles`?** Add it to the two column-level `GRANT`s in migration
  `0002` as well, or the app gets `permission denied for column`. Never add `role` to them.
- **Never ship the service-role key to the client.** The Flutter app uses the anon key and
  lives under RLS. Anything needing elevated access (Fitbit token exchange, scheduled
  rollups, bulk equipment imports) belongs in an Edge Function.
- New migration = new file with a later timestamp. Never edit a file that has been applied.

---

## Known gaps, carried from `docs/rec-center-equipment.md`

The equipment seed contains only what that doc states explicitly. Deliberately **not** seeded,
because inventing inventory would put exercises in someone's plan that they cannot perform:

- **"3 free weights"** and **"1 machine"** — the doc marks both AMBIGUOUS. No rows created.
- **Barbells and plate denominations** — not recorded anywhere. The catalog *assumes* the squat
  racks and bench stations come with a loadable bar, and that assumption is written into the
  `notes` of every barbell row. Until plate denominations exist, barbell load suggestions
  cannot be rounded to real plates; only dumbbells can (their denominations are on the
  `dumbbell_pair` row as `load_increments_lb`).
- **Cardio equipment** — none catalogued, so every cardio row in the seed is outdoor.
- **Calf raise / adductor / ab / hip thrust stations, leg press, Smith machine, pull-up bar** —
  not listed, so not seeded. Calves, adductors and abs are covered with dumbbell, bodyweight,
  cable and outdoor work instead; glutes lean on a bench-and-bar hip thrust. There are no
  pull-ups in the catalog at all because there is no bar in the inventory.
- **Count discrepancy:** the doc says "Total catalogued stations: 26", but its own per-row
  counts add to 24 machines (28 with the 4 squat racks). The per-row counts were seeded; the
  total was not. Worth settling on the floor walk.

Every seeded row has `is_verified = false`. Flip rows to `true` as they are confirmed on the
floor, and keep `docs/rec-center-equipment.md` and migration `0006` in sync — if they drift,
the doc wins and the seed gets regenerated.
