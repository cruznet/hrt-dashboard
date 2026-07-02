// worker.js — HRT Dashboard Health Auto Export ingest endpoint
// POST /api/healthkit — accepts JSON (Health Auto Export) or CSV data

const SUPABASE_URL = 'https://lnxhksnvcewtpwkaghrh.supabase.co';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/api/healthkit') {
      if (request.method === 'POST')    return handleIngest(request, env);
      if (request.method === 'OPTIONS') return new Response(null, { status: 204 });
      return new Response('Method Not Allowed', { status: 405 });
    }

    if (url.pathname === '/api/track') {
      if (request.method === 'POST')    return handleTrack(request, env);
      if (request.method === 'OPTIONS') return new Response(null, { status: 204 });
      return new Response('Method Not Allowed', { status: 405 });
    }

    if (url.pathname === '/api/account') {
      if (request.method === 'DELETE')  return handleDeleteAccount(request, env);
      if (request.method === 'OPTIONS') return new Response(null, { status: 204 });
      return new Response('Method Not Allowed', { status: 405 });
    }

    return env.ASSETS.fetch(request);
  },
};

// ── Funnel/retention analytics ingest ───────────────────────────────────────
// POST /api/track — fire-and-forget event logging from landing.html + index.html.
// Public (no auth) since events fire pre-signup with only an anon_id. Writes
// via the service role key so the analytics_events table needs no client-
// reachable RLS policy. Event names are allowlisted server-side to keep the
// table from becoming a dumping ground for arbitrary client-supplied strings.

const TRACK_EVENT_ALLOWLIST = new Set([
  'landing_view',
  'cta_click',
  'auth_complete',
  'onboarding_complete',
  'first_log',
  'feedback',
  'pwa_install_prompt_shown',
  'pwa_install_outcome',
  'pwa_installed',
]);

async function handleTrack(request, env) {
  if (!env.SUPABASE_SERVICE_KEY) return json({ error: 'SUPABASE_SERVICE_KEY not configured on worker' }, 500);

  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const eventName = typeof body.event_name === 'string' ? body.event_name.trim() : '';
  if (!TRACK_EVENT_ALLOWLIST.has(eventName)) return json({ error: 'Unknown event_name' }, 400);

  const anonId = typeof body.anon_id === 'string' ? body.anon_id.slice(0, 64) : null;
  const userId = typeof body.user_id === 'string' && /^[0-9a-f-]{36}$/i.test(body.user_id) ? body.user_id : null;
  // Cap properties payload size — analytics should never be a vector for large blobs
  let properties = (body.properties && typeof body.properties === 'object') ? body.properties : {};
  if (JSON.stringify(properties).length > 2000) properties = { _truncated: true };

  const res = await fetch(`${SUPABASE_URL}/rest/v1/analytics_events`, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        env.SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      'Prefer':        'return=minimal',
    },
    body: JSON.stringify([{ event_name: eventName, anon_id: anonId, user_id: userId, properties }]),
  });

  if (!res.ok) {
    const errText = await res.text();
    return json({ error: `Supabase error (${res.status}): ${errText}` }, 502);
  }

  return new Response(null, { status: 204 });
}

// ── Account deletion ─────────────────────────────────────────────────────────
// DELETE /api/account — verifies the user's JWT, then deletes the Supabase user
// via the admin API (service role). Supabase cascades the delete to user rows
// in application tables via FK ON DELETE CASCADE / SET NULL policies.

async function handleDeleteAccount(request, env) {
  if (!env.SUPABASE_SERVICE_KEY) return json({ error: 'SUPABASE_SERVICE_KEY not configured' }, 500);

  const token = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'Missing Authorization header' }, 401);

  // Verify the token and resolve the user ID
  const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      'apikey':        env.SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${token}`,
    },
  });

  if (!userRes.ok) return json({ error: 'Invalid or expired token' }, 401);

  const user = await userRes.json();
  const userId = user?.id;
  if (!userId || typeof userId !== 'string') return json({ error: 'Could not identify user' }, 400);

  // Delete via admin API — cascades to application table rows
  const deleteRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
    method: 'DELETE',
    headers: {
      'apikey':        env.SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${env.SUPABASE_SERVICE_KEY}`,
    },
  });

  if (!deleteRes.ok) {
    const errText = await deleteRes.text();
    return json({ error: `Supabase delete failed (${deleteRes.status}): ${errText}` }, 502);
  }

  return new Response(null, { status: 204 });
}

