# Hevy Daily Background Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync every user's Hevy workouts and body measurements once a day via a Cloudflare Worker Cron Trigger, independent of whether they open the app, so PR-based and bodyweight-based Goals don't sit stale.

**Architecture:** A new `scheduled()` export in `worker.js`, triggered daily by a Cloudflare Cron Trigger, reads every `user_settings` row with a `hevy_api_key` (via the existing `SUPABASE_SERVICE_KEY` service-role secret), fetches each user's raw Hevy workouts + body measurements, and caches them in two new `user_settings` columns. The client's `loadUserData()` picks up those columns on next load: workouts go straight into the existing `hrt_hevy_workouts` localStorage cache (the client always re-derives PRs fresh from that), and raw measurements are merged into `physique_measurements` using the client's own existing, timezone-aware merge logic (extracted into a reusable function so there's one implementation, not two). The existing manual "Sync" button and 2h/6h open-app auto-sync are untouched.

**Tech Stack:** Vanilla JS (`index.html`), Cloudflare Workers (`worker.js`, `wrangler.jsonc`), Supabase Postgres/PostgREST.

## Global Constraints

- No new Cloudflare secret — reuse the existing `env.SUPABASE_SERVICE_KEY` (already used by `/api/track` and `/api/account` in `worker.js`).
- The Worker must NOT compute final merged `physique_measurements` itself — it has no browser timezone, and `localDate()`-based date bucketing must stay client-side to avoid reintroducing the rollover bug fixed in commit `efd4935`. The Worker only caches Hevy's **raw** responses.
- Existing client-triggered sync paths (manual "Sync from Hevy" button, `hevyAutoSync()` 2h staleness, `hevyMeasAutoSync()` 6h staleness) are unchanged.
- Cron schedule: `"0 9 * * *"` (once daily, 09:00 UTC).
- Per-user try/catch in the cron loop — one user's failure (revoked key, API error) is logged and skipped, never aborts the run. No retries.
- No client-facing sync-failure UI in this iteration.
- Sequential per-user processing in the cron — no concurrency/queueing (current user count doesn't warrant it).
- New `user_settings` columns: `hevy_workouts_cache jsonb DEFAULT '[]'`, `hevy_measurements_raw_cache jsonb DEFAULT '[]'`, `hevy_cron_synced_at timestamptz`.
- Client restore of these columns follows the existing "Supabase wins on load" pattern in `loadUserData()` — no timestamp comparison, consistent with every other synced field.

---

## Pre-flight: Run SQL in Supabase

Before starting Task 2 or Task 3, run this once in the Supabase dashboard (SQL Editor) — same migration pattern already used for the `goals` column:

```sql
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_workouts_cache jsonb DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_measurements_raw_cache jsonb DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_cron_synced_at timestamptz;
```

Also append the same statements to `supabase-schema.sql` (after the existing `-- Goals sync` migration at the end of the file) so the schema file stays the source of truth:

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
cat >> supabase-schema.sql << 'EOF'

-- Hevy daily background sync: cache raw Hevy data for the cron job
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_workouts_cache jsonb DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_measurements_raw_cache jsonb DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_cron_synced_at timestamptz;
EOF
git add supabase-schema.sql
git commit -m "$(cat <<'COMMIT_EOF'
schema: add hevy_workouts_cache, hevy_measurements_raw_cache, hevy_cron_synced_at to user_settings

Pre-flight for the daily Hevy background cron sync — columns the
Worker's scheduled() handler writes to and loadUserData() reads from.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
COMMIT_EOF
)"
```

**Verify the columns exist** (read-only check against the live PostgREST schema, no auth needed — an unrecognized column name returns a 400 error, a recognized one returns `[]` even unauthenticated):

```bash
curl -s "https://lnxhksnvcewtpwkaghrh.supabase.co/rest/v1/user_settings?select=hevy_workouts_cache,hevy_measurements_raw_cache,hevy_cron_synced_at&limit=1" \
  -H "apikey: sb_publishable__lU8rYLjeTMoAgXANKsKKA_9Xgau8bm"
