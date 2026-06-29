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

    return env.ASSETS.fetch(request);
  },
};

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

  const res = await fetch(`${SUPABASE_URL}/rest/v1/healthkit_daily`, {
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
  'Weight (lbs)':                    ['weight_lbs',         'float'],
  'Body Fat Percentage (%)':         ['body_fat_pct',       'float'],
  'Lean Body Mass (lbs)':            ['lean_mass_lbs',      'float'],
  'Heart Rate Variability (ms)':     ['hrv_ms',             'float'],
  'Resting Heart Rate (bpm)':        ['resting_hr',         'int'],
  'Heart Rate [Min] (bpm)':          ['hr_min',             'int'],
  'Heart Rate [Avg] (bpm)':          ['hr_avg',             'int'],
  'Heart Rate [Max] (bpm)':          ['hr_max',             'int'],
  'Sleep Analysis [Total] (hr)':     ['sleep_total_hr',     'float'],
  'Sleep Analysis [Deep] (hr)':      ['sleep_deep_hr',      'float'],
  'Sleep Analysis [REM] (hr)':       ['sleep_rem_hr',       'float'],
  'Step Count (steps)':              ['steps',              'int'],
  'Active Energy (kcal)':            ['active_energy_kcal', 'float'],
  'Apple Exercise Time (min)':       ['exercise_min',       'int'],
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
    const row  = { date };

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
  'sleep_analysis': d => ({
    ...(d.qty          != null || d.totalSleepTime != null ? { sleep_total_hr: num(d.qty          ?? d.totalSleepTime) } : {}),
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
      if (!byDate[date]) byDate[date] = { date };
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
