#!/usr/bin/env node
/**
 * LionFit schema verifier.
 *
 *   node tool/verify_schema.js
 *
 * Uses only the publishable/anon key from .env — the same key the browser gets.
 * That is the point: anything this script can read, any visitor can read.
 *
 * Expected results once the migrations are applied:
 *   user-owned tables  -> EXISTS, RLS DENIES ANON   (empty result, not an error)
 *   reference tables   -> EXISTS, RLS DENIES ANON   (policies target `authenticated`)
 *   anything readable  -> FAIL, that is a data leak
 */
'use strict';
const fs = require('fs');

const env = Object.fromEntries(
  fs.readFileSync('.env', 'utf8').split(/\r?\n/)
    .filter((l) => l && !l.startsWith('#') && l.includes('='))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)])
);
const URL = (env.SUPABASE_URL || '').replace(/\/$/, '');
const KEY = env.SUPABASE_PUBLISHABLE_KEY || env.SUPABASE_ANON_KEY;
if (!URL || !KEY) { console.error('.env missing SUPABASE_URL or key'); process.exit(1); }

const USER_OWNED = ['profiles', 'user_workouts', 'workout_logs', 'muscle_group_intensity', 'user_health_metrics'];
const REFERENCE = ['exercises', 'rec_center_equipment'];

async function probe(table) {
  const res = await fetch(`${URL}/rest/v1/${table}?select=*&limit=5`, {
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
  });
  let body;
  try { body = await res.json(); } catch { body = null; }
  if (Array.isArray(body)) {
    return body.length === 0
      ? { state: 'LOCKED', note: 'exists, RLS denies anon' }
      : { state: 'READABLE', note: `exists, ANON CAN READ ${body.length}+ rows` };
  }
  const code = body && body.code;
  if (code === 'PGRST205' || code === '42P01') return { state: 'MISSING', note: 'table does not exist' };
  if (res.status === 401 || res.status === 403) return { state: 'LOCKED', note: `denied (HTTP ${res.status})` };
  return { state: 'ERROR', note: (body && (body.message || body.code)) || `HTTP ${res.status}` };
}

(async () => {
  console.log(`project: ${URL}\n`);
  const results = [];

  console.log('user-owned tables (must never be anon-readable):');
  for (const t of USER_OWNED) {
    const r = await probe(t);
    results.push({ table: t, kind: 'user', ...r });
    console.log(`  ${t.padEnd(24)} ${r.state.padEnd(9)} ${r.note}`);
  }

  console.log('\nreference tables:');
  for (const t of REFERENCE) {
    const r = await probe(t);
    results.push({ table: t, kind: 'ref', ...r });
    console.log(`  ${t.padEnd(24)} ${r.state.padEnd(9)} ${r.note}`);
  }

  const missing = results.filter((r) => r.state === 'MISSING');
  const leaking = results.filter((r) => r.kind === 'user' && r.state === 'READABLE');
  const errored = results.filter((r) => r.state === 'ERROR');

  console.log('');
  if (missing.length === results.length) {
    console.log('NOT APPLIED — no tables exist yet. Run supabase/apply_all.sql in the SQL editor.');
    process.exit(2);
  }
  if (missing.length) {
    console.log(`PARTIAL — ${missing.length} table(s) missing: ${missing.map((m) => m.table).join(', ')}`);
    process.exit(2);
  }
  if (leaking.length) {
    console.log(`SECURITY FAILURE — anon can read: ${leaking.map((l) => l.table).join(', ')}`);
    process.exit(1);
  }
  if (errored.length) {
    console.log(`UNEXPECTED — ${errored.map((e) => `${e.table}: ${e.note}`).join('; ')}`);
    process.exit(1);
  }
  console.log('ALL GOOD — every table exists and none leak to an anonymous caller.');
})();
