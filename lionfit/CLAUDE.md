# LionFit

AI-powered workout planner and tracker for Southeastern Louisiana University students.
Android + Web, built on Flutter with a Supabase backend.

The app plans a weekly training schedule around the equipment actually available at the
**Pennington Student Activity Center (Rec Center)**, mixes in outdoor activities, logs every
set, and uses the user's own history (volume, estimated 1RM, RPE/RIR) to pick the next load.

## Status

**The web app and the Android debug APK build.** 356 Dart tests (355 pass, 1 skipped) + 11 Edge Function grounding tests
pass, `dart analyze` is clean, `flutter build web` succeeds.

Built and verified:

| Area | State |
| --- | --- |
| App shell | Riverpod + go_router + Supabase client wired. Five tabs (Home, History, Log, Muscle map, Profile) in a `StatefulShellRoute` (`lib/core/router/app_shell.dart`): top bar on web, bottom bar + swipe on Android (swipe off on the map tab). Redirects: signed-in users never see the landing page; a signed-in user with the survey owed goes to `/welcome` |
| Onboarding survey | `/welcome`: goal, days, experience, effort scale + target, unit, optional current lifts + bodyweight (`lib/features/onboarding/`). Answers seed first loads via `coach/domain/starting_load.dart`; no history = a light calibration week. **Needs migration 0009** — without it the survey is skipped, not forced |
| Profile | `/profile`: read-only summary; one hamburger (Edit profile / Retake survey / Change theme / Change password / Admin tools (admins only) / Log out). Edit covers display name, W-Number, goal, days, experience, unit, effort, target effort, rest timer, bodyweight. **Password is its own flow** that re-checks the current password (`change_password_sheet.dart`); the plan's Change edits goal + days only (`lib/features/profile/`) |
| Admin tools | `/admin`, same login - shown and routed only for `profiles.role = 'admin'`; writes enforced by RLS `is_admin()`. Equipment: status / quantity / verified / notes, add. Exercises: retire/restore, edit muscles/equipment/pattern, add. No user data (`lib/features/admin/`) — **not yet run against the live DB** |
| Rest timer | Started by `TodaySessionController.logSet` after **every** saved set, from any screen (cardio excepted). Sets are logged one at a time everywhere ("Set 2 of 3"); there is no multi-set save; full screen over a blurred, 40%-dimmed app on Android (✕ shrinks it to a bar), a bar on web; +10 s, skip; 3 s vibration at the end (Android method channel in `MainActivity.kt`, `navigator.vibrate` on web). **Foreground only**; no background notification yet |
| Theme | Full light + dark token system, contrast-verified (`lib/core/theme/`) |
| Landing page | Minimal, no gradients (`lib/features/landing/`) |
| Auth | Login + sign-up with validation and unconfirmed-email handling (`lib/features/auth/`) |
| Home | This week's plan with Log / Replace per exercise (top-3 same-muscle swaps, stored in `user_plan_swaps`), logged/replaced marking, plan stable within the week; progress = average working set per session vs last week or personal best; next loads (`lib/features/home/presentation/`) — **not yet viewed in a browser** |
| Workout logging | `/log`: one exercise open at a time, recorded ones fold to a summary with Edit; per-set edit/delete; RPE/RIR slider; coach pre-fill (`lib/features/workout/`) — **not yet run against the live DB in a browser** |
| History | `/history`: last 1–7 days (slider) or calendar weeks back a month (dropdown), muscle filter (`lib/features/history/`) |
| Coach | `lib/features/coach/`: next load per lift, muscle gaps, weekly plan — pure Dart. Gemini phrasing via the `coach-insights` Edge Function (**written + tested, not deployed**). See `docs/ai-coach.md` |
| 3D muscle map | `/map`: red/yellow/green over a 1–30 day window; tap a muscle (model or list) for a sheet with what trained it (direct vs assisted) and loggable suggestions (`lib/features/muscle_map/`) — **3D tap not yet verified in a browser** |
| Training engine | e1RM, load quantization, progression, volume — pure Dart, 114 tests (`lib/core/training/`) |
| Database | 0001–0007 **applied**. 0008 (**real Pennington equipment list** + 50 exercises) and 0009 (survey/profile columns, `user_strength_baselines`, `user_plan_swaps`) written, **not yet applied** |
| 3D asset | `assets/muscleAnatomy.glb`, 64k triangles, bundled and served |
| Health (Android) | "Today's activity" card on Home: steps today, average heart rate today, latest resting heart rate, read from **Health Connect** (`health` package) - Fitbit / Google Health, Samsung Health and the phone write there. Read-only (`READ_STEPS`, `READ_HEART_RATE`, `READ_RESTING_HEART_RATE`), foreground only, **shown, not uploaded**. Privacy page at `/health-privacy`, opened by Health Connect's permission screen through `MainActivity.kt` (now a `FlutterFragmentActivity`); minSdk 26. Hidden on web (`lib/features/health/`) - **not yet run on a phone** |

