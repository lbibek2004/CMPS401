// =============================================================================
// coach-insights  --  Supabase Edge Function (Deno)
// =============================================================================
// Turns the app's deterministic CoachBrief into short, plain-language tips with
// Gemini. The numbers are already decided by the Dart engine before this runs;
// this function only phrases them. How the model is kept inside the facts is
// documented in grounding.ts and docs/ai-coach.md.
//
// Secrets (never in the client build):
//   supabase secrets set GEMINI_API_KEY=...
//   supabase secrets set GEMINI_MODEL=gemini-3.5-flash-lite   # optional
// SUPABASE_URL and SUPABASE_ANON_KEY are injected by the platform.
//
// Deploy:   supabase functions deploy coach-insights
//
// Responses:
//   200 { summary, next_loads: {slug: tip}, muscle_gaps: {group: {exercise_slug, tip}}, model }
//   400 malformed brief       401 not signed in
//   503 GEMINI_API_KEY unset  502 Gemini failed
// The app treats every non-200 as "no AI text" and shows the engine's own
// sentences, so this function is optional, not load-bearing.
// =============================================================================

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import {
  BriefError,
  buildResponseSchema,
  buildUserPrompt,
  groundBrief,
  parseBrief,
  SYSTEM_INSTRUCTION,
  validateModelOutput,
} from './grounding.ts';

// Gemini 1.5 Flash-8B was shut down in September 2025. Flash-Lite is the
// current small, cheap tier. Override with the GEMINI_MODEL secret.
const DEFAULT_MODEL = 'gemini-3.5-flash-lite';
const GEMINI_TIMEOUT_MS = 12_000;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  // ---- Who is asking. The client is built with the caller's JWT, so every
  // read below runs under RLS as that user -- never as service role.
  const authorization = req.headers.get('Authorization');
  if (!authorization) return json(401, { error: 'not_signed_in' });
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json(401, { error: 'not_signed_in' });

  // ---- Layer 1: the payload, as data.
  let brief;
  try {
    brief = parseBrief(await req.json());
  } catch (error) {
    const message = error instanceof BriefError ? error.message : 'invalid_json';
    return json(400, { error: 'bad_brief', message });
  }

  // ---- Layer 2: the source of truth is the database, read here.
  const [exercises, equipment] = await Promise.all([
    supabase.from('exercises').select('slug, name, primary_muscle_groups, required_equipment, is_active'),
    supabase.from('rec_center_equipment').select('equipment_type, label, availability_status, quantity'),
  ]);
  if (exercises.error || equipment.error) return json(502, { error: 'catalog_unavailable' });
  const grounded = groundBrief(brief, exercises.data ?? [], equipment.data ?? []);

  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) return json(503, { error: 'ai_not_configured' });
  const model = Deno.env.get('GEMINI_MODEL') || DEFAULT_MODEL;

  // ---- Layer 3: constrained decoding against a closed vocabulary.
  const request = {
    systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
    contents: [{ role: 'user', parts: [{ text: buildUserPrompt(grounded) }] }],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 600,
      responseMimeType: 'application/json',
      responseSchema: buildResponseSchema(grounded),
    },
  };

  let raw: string;
  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
        body: JSON.stringify(request),
        signal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
      },
    );
    if (!response.ok) {
      console.error('gemini', response.status, await response.text());
      return json(502, { error: 'ai_failed', status: response.status });
    }
    const body = await response.json();
    raw = body?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? '').join('') ?? '';
  } catch (error) {
    console.error('gemini', error);
    return json(502, { error: 'ai_failed' });
  }

  // ---- Layers 4 + 5: every sentence is checked against its own facts.
  return json(200, { ...validateModelOutput(raw, grounded), model });
});