async function handleIngest(request, env) {
  const key = request.headers.get('X-Ingest-Key') || request.headers.get('x-ingest-key');
  if (!key || key !== env.INGEST_KEY) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const ct = (request.headers.get('Content-Type') || '').toLowerCase();
  let rows = [];

  try {
    if (ct.includes('application/json')) {
      const body = await request.json();
      rows = parseHAEJson(body);
    } else if (ct.includes('multipart/form-data')) {
      const fd = await request.formData();
      let csvText = '';
      for (const [, val] of fd.entries()) {
        const text = typeof val === 'string' ? val : (val instanceof File ? await val.text() : null);
        if (!text) continue;
        // Prefer the entry that looks like a HealthKit CSV
        if (text.includes('Date/Time') || text.includes('Heart Rate')) { csvText = text; break; }
        if (!csvText && text.trim().length > 0) csvText = text;
      }
      rows = parseCsv(csvText);
    } else {
      const text = await request.text();
      if (text.trimStart().startsWith('{')) {
        rows = parseHAEJson(JSON.parse(text));
      } else {
        rows = parseCsv(text);
      }
    }
  } catch (e) {
    return json({ error: `Parse error: ${e.message}` }, 400);
  }

  if (!rows.length) return json({ error: 'No rows parsed', ok: false }, 400);

  const userId = env.SUPABASE_USER_ID;
  if (!userId) return json({ error: 'SUPABASE_USER_ID not configured on worker' }, 500);
  if (!env.SUPABASE_SERVICE_KEY) return json({ error: 'SUPABASE_SERVICE_KEY not configured on worker' }, 500);

  const upsertRows = rows.map(r => ({ ...r, user_id: userId }));

  const res = await fetch(`${SUPABASE_URL}/rest/v1/healthkit_daily?on_conflict=user_id%2Cdate`, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        env.SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      'Prefer':        'resolution=merge-duplicates',
    },
    body: JSON.stringify(upsertRows),
  });

  if (!res.ok) {
    const errText = await res.text();
    return json({ error: `Supabase error (${res.status}): ${errText}` }, 502);
  }

  return json({ ok: true, rows: rows.length });
}

// ── CSV parser ─────────────────────────────────────────────────────────────────
// Maps Health Auto Export CSV column headers → healthkit_daily column names + type

const CSV_COL = {
  'Weight (lbs)':                          ['weight_lbs',         'float'],
  'Body Fat Percentage (%)':               ['body_fat_pct',       'float'],
  'Lean Body Mass (lbs)':                  ['lean_mass_lbs',      'float'],
  'Heart Rate Variability (ms)':           ['hrv_ms',             'float'],
  'Resting Heart Rate (bpm)':              ['resting_hr',         'int'],
  'Heart Rate [Min] (bpm)':               ['hr_min',             'int'],
  'Heart Rate [Avg] (bpm)':               ['hr_avg',             'int'],
  'Heart Rate [Max] (bpm)':               ['hr_max',             'int'],
  'Sleep Analysis [Total] (hr)':           ['sleep_total_hr',     'float'],
  'Sleep Analysis [Deep] (hr)':            ['sleep_deep_hr',      'float'],
  'Sleep Analysis [REM] (hr)':             ['sleep_rem_hr',       'float'],
  'Step Count (steps)':                    ['steps',              'int'],
  'Active Energy (kcal)':                  ['active_energy_kcal', 'float'],
  'Apple Exercise Time (min)':             ['exercise_min',       'int'],
  'Blood Pressure [Systolic] (mmHg)':      ['bp_systolic',        'int'],
  'Blood Pressure [Diastolic] (mmHg)':     ['bp_diastolic',       'int'],
  'Oxygen Saturation (%)':                 ['spo2_pct',           'float'],
};

function parseCsv(text) {
  const lines = (text || '').trim().split('\n').filter(l => l.trim());
  if (lines.length < 2) return [];

  const headers = lines[0].split(',').map(h => h.trim().replace(/\r/g, ''));
  const result  = [];

  for (let i = 1; i < lines.length; i++) {
    const vals = lines[i].split(',');
    const raw  = {};
    headers.forEach((h, j) => { raw[h] = (vals[j] || '').trim().replace(/\r/g, ''); });

    const dateStr = raw['Date/Time'];
    if (!dateStr) continue;

    // "2026-06-17 00:00:00 +0000" → "2026-06-17"
    const date = dateStr.split(' ')[0];
    // All rows must have identical keys for Supabase batch upsert — use null for missing values
    const row  = {
      date,
      weight_lbs: null, body_fat_pct: null, lean_mass_lbs: null,
      hrv_ms: null, resting_hr: null, hr_min: null, hr_avg: null, hr_max: null,
      sleep_total_hr: null, sleep_deep_hr: null, sleep_rem_hr: null,
      steps: null, active_energy_kcal: null, exercise_min: null,
      bp_systolic: null, bp_diastolic: null, spo2_pct: null,
    };

    for (const [csvCol, [dbCol, type]] of Object.entries(CSV_COL)) {
      const v = raw[csvCol];
      if (!v) continue;
      const n = parseFloat(v);
      if (isNaN(n)) continue;
      row[dbCol] = type === 'int' ? Math.round(n) : n;
    }

    result.push(row);
  }

  return result;
}