Not built yet: health data on web (would need the Google Health API - see Health monitoring), a
background rest-timer notification, offline sync (the logger shows an error on a dropped
connection rather than queueing).

Open blockers and decisions owed by the team live in **`CHECKLIST.md`**. The Pennington
equipment inventory lives in **`docs/rec-center-equipment.md`**, transcribed from
`assets/Pennington Rec Center Equipment List.docx` — it is the source of truth for the
`rec_center_equipment` seed, and each row's load range is what suggestions round to.

**Do not tell the user a feature works until you have run it.**

## Tech stack

| Layer | Choice |
| --- | --- |
| Frontend / UI | Flutter (Android + Web from one codebase) |
| Backend | Supabase (Postgres, Auth, Storage, Edge Functions) |
| Database | Supabase Postgres, Row Level Security on every user-owned table |
| AI logic | Deterministic training math in Dart first; Gemini (Flash-Lite) only phrases it, via a Supabase Edge Function — see `docs/ai-coach.md` |

### Settled stack decisions

Chosen deliberately for a team that wants fewer moving parts. Do not swap these without a
reason written down here.

| Concern | Package | Why this one |
| --- | --- | --- |
| State management | `flutter_riverpod` (**no** code generation) | Its `AsyncValue` gives loading / error / data handling for free, and nearly every screen in this app loads from Supabase. The simpler-looking alternative (`provider` + `ChangeNotifier`) means hand-rolling that triad on every screen, which is more total work, not less. Skip `riverpod_generator` — the build_runner step is the part that actually costs beginners time. |
| Routing | `go_router` | Real URLs on web (`/login`, `/plan`, `/log/:id`). Browser back/forward and refresh behave correctly, which `Navigator` alone does not give you on web. |
| Charts | `fl_chart` | Line charts for per-exercise progress; themeable to our palette. |
| Backend client | `supabase_flutter` | Official; wraps auth, Postgrest, and session persistence on both Android and Web. |
| 3D renderer | `model_viewer_plus` | Google's `<model-viewer>`: a web component on Web, a WebView on Android — one widget for both. Colours are written into the GLB's 16 materials **in Dart** (`glb_recolor.dart`) and passed as a `data:` URL. The only JS is tap-to-select (`materialFromPoint`): a JavaScript channel on Android, a page-level script installed from Dart on web (the web build injects HTML via `innerHTML`, so `relatedJs` never runs there). Needs the script tag in `web/index.html` and `usesCleartextTraffic` in the Android manifest. |

Rule of thumb for this project: prefer the boring, well-documented package, and do not add a
dependency until a screen actually needs it.

## Color theme

Both themes ship together. Nothing hardcodes a hex outside the theme definition.

**Dark**
- Base / background: `#000000`
- Primary: `#1A5634`
- Secondary: `#F8CB28`

**Light**
- Base / background: `#FFFFFF`
- Primary: `#0B4022`
- Secondary: `#BF9C1F`

Primary carries brand and main actions. Secondary is the accent — highlights, intensity peaks,
PRs, call-to-action emphasis. Every screen must be checked in both themes.

## Assets

### `assets/muscleAnatomy.glb` — the 3D anatomy model

Registered in `pubspec.yaml` through `assets/`. Re-verify after any Blender re-export:

```bash
node tool/inspect_glb.js assets/muscleAnatomy.glb
```

Measured, not estimated:

| | |
| --- | --- |
| File size | **1.08 MiB** (1,130,632 bytes) |
| Rendered triangles | **64,130** |
| Colorable muscle groups | **16** |
| Nodes | 30 muscle (left/right pairs) + 6 neutral; 36 meshes, no instancing |
| Textures / skins | none — flat `baseColorFactor` materials |
| Mirrored nodes | 18 with negative scale; every material is `doubleSided`, so they render correctly |

This is the decimated model and it is **web-ready**: 1 MiB and 64k triangles load fine on a
phone browser. The earlier 12.8 MiB / 897k-triangle version is gone. No optimization pass is
required before shipping the muscle map.

### The 16 muscle group keys

**The material name is the canonical key.** These exact strings are schema values — the
`muscle_group` enum, `exercises.primary_muscle_groups`, and
`muscle_group_intensity.muscle_group` all use them verbatim:

```
abs          adductors    biceps       calves
chest_lower  chest_upper  delts_front  delts_rear
delts_side   forearms     glutes       hamstrings
lats         quads        traps_upper  triceps
```

### Recolor by material, not by mesh

Left and right sides share a material and always carry the same intensity, so a full repaint is
**16 `baseColorFactor` writes**, not 30 mesh updates, and there are no textures to swap. This is
the main reason the model is pleasant to work with.

### Known issues in the asset

- **`tricep_r` is singular.** Every other right-side node is `<group>_r`, and `triceps_l` is
  spelled correctly. A naive `${group}_r` lookup breaks on triceps. `tool/inspect_glb.js` flags
  this automatically; until it is fixed in Blender, special-case it in one place.
- **Mesh names are misleading leftovers** from the source anatomy model. `traps_upper` lives on
  a mesh named "Subcutaneous acromial bursa"; the head neutral is "Sternocleidomastoid muscle".
  **Ignore mesh names entirely — node and material names are authoritative.**
- **A stray animation is embedded.** `cvel_lAction`, 52 bytes, one frame, keyed on `calves_l`
  translation/rotation/scale. Harmless in size, but **do not enable autoplay** on the renderer
  or the left calf may snap to that keyframe. Strip it on the next export.
- **36% of the triangles (23,104) are `body_neutral`** filler that can never be colored. Fine at
  this size; only worth revisiting if the budget gets tight again.
- **`TEXCOORD_0` is present but unused** (zero textures). 0.02 MiB — not worth a pass.

### Muscle groups the model does not have

No geometry exists for these, and they matter for a lifting app:

| Missing | Exercises with nowhere to map |
| --- | --- |
| Erector spinae / lower back | deadlift, good morning, back extension |
| Obliques | side bend, Russian twist, woodchop |
| Rhomboids / mid-traps | every rowing variation |
| Tibialis anterior | shin work |

Until that geometry exists, `exercises` rows targeting them need a documented fallback
(`lats` for rows, `abs` for obliques) or an explicit "not shown on map" flag. Do not silently
drop the volume — a deadlift that lights up nothing reads as a bug to the user.

## Feature scope

### Planning
- Generate a schedule of **3–7 days/week** (user picks; 3 is the floor)
- Goal-driven: weight loss, muscle gain, or general fitness
- Subtle week-over-week variation so adaptation doesn't stall
- User can customize/override any generated variation
- Mix of Rec Center equipment work and outdoor activities

### Logging
- Weight (lbs **and** kgs — user-selectable unit), reps, sets
- RPE (Rate of Perceived Exertion) **or** RIR (Reps in Reserve), user's choice
- Set types: warm-up, working, drop-set, superset
- Customizable rest timer between sets, with notification support (must fire with the app
  backgrounded on Android)

### Progress
- Per-exercise progress line graph
- **3D muscle map**: which muscle groups were trained and at what intensity, over a rolling
  window of 1–30 days (user picks the window; default to the longest window with data)

### Rec Center integration
- Equipment availability filter
- Alternative-exercise swap logic when a machine is occupied or out of service

### Health monitoring
- Heart rate and steps from the user's wearable. **Android: Health Connect** (built). The Fitbit /
  Google Health app writes steps, heart rate and resting heart rate there, so no Fitbit API is
  needed on the phone.
- **The Fitbit Web API is gone** - Google ended support on 2026-09-30 and switched it off on
  2026-10-30. Its successor, the Google Health API (Google OAuth), is the only route for web;
  most of its scopes are restricted (100-user cap until Google verification + a yearly CASA
  security assessment). Not started.
- Graceful fallback: manual entry or basic platform step/HR data when no wearable API is
  available. The app must be fully usable with zero wearable connected.

### AI
- Read the user's history and suggest the next load. Example: benched 135 lb × 10 and reported
  the first and last reps felt about the same → suggest 145 lb next session. Failed to finish
  8 reps at 135 lb → back the load off.
- Propose a fresh plan for the same muscle group every 1–2 weeks to avoid staleness
- Recommendation inputs: historical volume, estimated 1RM, RPE/RIR trend
- Outputs: dynamic load adjustment, progressive overload targets, equipment-constrained
  exercise substitutions

## Database schema

Required tables (names are fixed — other code and docs refer to them):

- `exercises` — the exercise catalog: name, primary/secondary muscle groups, required
  equipment, movement pattern, indoor/outdoor
- `user_workouts` — a planned or completed session for a user: date, goal, week index,
  plan variation