```

Expected: `[]` (empty array, not an error object mentioning "column ... does not exist").

---

### Task 1: Extract `hevyMergeRawMeasurements()` and add logic tests

**Files:**
- Modify: `index.html:7873-7954` (`hevyMeasSync()` and the block above it)
- Modify: `tests/bloodwork-hevy-logic.html`

**Interfaces:**
- Consumes: `localDate(d)` (existing, index.html:3459), `measLoad()`, `measSaveAll(list)` (existing)
- Produces: `hevyMergeRawMeasurements(rawEntries, existingList)` → `{ list, added, updated }` — pure function, no localStorage/DOM access. Used by `hevyMeasSync()` in this task, and by `loadUserData()` in Task 2.

- [ ] **Step 1: Add failing tests to `tests/bloodwork-hevy-logic.html`**

Insert this new section right before the final `document.getElementById('summary')...` line (end of file):

```html
// ── hevyMergeRawMeasurements (dedup + merge raw Hevy body measurements) ──────
function localDate(d) {
  if (!d) d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

section('hevyMergeRawMeasurements');

// New date, no existing entry — should add with lbs conversion
{
  const raw = [{ date: '2026-07-01', weight_kg: 90, fat_percent: 15.234 }];
  const { list, added, updated } = hevyMergeRawMeasurements(raw, []);
  assert('New entry added',                 added, 1);
  assert('No entries updated',              updated, 0);
  assert('Weight converted kg→lbs',         list[0].measurements.weight, +(90 * 2.20462).toFixed(1));
  assert('Fat % rounded to 2 decimals',     list[0].measurements.bf, 15.23);
}

// Existing manual entry — Hevy fills missing field, never overwrites existing field
{
  const existing = [{ id: 'm1', date: '2026-07-02', notes: '', measurements: { weight: 201.5 } }];
  const raw = [{ date: '2026-07-02', weight_kg: 91, fat_percent: 14 }];
  const { list, added, updated } = hevyMergeRawMeasurements(raw, existing);
  assert('Existing date updated, not added', [added, updated], [0, 1]);
  assert('Manual weight value preserved',    list[0].measurements.weight, 201.5);
  assert('Missing bf field filled from Hevy', list[0].measurements.bf, 14);
}

// Two Hevy entries same date — most non-null fields wins
{
  const raw = [
    { date: '2026-07-03', weight_kg: 92 },
    { date: '2026-07-03', weight_kg: 92.5, fat_percent: 13.8 },
  ];
  const { list } = hevyMergeRawMeasurements(raw, []);
  assert('Dedup keeps entry with more fields', list[0].measurements.bf, 13.8);
}

// Entry with no usable fields (both null) — skipped entirely
{
  const raw = [{ date: '2026-07-04', weight_kg: null, fat_percent: null }];
  const { list, added, updated } = hevyMergeRawMeasurements(raw, []);
  assert('All-null entry skipped', [list.length, added, updated], [0, 0, 0]);
}

// Empty raw input — no-op, returns existing list unchanged
{
  const existing = [{ id: 'm1', date: '2026-07-01', notes: '', measurements: { weight: 200 } }];
  const { list, added, updated } = hevyMergeRawMeasurements([], existing);
  assert('Empty input is a no-op', [list === existing, added, updated], [true, 0, 0]);
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Start the local server if it isn't already running, then load the test page:

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
python3 server.py &
sleep 1
curl -s http://localhost:3000/tests/bloodwork-hevy-logic.html > /dev/null && echo "server up"
```

Open `http://localhost:3000/tests/bloodwork-hevy-logic.html` in a browser. Expected: a `ReferenceError: hevyMergeRawMeasurements is not defined` surfaces in the console and/or the new assertions fail, since the function doesn't exist yet.

- [ ] **Step 3: Extract `hevyMergeRawMeasurements()` in `index.html`**

Find (`index.html:7880-7941`, inside `hevyMeasSync()`):

```js
    if (!allEntries.length) { showToast('No body measurements found in Hevy.', 'info'); return; }

    // Dedup by date — keep entry with most non-null fields (handles multiple weigh-ins per day)
    const dedupMap = {};
    for (const h of allEntries) {
      const dateStr = (h.date || h.created_at || '').slice(0, 10);
      if (!dateStr) continue;
      const date = localDate(new Date(dateStr));
      const prev = dedupMap[date];
      const fields = (h.weight_kg != null ? 1 : 0) + (h.fat_percent != null ? 1 : 0);
      const prevFields = prev ? (prev.weight_kg != null ? 1 : 0) + (prev.fat_percent != null ? 1 : 0) : -1;
      if (!prev || fields >= prevFields) dedupMap[date] = h;
    }

    const list = measLoad();
    // Build date index for O(1) lookup
    const byDate = {};
    list.forEach((e, i) => { byDate[e.date] = i; });

    let added = 0, updated = 0;
    for (const [date, h] of Object.entries(dedupMap)) {
      const weightKg = h.weight_kg ?? null;
      const hevyMeas = {};
      if (weightKg != null)        hevyMeas.weight = +(weightKg * 2.20462).toFixed(1);
      if (h.fat_percent != null)   hevyMeas.bf     = +h.fat_percent.toFixed(2);
      if (!Object.keys(hevyMeas).length) continue;

      if (byDate[date] !== undefined) {
        // Merge: existing manual values always win — spread Hevy first, existing on top
        const existing = list[byDate[date]];
        const merged = { ...hevyMeas, ...(existing.measurements || {}) };
        list[byDate[date]] = { ...existing, measurements: merged };
        updated++;
      } else {
        list.push({ id: crypto.randomUUID(), date, notes: '', measurements: hevyMeas });
        byDate[date] = list.length - 1;
        added++;
      }
    }

    measSaveAll(list);
    localStorage.setItem(HEVY_MEAS_SYN_LS, new Date().toISOString());
    renderPhysiquePage();

    const parts = [added && `${added} added`, updated && `${updated} updated`].filter(Boolean);
    if (parts.length) showToast(`Hevy body sync complete: ${parts.join(', ')}.`, 'success');
```

Replace with:

```js
    if (!allEntries.length) { showToast('No body measurements found in Hevy.', 'info'); return; }

    const { list, added, updated } = hevyMergeRawMeasurements(allEntries, measLoad());
    measSaveAll(list);
    localStorage.setItem(HEVY_MEAS_SYN_LS, new Date().toISOString());
    renderPhysiquePage();

    const parts = [added && `${added} added`, updated && `${updated} updated`].filter(Boolean);
    if (parts.length) showToast(`Hevy body sync complete: ${parts.join(', ')}.`, 'success');
```

Then find the lines directly above `hevyMeasAutoSync()` (`index.html:7871-7873`):

```js
  }
}

function hevyMeasAutoSync() {
```

Replace with (inserting the extracted function between them):

```js
  }
}

// hevyMergeRawMeasurements is pure — no localStorage/DOM access — so both the
// live-fetch sync (hevyMeasSync, below) and the daily-cron-cache restore path
// (loadUserData) share one implementation instead of two. Dedup keeps the
// Hevy entry with the most non-null fields per date; existing (manual)
// measurement values always win over Hevy's for the same date+field.
function hevyMergeRawMeasurements(rawEntries, existingList) {
  if (!rawEntries || !rawEntries.length) return { list: existingList, added: 0, updated: 0 };

  const dedupMap = {};
  for (const h of rawEntries) {
    const dateStr = (h.date || h.created_at || '').slice(0, 10);
    if (!dateStr) continue;
    const date = localDate(new Date(dateStr));
    const prev = dedupMap[date];
    const fields = (h.weight_kg != null ? 1 : 0) + (h.fat_percent != null ? 1 : 0);
    const prevFields = prev ? (prev.weight_kg != null ? 1 : 0) + (prev.fat_percent != null ? 1 : 0) : -1;
    if (!prev || fields >= prevFields) dedupMap[date] = h;
  }

  const list = existingList.slice();
  const byDate = {};
  list.forEach((e, i) => { byDate[e.date] = i; });

  let added = 0, updated = 0;
  for (const [date, h] of Object.entries(dedupMap)) {
    const weightKg = h.weight_kg ?? null;
    const hevyMeas = {};
    if (weightKg != null)        hevyMeas.weight = +(weightKg * 2.20462).toFixed(1);
    if (h.fat_percent != null)   hevyMeas.bf     = +h.fat_percent.toFixed(2);
    if (!Object.keys(hevyMeas).length) continue;

    if (byDate[date] !== undefined) {
      const existing = list[byDate[date]];
      const merged = { ...hevyMeas, ...(existing.measurements || {}) };
      list[byDate[date]] = { ...existing, measurements: merged };
      updated++;
    } else {
      list.push({ id: crypto.randomUUID(), date, notes: '', measurements: hevyMeas });
      byDate[date] = list.length - 1;
      added++;
    }
  }

  return { list, added, updated };
}

function hevyMeasAutoSync() {
```

- [ ] **Step 4: Run the tests again to verify they pass**

Refresh `http://localhost:3000/tests/bloodwork-hevy-logic.html`. Expected: summary shows `0 failed`, including all 5 new `hevyMergeRawMeasurements` assertions.

- [ ] **Step 5: Run the full existing test suite to confirm no regression**

```bash
cd ~/.claude/skills/playwright-skill && node run.js "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard/tests/smoke-test.js"
```

Expected: all existing checks still pass (this refactor is behavior-preserving — `hevyMeasSync()`'s only change is calling the extracted function instead of inlining the same logic).

- [ ] **Step 6: Commit**

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
git add index.html tests/bloodwork-hevy-logic.html
git commit -m "$(cat <<'EOF'
refactor: extract hevyMergeRawMeasurements from hevyMeasSync

Pure function with no localStorage/DOM access, so the upcoming daily
cron-cache restore path (loadUserData) can reuse the exact same
dedup/merge logic as the live-fetch sync button, instead of a second
copy drifting out of sync.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Client restores cached Hevy data on load

**Files:**
- Modify: `index.html:3993-4032` (`loadUserData()`)

**Interfaces:**
- Consumes: `hevyMergeRawMeasurements(rawEntries, existingList)` (Task 1), `HEVY_DATA_LS` (existing const, index.html:7787), `measLoad()` (existing)
- Produces: on sign-in / load, `hrt_hevy_workouts` and `hrt_measurements` localStorage are seeded from `settings.hevy_workouts_cache` / `settings.hevy_measurements_raw_cache` if present, without waiting for the user to visit the Workouts/Physique tab.

- [ ] **Step 1: Add cache-restore block to `loadUserData()`**

Find (`index.html:4004-4007`):

```js
      if (Array.isArray(settings.physique_measurements) && settings.physique_measurements.length)
        localStorage.setItem('hrt_measurements', JSON.stringify(settings.physique_measurements));
      if (Array.isArray(settings.goals) && settings.goals.length)
        localStorage.setItem('hrt_goals', JSON.stringify(settings.goals));
```

Replace with:

```js
      if (Array.isArray(settings.physique_measurements) && settings.physique_measurements.length)
        localStorage.setItem('hrt_measurements', JSON.stringify(settings.physique_measurements));
      if (Array.isArray(settings.hevy_workouts_cache) && settings.hevy_workouts_cache.length)
        localStorage.setItem(HEVY_DATA_LS, JSON.stringify(settings.hevy_workouts_cache));
      if (Array.isArray(settings.hevy_measurements_raw_cache) && settings.hevy_measurements_raw_cache.length) {
        const { list } = hevyMergeRawMeasurements(settings.hevy_measurements_raw_cache, measLoad());
        localStorage.setItem('hrt_measurements', JSON.stringify(list));
      }
      if (Array.isArray(settings.goals) && settings.goals.length)
        localStorage.setItem('hrt_goals', JSON.stringify(settings.goals));
```

Note the ordering: `physique_measurements` restores first, then the Hevy raw-cache merge reads `measLoad()` (which now reflects that just-restored data) and applies on top of it — so a manual entry synced from Supabase still wins over a same-date Hevy value, exactly as it would live.

- [ ] **Step 2: Verify placement**

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
grep -n "hevy_workouts_cache\|hevy_measurements_raw_cache" index.html
```

Expected: both strings appear exactly once, inside `loadUserData()` (no occurrences elsewhere yet — Task 3 doesn't touch `index.html`).

- [ ] **Step 3: Manual browser verification (no real Hevy account needed)**

This exercises the restore path directly without needing a live cron run or a real Hevy API key — it simulates what `loadUserData()` would do with cached data from Supabase.

```bash
python3 server.py &
sleep 1
```

Open `http://localhost:3000/` in a browser, open DevTools console, and run:

```js
localStorage.clear();
showApp();
const fakeSettings = {
  hevy_workouts_cache: [{ start_time: Date.now()/1000, exercises: [{ title: 'Bench Press', sets: [{ weight_kg: 100, reps: 3 }] }] }],
  hevy_measurements_raw_cache: [{ date: new Date().toISOString().slice(0,10), weight_kg: 90 }],
};
if (Array.isArray(fakeSettings.hevy_workouts_cache) && fakeSettings.hevy_workouts_cache.length)
  localStorage.setItem(HEVY_DATA_LS, JSON.stringify(fakeSettings.hevy_workouts_cache));
if (Array.isArray(fakeSettings.hevy_measurements_raw_cache) && fakeSettings.hevy_measurements_raw_cache.length) {
  const { list } = hevyMergeRawMeasurements(fakeSettings.hevy_measurements_raw_cache, measLoad());
  localStorage.setItem('hrt_measurements', JSON.stringify(list));
}
JSON.parse(localStorage.getItem(HEVY_DATA_LS)).length; // expect 1
JSON.parse(localStorage.getItem('hrt_measurements'))[0].measurements.weight; // expect ~198.4 (90kg in lbs)
```

Expected: both expressions return the values noted in the comments, confirming the restore logic (copied verbatim from Step 1's diff) works end-to-end against fake cached data.

- [ ] **Step 4: Commit**

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
git add index.html
git commit -m "$(cat <<'EOF'
feat: restore cron-cached Hevy data in loadUserData

Seeds hrt_hevy_workouts and merges hrt_measurements from the new
hevy_workouts_cache / hevy_measurements_raw_cache Supabase columns on
load, so PR- and bodyweight-based Goals have data on a fresh
device/session without needing to visit Workouts/Physique first.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Worker cron trigger + daily sync handler

**Files:**
- Modify: `worker.js`
- Modify: `wrangler.jsonc`
- Modify: `tests/PRE-DEPLOY-CHECKLIST.md`

**Interfaces:**
- Consumes: `env.SUPABASE_SERVICE_KEY` (existing secret), `SUPABASE_URL` (existing const, worker.js:4)
- Produces: `scheduled(event, env, ctx)` export; `runHevyDailySync(env)`, `syncOneUserHevyData(env, userId, hevyApiKey)`, `fetchHevyWorkouts(apiKey)`, `fetchHevyBodyMeasurementsRaw(apiKey)` — none of these are consumed by `index.html`, this task is backend-only.

- [ ] **Step 1: Add the cron trigger to `wrangler.jsonc`**

Find:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "hrt-dashboard",
  "main": "worker.js",
  "compatibility_date": "2026-06-29",
  "observability": {
    "enabled": true
  },
```

Replace with:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "hrt-dashboard",
  "main": "worker.js",
  "compatibility_date": "2026-06-29",
  "triggers": {
    "crons": ["0 9 * * *"]
  },
  "observability": {
    "enabled": true
  },
```

- [ ] **Step 2: Add `HEVY_BASE` const and the `scheduled` export in `worker.js`**

Find (`worker.js:1-6`):

```js
// worker.js — HRT Dashboard Health Auto Export ingest endpoint
// POST /api/healthkit — accepts JSON (Health Auto Export) or CSV data

const SUPABASE_URL = 'https://lnxhksnvcewtpwkaghrh.supabase.co';

export default {
  async fetch(request, env) {
```

Replace with:

```js
// worker.js — HRT Dashboard Health Auto Export ingest endpoint
// POST /api/healthkit — accepts JSON (Health Auto Export) or CSV data

const SUPABASE_URL = 'https://lnxhksnvcewtpwkaghrh.supabase.co';
const HEVY_BASE     = 'https://api.hevyapp.com/v1';

export default {
  async fetch(request, env) {
```

Find the end of the `export default { ... }` block (`worker.js:29-30`):

```js
    return env.ASSETS.fetch(request);
  },
};
```

Replace with:

```js
    return env.ASSETS.fetch(request);
  },

  // Cron Trigger — see wrangler.jsonc `triggers.crons`. Fires once daily so
  // Hevy data refreshes even if the user never opens the app that day.
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runHevyDailySync(env));
  },
};
```

- [ ] **Step 3: Add the sync functions to `worker.js`**

Insert this new section right after the closing `};` of the `export default { ... }` block (before the existing `// ── Funnel/retention analytics ingest ──` comment):

```js
// ── Hevy daily background sync ──────────────────────────────────────────────
// Caches RAW Hevy data only (no dedup/merge) — a Worker has no browser
// timezone to bucket measurement dates by, and the client's existing
// hevyMergeRawMeasurements() already does that correctly using the user's
// local calendar date (see index.html). Doing the merge here would silently
// reintroduce the local-date rollover bug fixed in commit efd4935.

async function runHevyDailySync(env) {
  if (!env.SUPABASE_SERVICE_KEY) { console.error('[hevyCron] SUPABASE_SERVICE_KEY not configured'); return; }

  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/user_settings?select=user_id,hevy_api_key&hevy_api_key=not.is.null`,
    { headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}` } }
  );
  if (!res.ok) { console.error(`[hevyCron] failed to list users: ${res.status} ${await res.text()}`); return; }

  const rows = await res.json();
  console.log(`[hevyCron] syncing ${rows.length} user(s)`);

  for (const row of rows) {
    try {
      await syncOneUserHevyData(env, row.user_id, row.hevy_api_key);
    } catch (e) {
      console.error(`[hevyCron] user ${row.user_id} failed:`, e.message);
    }
  }
}

async function syncOneUserHevyData(env, userId, hevyApiKey) {
  const workouts     = await fetchHevyWorkouts(hevyApiKey);
  const measurements = await fetchHevyBodyMeasurementsRaw(hevyApiKey);

  // Only these 4 columns are sent, so this never touches protocols, goals,
  // bloodwork, or any other field on the user's row (PostgREST upserts only
  // set columns present in the payload).
  const res = await fetch(`${SUPABASE_URL}/rest/v1/user_settings?on_conflict=user_id`, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        env.SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      'Prefer':        'resolution=merge-duplicates',
    },
    body: JSON.stringify([{
      user_id:                     userId,
      hevy_workouts_cache:         workouts,
      hevy_measurements_raw_cache: measurements,
      hevy_cron_synced_at:         new Date().toISOString(),
    }]),
  });
  if (!res.ok) throw new Error(`upsert failed: ${res.status} ${await res.text()}`);
}

async function fetchHevyWorkouts(apiKey) {
  let allWorkouts = [];
  let page = 1;
  while (allWorkouts.length < 50) {
    const res = await fetch(`${HEVY_BASE}/workouts?page=${page}&pageSize=10`, {
      headers: { 'api-key': apiKey, 'Content-Type': 'application/json' }
    });
    if (!res.ok) throw new Error(`Hevy workouts API error ${res.status}`);
    const data  = await res.json();
    const batch = data.workouts || [];
    allWorkouts = allWorkouts.concat(batch);
    if (batch.length < 10 || page >= (data.page_count || 1)) break;
    page++;
  }
  return allWorkouts;
}

async function fetchHevyBodyMeasurementsRaw(apiKey) {
  let allEntries = [];
  let page = 1;
  let pageCount = 1;
  do {
    const res = await fetch(`${HEVY_BASE}/body_measurements?page=${page}&pageSize=10`, {
      headers: { 'api-key': apiKey }
    });
    if (!res.ok) throw new Error(`Hevy body_measurements API error ${res.status}`);
    const data  = await res.json();
    const batch = data.body_measurements || [];
    allEntries  = allEntries.concat(batch);
    pageCount   = data.page_count || 1;
    page++;
  } while (page <= pageCount);
  return allEntries;
}

```

- [ ] **Step 4: Verify syntax**

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
node --check worker.js
```

Expected: no output (exit code 0 — valid JS syntax).

- [ ] **Step 5: Manual local test with a real Hevy API key**

This requires a real Hevy Pro API key and the production `SUPABASE_SERVICE_KEY` value (get it from wherever it was originally stored — `wrangler secret` values can't be read back, only set).

Create `.dev.vars` (already gitignored, never commit it):

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
cat > .dev.vars << 'EOF'
SUPABASE_SERVICE_KEY=paste-your-real-service-role-key-here
EOF
```

Run the dev server with scheduled-event testing enabled:

```bash
npx wrangler dev --test-scheduled
```

In a second terminal, trigger the cron manually:

```bash
curl "http://localhost:8787/__scheduled?cron=0+9+*+*+*"
```

Watch the first terminal's logs for `[hevyCron] syncing N user(s)` and no `[hevyCron] user ... failed` lines for a user you know has a valid Hevy key set in `user_settings.hevy_api_key`.

Then confirm the write landed, using the anon key (RLS blocks unauthenticated reads of real row contents, so this just confirms the columns exist and are queryable — cross-check the actual values in the Supabase dashboard Table Editor for your test user's row):

```bash
curl -s "https://lnxhksnvcewtpwkaghrh.supabase.co/rest/v1/user_settings?select=hevy_cron_synced_at&limit=1" \
  -H "apikey: sb_publishable__lU8rYLjeTMoAgXANKsKKA_9Xgau8bm"
```

In the Supabase dashboard Table Editor, open `user_settings` for your test user and confirm `hevy_workouts_cache`, `hevy_measurements_raw_cache`, and `hevy_cron_synced_at` are all populated with fresh data.

- [ ] **Step 6: Add a manual pre-deploy checklist item**

Find (`tests/PRE-DEPLOY-CHECKLIST.md`, item 13, the last one):

```markdown
13. **Console check** — confirm no red errors logged during steps 2-12.
```

Replace with:

```markdown
13. **Hevy daily cron sync** (only after touching `worker.js`'s `scheduled()` handler or the Hevy sync functions) — run `npx wrangler dev --test-scheduled`, then `curl "http://localhost:8787/__scheduled?cron=0+9+*+*+*"`; confirm the terminal logs `[hevyCron] syncing N user(s)` with no failures for a test user with a valid Hevy key.
14. **Console check** — confirm no red errors logged during steps 2-13.
```

- [ ] **Step 7: Commit**

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
git add worker.js wrangler.jsonc tests/PRE-DEPLOY-CHECKLIST.md
git commit -m "$(cat <<'EOF'
feat: add daily Hevy background sync via Cloudflare Cron Trigger

Adds a scheduled() handler that runs once a day, reads every user with
a stored Hevy API key via the existing service-role secret, and caches
their raw workouts + body measurements in user_settings. The client's
loadUserData() (see prior commit) picks this up so PR/bodyweight-based
Goals have data without needing to visit the Workouts/Physique tab.
Existing manual Sync button and 2h/6h open-app auto-sync are untouched.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

Remember to rebase against `cloudflare/workers-autoconfig` before pushing (see `CLAUDE.md` deploy workflow) — Cloudflare's bot force-pushes that branch regularly.

---

## Post-implementation: Confirm the schedule went live

Cloudflare's bot auto-deploys from git per the existing branch workflow — no manual `wrangler deploy` needed. After the push lands, confirm the Cron Trigger is registered:

Cloudflare dashboard → Workers & Pages → `hrt-dashboard` → Triggers tab → confirm a Cron Trigger reading `0 9 * * *` is listed and enabled. The first real run will happen at the next 09:00 UTC after deploy; check the Logs tab afterward for `[hevyCron] syncing N user(s)`.
