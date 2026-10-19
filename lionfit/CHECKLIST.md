# LionFit — Next Session Checklist

Updated 2026-10-11. Most of this list is now **done**. What's left is one dashboard click, one
floor walk, and two small art decisions.

Goals: **(a)** app usable on web, **(b)** landing + login/signup with a seeded `Pao` admin,
**(c)** start the recommendation engine.

---

## 🔴 The one thing that still blocks (b)

- [ ] **Turn off email confirmation.** Dashboard → **Authentication → Sign In / Providers →
      Email** → toggle **Confirm email** OFF, then Save.

I checked your project's live auth settings and it currently reports
`mailer_autoconfirm: false` — confirmation is **still on**. You asked for the easier version
since you'll be using dummy emails, and this is the toggle that delivers it.

I can't flip it for you: it needs the dashboard or a management API personal access token, and
the anon key has no authority over project settings.

**Until this is off, the login page will work and `Pao` still won't be able to sign in.**
That's the most likely way next session stalls, and it's a 15-second fix.

---

## 🟡 Waiting on you, but not blocking anything

### Rec Center floor walk

I captured everything you recalled in **`docs/rec-center-equipment.md`** — dumbbell
denominations, 26 stations, counts. That's enough to build the substitution engine against, so
**don't rush this.**

Two things you said are currently unusable as data:

- [ ] **"3 free weights"** — benches? barbell platforms? Olympic bars?
- [ ] **"1 machine"** — which machine?

And four of the sixteen muscle groups have **no dedicated equipment** in what you listed:

- [ ] `calves` — no calf raise machine mentioned
- [ ] `adductors` — no adductor machine mentioned
- [ ] `abs` — no ab station mentioned
- [ ] `glutes` — thin; only squat racks, no hip thrust

Either the Rec Center has gear you didn't recall, or those groups need bodyweight/outdoor
alternatives in the catalog. Left alone, the muscle map shows permanent cold spots there and it
reads as a bug.

Also worth grabbing while you're on the floor (full list in the doc):

- [ ] Barbell count + whether they're standard 45 lb Olympic bars
- [ ] Plate denominations — sets the minimum jump on every barbell lift
- [ ] Leg press? Smith machine? Calf raise?
- [ ] Cardio equipment + counts (needed for weight-loss plans)

### Two art decisions on the model

- [ ] **`tricep_r` → `triceps_r`** in Blender? Every other right-side node is `<group>_r`;
      triceps is the lone exception. Say the word and I'll special-case it in code instead —
      one line, but it's the kind of thing that confuses whoever reads it next.
- [ ] **Strip the stray animation.** There's a 52-byte one-frame action (`cvel_lAction`) keyed
      on `calves_l`. Harmless as long as the renderer doesn't autoplay, and I'll make sure it
      doesn't — but cleaner gone on your next export.
- [ ] **The 4 missing muscle groups** (lower back, obliques, rhomboids, tibialis) — add geometry
      in Blender, or use the fallback mapping? Suggested: rows → `lats`, obliques → `abs`,
      deadlift → `glutes` + `hamstrings`.

---

## ✅ Resolved since last session

| Item | Outcome |
| --- | --- |
| Supabase project | **Live.** Health check returns 200, signups enabled. |
| Supabase keys | In `.env`. I verified the key's `role` claim is **`anon`** — correct, safe for a client build. You did not paste `service_role`. |
| `SUPABASE_URL` | **I fixed a breaking typo** — see below |
| 3D model | **Done and web-ready.** 64,130 triangles, 1.08 MiB, all 16 muscle groups intact |
| Email confirmation | Decided: OFF (toggle still pending above) |
| Stack | Decided by me — see below |
| Android testing | Pixel 8 Pro over USB, no emulation |
| Landing page | Clean and minimal for now; redesign later |

### The URL fix

You pasted:

```
https://wtrhgkquswrqqjdndate.supabase.co/rest/v1/     ← the REST endpoint
```

Corrected to:

```
https://wtrhgkquswrqqjdndate.supabase.co              ← the project URL
```

`supabase_flutter` appends `/rest/v1`, `/auth/v1`, and `/storage/v1` itself. With the suffix
left in, every request would have hit `/rest/v1/rest/v1/...` and **auth would have failed
entirely** with an error that points nowhere near the actual cause. Easy mistake — the API
settings page shows the REST endpoint prominently right next to the Project URL.

### Stack — decided, since you asked me to judge

| Concern | Choice |
| --- | --- |
| State | `flutter_riverpod`, **no** code generation |
| Routing | `go_router` |
| Charts | `fl_chart` |
| Backend | `supabase_flutter` |

You said make it easier, and the non-obvious call is Riverpod. The simpler-*looking* option is
`provider` + `ChangeNotifier`, but then every screen hand-rolls its own loading / error / empty
handling. Riverpod's `AsyncValue` gives you that for free, and in an app where nearly every
screen loads from Supabase, that's less total code to write and less to get wrong. I'm skipping
`riverpod_generator` — the `build_runner` step is the part that actually costs beginners time.

Reasoning is recorded in `CLAUDE.md` → **Settled stack decisions** so it doesn't get
re-litigated.

### One setup step for the Pixel 8 Pro

- [ ] On the phone: **Settings → About phone → tap "Build number" 7 times**, then
      **Settings → System → Developer options → USB debugging ON**. Plug in, accept the
      pairing prompt, and `flutter devices` will list it.

Good call skipping emulation — your machine is `windows-arm64`, where the Android emulator is
genuinely painful. A physical device sidesteps that entirely.

---

## Status: the app is built and runs

170 tests pass, `dart analyze` is clean, `flutter build web` succeeds.

```bash
flutter run -d chrome --dart-define-from-file=.env
```

The `--dart-define-from-file=.env` flag is **required** — without it the app boots into a
setup screen instead of the real UI. That is deliberate, not a bug.

| Built | Where |
| --- | --- |
| Theme, light + dark, contrast-verified | `lib/core/theme/` |
| Landing page (minimal, no gradients) | `lib/features/landing/` |
| Login + sign-up | `lib/features/auth/` |
| Home dashboard (empty state) | `lib/features/home/` |
| Training/recommendation engine, 114 tests | `lib/core/training/` |
| 7 migrations, 24 RLS policies, seed data | `supabase/` |

### Still to do, in order

1. **Flip the email-confirmation toggle** (top of this file) — blocks real sign-in
2. **Apply the migrations** — `supabase/README.md` has both routes
3. **Create Pao** — sign up in the app, then one `UPDATE` to promote to admin
4. Then: workout logging UI, 3D muscle map screen, plan generation, progress charts

### Not built yet

Workout logging UI, the 3D muscle map screen, plan generation, progress charts, Fitbit
integration, offline sync. The training engine the logging UI needs is done and tested — it
just has no screen in front of it yet.