- `workout_logs` — per-set rows: exercise, set index, set type, weight, unit, reps, RPE/RIR
- `muscle_group_intensity` — rolled-up intensity per muscle group per user per day, feeding
  the 3D map
- `rec_center_equipment` — Pennington equipment inventory, quantity, availability status

Supporting tables are fine to add (`profiles`, `user_health_metrics`, `user_preferences`, …)
but the five above keep their names.

Rules:
- **`muscle_group` is an enum of exactly the 16 keys listed under Assets.** The 3D model's
  material names and the database enum must stay in lockstep; if one changes, the map breaks
  silently. Validate with `node tool/inspect_glb.js`.
- RLS on every table holding user data; a user reads and writes only their own rows
- `exercises` and `rec_center_equipment` are shared reference data — read-only to clients
- Every schema change lands as a migration file in `supabase/migrations/`, never as an
  untracked edit in the Supabase dashboard

## Auth model

Settled — do not relitigate:

- **Email + password, not username login.** Supabase Auth is email-based; a
  `username -> email` lookup layer is work we do not need. Users sign in with their email, and
  `profiles.display_name` carries what they are called in the UI.
- **Two roles:** `member` (default) and `admin`. The seeded `Pao` account is an **admin**.

### What admin means here

Admin is a content-management role, not god mode. Admins write the shared reference tables that
members may only read:

| | member | admin |
| --- | --- | --- |
| `exercises` | read | read + write |
| `rec_center_equipment` | read | read + write |
| own workout / health rows | read + write | read + write |
| **other users'** workout / health rows | none | **none** |

**An admin must not be able to read another user's workout or health data.** That is a privacy
boundary and RLS has to enforce it — not the app hiding a button.

Implementation rules:

- Role lives in `profiles.role`. **Never** in `auth.users.raw_user_meta_data`, which is
  client-writable — a user could promote themselves.
- `profiles.role` must not be member-writable. The `UPDATE` policy on `profiles` has to exclude
  it, or role changes go through an admin-only path.
- RLS policies test the role through a `SECURITY DEFINER` helper such as `public.is_admin()`,
  so policy checks do not recurse through `profiles`' own RLS.
- Verify by logging in as a second non-admin user and attempting to read Pao's `workout_logs`.
  A policy that was never tested against a real second user is not evidence of anything.

## Commands

```bash
flutter pub get

# Web. The --dart-define-from-file flag is required — without it the Supabase
# config is empty and the app cannot reach the backend.
flutter run -d chrome --dart-define-from-file=.env

# Android (device or emulator attached)
flutter run --dart-define-from-file=.env

# Deploy web to Vercel (builds, then ships build/web — never deploy web/ itself)
bash tool/deploy_web.sh          # preview
bash tool/deploy_web.sh --prod   # production

flutter test
node --test supabase/functions/coach-insights/grounding.test.ts
dart analyze
dart format .

# Inspect the 3D model (triangle counts, muscle group keys, naming contract)
node tool/inspect_glb.js assets/muscleAnatomy.glb
```

Copy `.env.example` to `.env` and fill in real values before the first run.

## Conventions

- Feature-first layout under `lib/features/<feature>/` with `data/`, `domain/`, `presentation/`;
  cross-cutting code in `lib/core/`
- No secrets in the repo. Supabase URL/anon key come from `--dart-define` or a gitignored
  `.env`; the service-role key never reaches the client.
- Store weights in a single canonical unit in the DB and convert at the UI boundary — do not
  store mixed units.
- Both Android and Web must work. If a package is Android-only, guard it and provide a web
  fallback rather than breaking the web build.
- The gym has bad signal: logging must survive a dropped connection and sync later.
- Training math (e1RM, volume, load progression) belongs in pure, unit-tested Dart functions —
  not buried in widgets and not left to an LLM call.

## Agents

Three leads, each with focused subagents. Delegate to the lead when the task spans a domain;
delegate to a subagent when the task is already scoped.

| Agent | Owns |
| --- | --- |
| `MobileAppDev` | Flutter app implementation — screens, state, data layer, platform integration, builds |
| `UI_UXDev` | Design system, theming, screen design, flows, accessibility |
| `SeniorDev` | Architecture, Supabase data model, AI training logic, code review, quality gate |

Subagents:

- Under `MobileAppDev`: `flutter-feature-builder`, `health-data-integrator`, `muscle-map-3d`,
  `offline-sync-engineer`
- Under `UI_UXDev`: `design-system-curator`, `ux-flow-architect`, `accessibility-auditor`
- Under `SeniorDev`: `supabase-architect`, `ai-coach-engineer`, `code-reviewer`, `test-engineer`

Definitions live in `.claude/agents/`.