// ── Health Auto Export JSON parser ─────────────────────────────────────────────
// Handles Health Auto Export v1/v2 metric payload format

const JSON_METRIC = {
  'weight_body_mass':             d => ({ weight_lbs:         num(d.qty) }),
  'body_fat_percentage':          d => ({ body_fat_pct:       num(d.qty) }),
  'lean_body_mass':               d => ({ lean_mass_lbs:      num(d.qty) }),
  'heart_rate_variability_sdnn':  d => ({ hrv_ms:             num(d.avg ?? d.qty) }),
  'heart_rate_variability':       d => ({ hrv_ms:             num(d.avg ?? d.qty) }),
  'resting_heart_rate':           d => ({ resting_hr:         int(d.avg ?? d.qty) }),
  'heart_rate': d => ({
    ...(d.min != null ? { hr_min: int(d.min) } : {}),
    ...(d.max != null ? { hr_max: int(d.max) } : {}),
    ...(d.avg != null ? { hr_avg: int(d.avg) } : {}),
  }),
  'step_count':                   d => ({ steps:              int(d.qty ?? d.sum) }),
  'active_energy':                d => ({ active_energy_kcal: num(d.qty ?? d.sum) }),
  'active_energy_burned':         d => ({ active_energy_kcal: num(d.qty ?? d.sum) }),
  'apple_exercise_time':          d => ({ exercise_min:       int(d.qty ?? d.sum) }),
  'blood_pressure': d => ({
    ...(d.systolic  != null ? { bp_systolic:  int(d.systolic)  } : {}),
    ...(d.diastolic != null ? { bp_diastolic: int(d.diastolic) } : {}),
  }),
  'oxygen_saturation':            d => ({ spo2_pct:           num(d.qty) }),
  'blood_oxygen_saturation':      d => ({ spo2_pct:           num(d.avg ?? d.qty) }),
  'sleep_analysis': d => ({
    ...(d.qty != null || d.totalSleepTime != null || d.totalSleep != null ? { sleep_total_hr: num(d.qty ?? d.totalSleepTime ?? d.totalSleep) } : {}),
    ...(d.deep         != null || d.deepSleepTime  != null ? { sleep_deep_hr:  num(d.deep         ?? d.deepSleepTime)  } : {}),
    ...(d.rem          != null || d.remSleepTime   != null ? { sleep_rem_hr:   num(d.rem          ?? d.remSleepTime)   } : {}),
  }),
};

function parseHAEJson(body) {
  const metrics = body?.data?.metrics ?? body?.metrics ?? [];
  const byDate  = {};

  for (const metric of metrics) {
    const mapper = JSON_METRIC[metric.name];
    if (!mapper) continue;

    for (const d of (metric.data ?? [])) {
      const date = (d.date || '').split(' ')[0];
      if (!date) continue;
      if (!byDate[date]) byDate[date] = {
        date,
        weight_lbs: null, body_fat_pct: null, lean_mass_lbs: null,
        hrv_ms: null, resting_hr: null, hr_min: null, hr_avg: null, hr_max: null,
        sleep_total_hr: null, sleep_deep_hr: null, sleep_rem_hr: null,
        steps: null, active_energy_kcal: null, exercise_min: null,
        bp_systolic: null, bp_diastolic: null, spo2_pct: null,
      };
      const mapped = mapper(d);
      for (const [k, v] of Object.entries(mapped)) {
        if (v != null) byDate[date][k] = v;
      }
    }
  }

  return Object.values(byDate);
}

// ── Helpers ────────────────────────────────────────────────────────────────────

function num(v) { const n = parseFloat(v); return isNaN(n) ? undefined : n; }
function int(v) { const n = parseFloat(v); return isNaN(n) ? undefined : Math.round(n); }

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
