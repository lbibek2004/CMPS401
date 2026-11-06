# AI coach — data path and how Gemini is kept on the facts

## The short version

**The math decides, Gemini phrases.** Every load, rep count, set count and exercise choice is
computed in Dart from the user's own logged sets and the real equipment list. Gemini only writes
one short sentence per item explaining the number, and a validator throws the sentence away if
it mentions anything that is not in the facts. If Gemini is down, unconfigured or rejected, the
app shows the engine's own sentence — nothing breaks.

## Model choice

**Gemini 1.5 Flash-8B is no longer available** — Google shut the 1.5 models down in September
2025. (It also had a 1M-token window, not 128k.) The function defaults to
`gemini-3.5-flash-lite`, Google's current recommended small/cheap model, and reads the
`GEMINI_MODEL` secret so it can be changed without a deploy.

The context window is not a constraint here: the brief is capped at 8 next-load items and 6
muscle gaps × 3 candidates, so a request is around 1–2k input tokens and output is capped at
600 tokens.

## 1. Getting the history out of Supabase

```text
workout_logs ── trainingHistoryProvider ─┐   last 84 days, RLS = own rows only
exercises ───── exerciseCatalogProvider ─┤   all rows (retired ones still name old sets)
rec_center_ ─── inventoryProvider ───────┤   availability + load ranges (migration 0008)
equipment                                 │
profiles ────── trainingProfileProvider ─┘   goal, days/week, unit, RPE vs RIR
                         │
                         v
                coachEngineProvider      lib/features/coach/data/coach_providers.dart
                         │
        ┌────────────────┼──────────────────┐
        v                v                  v
  coachBriefProvider  weeklyPlanProvider  (logger pre-fill, muscle sheet)
        │
        v
  coachInsightsProvider ── POST coach-insights (Edge Function) ── Gemini
```

One query feeds everything: `WorkoutRepository.setsSince(today − 83 days)`. It runs under the
signed-in user's JWT, so RLS returns only their rows — the engine never sees anyone else's data,
and neither does the Edge Function (it also runs as the user, not as service role).

## 2. What the engine computes (pure Dart, unit-tested)

`lib/features/coach/domain/coach_engine.dart`:

| Output | How |
| --- | --- |
| Next load per recent lift | `ProgressionEngine` (double progression, e1RM, RPE/RIR fatigue trend, 10% cap) on that exercise's sets |
| Rounded to real gear | `EquipmentLoadSpec` from the equipment row: 12.5 lb pins on leg extension, 20 lb on leg press, 5 lb dumbbells, 5 lb bar jumps |
| Undertrained muscles | `muscleStatusReport` (hard sets vs 10/week target) |
| What to do about them | Active exercises whose equipment is available, that train the muscle directly; ones the user has done first |
| This week's plan | `weekly_plan.dart`: split by days/week, slots filled from available exercises, rotates every 1–2 weeks |
| First time on an exercise | The machine's lightest setting, top of the rep range |

## 3. How Gemini is kept inside the source data

Five layers, in `supabase/functions/coach-insights/grounding.ts`. Each one catches what gets
past the previous.

1. **The client sends data, not text.** `CoachBrief.toJson()` contains only slugs, enums and
   numbers — no exercise names, notes or free text. `parseBrief()` re-checks every field
   (slug regex, enum membership, numeric ranges) and drops unknown keys. There is **no chat
   box**, so there is no user prompt to go off-topic with.
2. **Facts come from the database, server-side.** `groundBrief()` reads `exercises` and
   `rec_center_equipment` itself and drops any slug that is retired, out of service, or does
   not actually train the muscle it was offered for. Names and equipment labels in the prompt
   come from those rows, not from the client.
3. **Closed vocabulary.** The request uses Gemini structured output
   (`responseMimeType: application/json` + `responseSchema`). Every exercise and muscle field is
   an `enum` of exactly the grounded slugs, so constrained decoding cannot produce an exercise
   outside the list.
4. **The model never produces a number we use.** It writes a `tip` string per item.
   `validateModelOutput()` rejects any tip containing a number that is not one of that item's
   own facts (e.g. the engine said 145 lb; a tip saying 150 is dropped), any tip over 220
   characters, and anything with medical/diet/injury language. The system instruction says the
   same, but the validator is what enforces it.
5. **Nothing is required.** Rejected or missing tips are simply absent; the UI falls back to
   the engine's deterministic `reason` for that item.

Other settings: temperature 0.2, `maxOutputTokens` 600, 12 s timeout.

## Deploying

The function is written but **not deployed** — the Supabase CLI is not installed on the dev
machine, and the Gemini key is yours to create.

```bash
supabase login
supabase link --project-ref <your project ref>
supabase secrets set GEMINI_API_KEY=<key from aistudio.google.com>
supabase secrets set GEMINI_MODEL=gemini-3.5-flash-lite   # optional
supabase functions deploy coach-insights
```

Until then the app calls the function, gets a 404, and shows the engine's own sentences.
The key lives only in Supabase secrets — never in `.env`, which ships to the browser.

## Tests

```bash
node --test supabase/functions/coach-insights/grounding.test.ts   # 11 grounding tests
flutter test test/features/coach                                  # engine, plan, insight, history
```
