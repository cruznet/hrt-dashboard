# Hevy Volume Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 4th "Volume" tab to the Workouts page showing a 7d/30d/90d toggle, three KPI cards, a training frequency heatmap, and a stacked bar chart of weekly volume by muscle group.

**Architecture:** All computation runs over the existing `hrt_hevy_workouts` localStorage cache — no new API calls or Supabase tables. Five new functions are inserted into `index.html` immediately after `hevyWorkoutTag()` (line 7957). Two existing functions (`hevyRenderTabs`, `renderWorkoutsPage`) receive one-line additions each.

**Tech Stack:** Vanilla JS, Chart.js 4.4.0 (via existing `makeChart()`), existing CSS variables only.

## Global Constraints

- Single file: all changes go in `index.html` only (except the test file)
- No hardcoded colors — use CSS variables or chart rgba values from the spec
- All date strings via `localDate()` — never `toISOString()`
- `hevyWorkoutVolume()` already converts kg→lbs — do not re-convert
- `makeChart()` destroys the previous chart before re-creating — always use it, never `new Chart()`
- `hevyWorkoutTag()` returns `{ label, color }` or `null` — treat `null` as Other

---

### Task 1: Wire the Volume tab

**Files:**
- Modify: `index.html:7798-7801` (tabs array in `hevyRenderTabs`)
- Modify: `index.html:7985-7986` (tab dispatch in `renderWorkoutsPage`)
- Modify: `index.html:7783` (module-level state — add `_hevyVolRange`)
- Test: `tests/hevy-volume-logic.html` (create)

**Interfaces:**
- Produces: `_hevyVolRange` (number, 7|30|90, default 30), `hevySetVolRange(days)` stub, `renderHevyVolume(workouts)` stub

- [ ] **Step 1: Create browser test file**

Create `tests/hevy-volume-logic.html`:

```html
<!DOCTYPE html>
<html>
<head><title>Hevy Volume Logic Tests</title>
<style>
  body { font-family: monospace; padding: 20px; background:#111; color:#eee; }
  .pass { color: #4ADE80; } .fail { color: #F87171; }
  h2 { color: #F5C518; }
</style>
</head>
<body>
<h2>Hevy Volume Logic Tests</h2>
<div id="results"></div>
<script>
const results = document.getElementById('results');
let passed = 0, failed = 0;

function assert(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  results.innerHTML += `<div class="${ok?'pass':'fail'}">${ok?'✅':'❌'} ${label}${ok?'':' | got: '+JSON.stringify(actual)+' expected: '+JSON.stringify(expected)}</div>`;
  ok ? passed++ : failed++;
}

// ── hevyMuscleTag ────────────────────────────────────────────────────────────
// Paste hevyMuscleTag here for testing
function hevyWorkoutTag(title) {
  const t = (title||'').toLowerCase();
  if (/pull|back|row|deadlift|curl|lat|bicep/i.test(t))  return { label:'Pull',  color:'#38BDF8' };
  if (/push|chest|press|delt|tricep|shoulder/i.test(t))  return { label:'Push',  color:'#F87171' };
  if (/leg|squat|quad|hamstring|glute|calf|calves/i.test(t)) return { label:'Legs', color:'#4ADE80' };
  if (/upper/i.test(t)) return { label:'Upper', color:'#A78BFA' };
  if (/lower/i.test(t)) return { label:'Lower', color:'#FB923C' };
  if (/full|total/i.test(t)) return { label:'Full',  color:'#F5C518' };
  if (/cardio|run|bike|swim/i.test(t)) return { label:'Cardio', color:'#F472B6' };
  return null;
}

function hevyMuscleTag(workout) {
  // PLACEHOLDER — implement in Task 3
  return 'Other';
}

assert('hevyMuscleTag Pull workout → Pull', hevyMuscleTag({title:'Pull Day'}), 'Pull');
assert('hevyMuscleTag Push workout → Push', hevyMuscleTag({title:'Push A'}), 'Push');
assert('hevyMuscleTag Legs workout → Legs', hevyMuscleTag({title:'Leg Day'}), 'Legs');
assert('hevyMuscleTag Upper → Push', hevyMuscleTag({title:'Upper Body'}), 'Push');
assert('hevyMuscleTag Lower → Legs', hevyMuscleTag({title:'Lower Body'}), 'Legs');
assert('hevyMuscleTag Full → Push', hevyMuscleTag({title:'Full Body'}), 'Push');
assert('hevyMuscleTag Cardio → Other', hevyMuscleTag({title:'Cardio Run'}), 'Other');
assert('hevyMuscleTag null tag → Other', hevyMuscleTag({title:'Random'}), 'Other');

results.innerHTML += `<h2>${passed} passed, ${failed} failed</h2>`;
</script>
</body>
</html>
```

- [ ] **Step 2: Open test file in browser and verify all 8 tests FAIL**

```bash
open tests/hevy-volume-logic.html
```

Expected: 8 red ❌ lines (hevyMuscleTag returns 'Other' for everything)

- [ ] **Step 3: Add `_hevyVolRange` state variable**

In `index.html`, find line 7783:
```js
let _hevyTab     = 'recent';
```

Add on the line immediately after:
```js
let _hevyVolRange = 30;
```

- [ ] **Step 4: Add Volume tab to `hevyRenderTabs`**

Find (lines 7798–7801):
```js
  const tabs = [
    { key: 'recent', label: 'Recent' },
    { key: 'prs',    label: 'PRs' },
    { key: 'e1rm',   label: 'E1RM Trends' },
  ];
```

Replace with:
```js
  const tabs = [
    { key: 'recent', label: 'Recent' },
    { key: 'prs',    label: 'PRs' },
    { key: 'e1rm',   label: 'E1RM Trends' },
    { key: 'volume', label: 'Volume' },
  ];
```

- [ ] **Step 5: Add Volume dispatch in `renderWorkoutsPage`**

Find (lines 7985–7986):
```js
  if (_hevyTab === 'prs')  { renderHevyPRs(workouts);   return; }
  if (_hevyTab === 'e1rm') { renderHevyE1RM(workouts);  return; }
```

Replace with:
```js
  if (_hevyTab === 'prs')    { renderHevyPRs(workouts);    return; }
  if (_hevyTab === 'e1rm')   { renderHevyE1RM(workouts);   return; }
  if (_hevyTab === 'volume') { renderHevyVolume(workouts); return; }
```

- [ ] **Step 6: Add stub functions after `hevyWorkoutTag` (line 7957)**

Insert after the closing `}` of `hevyWorkoutTag`:

```js
let _hevyVolRange = 30; // Remove this line — already added in Step 3

function hevySetVolRange(days) {
  _hevyVolRange = days;
  document.querySelectorAll('.hevy-vol-pill').forEach(b => {
    b.style.borderColor = b.dataset.days == days ? 'var(--primary-bright)' : 'var(--border)';
    b.style.color       = b.dataset.days == days ? 'var(--primary-bright)' : 'var(--text-muted)';
    b.style.background  = b.dataset.days == days ? 'rgba(34,211,238,0.12)' : 'transparent';
  });
  renderHevyVolume(hevyCache());
}

function renderHevyVolume(workouts) {
  const content = document.getElementById('hevy-content');
  if (!content) return;
  content.innerHTML = '<div style="color:var(--text-muted);font-size:13px;padding:24px 0;">Loading volume...</div>';
}
```

**Note:** Do NOT add `let _hevyVolRange = 30;` here — it was already added in Step 3. Only add the two functions.

- [ ] **Step 7: Verify Volume tab appears in browser**

```bash
python3 server.py &
```

Open `http://localhost:3000`, navigate to Workouts, verify a "Volume" tab button appears. Click it — should show "Loading volume..." text.

- [ ] **Step 8: Commit**

```bash
git add index.html tests/hevy-volume-logic.html
git commit -m "feat: wire Volume tab to Workouts page"
```

---

### Task 2: KPI cards + range toggle

**Files:**
- Modify: `index.html` — replace `renderHevyVolume` stub, add `hevyVolKpis`

**Interfaces:**
- Consumes: `_hevyVolRange` (number), `hevyParseMs(t)` → ms, `hevyWorkoutVolume(w)` → lbs (number)
- Produces: `hevyVolKpis(workouts, cutoffMs)` → `{ totalVol: number, sessions: number, avgSession: number }`; `renderHevyVolume(workouts)` renders toggle + KPI row

- [ ] **Step 1: Add `hevyVolKpis` test to `tests/hevy-volume-logic.html`**

Add before the final `results.innerHTML` summary line:

```html
<script>
// ── hevyVolKpis ──────────────────────────────────────────────────────────────
function hevyParseMs(t) {
  if (!t) return 0;
  if (typeof t === 'number') return t * 1000;
  const ms = new Date(t).getTime();
  return isNaN(ms) ? 0 : ms;
}
function hevyWorkoutVolume(w) {
  return (w.exercises||[]).reduce((total, e) =>
    total + (e.sets||[]).reduce((s, set) =>
      s + (set.weight_kg > 0 && set.reps > 0 ? set.weight_kg * 2.205 * set.reps : 0), 0), 0);
}
function hevyVolKpis(workouts, cutoffMs) {
  // PLACEHOLDER
  return { totalVol: 0, sessions: 0, avgSession: 0 };
}

const now = Date.now();
const w1 = { start_time: now - 1 * 86400000, exercises: [{ sets: [{ weight_kg: 100, reps: 5 }] }] };
const w2 = { start_time: now - 3 * 86400000, exercises: [{ sets: [{ weight_kg: 50,  reps: 10 }] }] };
const wOld = { start_time: now - 40 * 86400000, exercises: [{ sets: [{ weight_kg: 100, reps: 5 }] }] };
const cutoff30 = now - 30 * 86400000;

const kpis = hevyVolKpis([w1, w2, wOld], cutoff30);
assert('hevyVolKpis sessions counts only within window', kpis.sessions, 2);
assert('hevyVolKpis totalVol sums lbs in window', Math.round(kpis.totalVol), Math.round(100*2.205*5 + 50*2.205*10));
assert('hevyVolKpis avgSession = totalVol/sessions', Math.round(kpis.avgSession), Math.round(kpis.totalVol / 2));
assert('hevyVolKpis empty window returns zeros', hevyVolKpis([], cutoff30), { totalVol: 0, sessions: 0, avgSession: 0 });
</script>
```

- [ ] **Step 2: Open test file — verify 4 new tests FAIL**

Open `tests/hevy-volume-logic.html` in browser. Expected: 4 new ❌ for hevyVolKpis.

- [ ] **Step 3: Implement `hevyVolKpis`**

Find the `hevySetVolRange` function added in Task 1 and insert `hevyVolKpis` immediately before it:

```js
function hevyVolKpis(workouts, cutoffMs) {
  const inWindow = workouts.filter(w => hevyParseMs(w.start_time) >= cutoffMs);
  const totalVol = inWindow.reduce((s, w) => s + hevyWorkoutVolume(w), 0);
  const sessions = inWindow.length;
  return { totalVol, sessions, avgSession: sessions ? totalVol / sessions : 0 };
}
```

- [ ] **Step 4: Verify 4 hevyVolKpis tests PASS**

Reload `tests/hevy-volume-logic.html`. Expected: 4 green ✅ for hevyVolKpis.

- [ ] **Step 5: Replace `renderHevyVolume` stub with full toggle + KPI render**

Find and replace the stub `renderHevyVolume` function:

```js
function renderHevyVolume(workouts) {
  const content = document.getElementById('hevy-content');
  if (!content) return;

  const cutoffMs = Date.now() - _hevyVolRange * 86400000;
  const { totalVol, sessions, avgSession } = hevyVolKpis(workouts, cutoffMs);

  const pill = (days) => `<button class="hevy-vol-pill" data-days="${days}" onclick="hevySetVolRange(${days})"
    style="padding:5px 14px;border-radius:99px;border:1.5px solid ${_hevyVolRange===days?'var(--primary-bright)':'var(--border)'};
    background:${_hevyVolRange===days?'rgba(34,211,238,0.12)':'transparent'};
    color:${_hevyVolRange===days?'var(--primary-bright)':'var(--text-muted)'};
    font-size:13px;font-weight:600;cursor:pointer;">${days}d</button>`;

  const kpiCard = (label, value, unit, color) => `<div class="card" style="padding:12px 14px;">
    <div style="font-size:12px;color:var(--text-label);text-transform:uppercase;letter-spacing:.06em;font-weight:600;margin-bottom:6px;">${label}</div>
    <div style="font-size:22px;font-family:var(--font-data);font-weight:600;color:${color};">${value}</div>
    <div style="font-size:12px;color:var(--text-label);margin-top:1px;">${unit}</div>
  </div>`;

  content.innerHTML = `
    <div style="display:flex;gap:4px;margin-bottom:16px;">
      ${pill(7)}${pill(30)}${pill(90)}
    </div>
    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:16px;">
      ${kpiCard('Total Volume', Math.round(totalVol).toLocaleString(), 'lbs', 'var(--primary-bright)')}
      ${kpiCard('Sessions', sessions, 'workouts', 'var(--teal)')}
      ${kpiCard('Avg Session', sessions ? Math.round(avgSession).toLocaleString() : '—', 'lbs', 'var(--text-primary)')}
    </div>
    <div id="hevy-vol-heatmap" style="margin-bottom:16px;"></div>
    <div style="margin-bottom:16px;"><canvas id="hevy-chart-vol-muscle"></canvas></div>
  `;
}
```

- [ ] **Step 6: Verify in browser**

Navigate to Workouts → Volume tab. Confirm:
- 3 pills (7d / 30d / 90d), 30d active by default
- 3 KPI cards with correct values
- Clicking 7d updates the active pill and recalculates KPIs
- Heatmap and chart areas are empty (placeholders for next tasks)

- [ ] **Step 7: Commit**

```bash
git add index.html tests/hevy-volume-logic.html
git commit -m "feat: Volume tab KPI cards and range toggle"
```

---

### Task 3: Frequency heatmap

**Files:**
- Modify: `index.html` — add `hevyMuscleTag`, `hevyFreqHeatmap`; update `renderHevyVolume` to call `hevyFreqHeatmap`

**Interfaces:**
- Consumes: `workouts[]`, `_hevyVolRange`, `hevyParseMs`, `hevyWorkoutVolume`, `hevyWorkoutTag`
- Produces: `hevyMuscleTag(workout)` → `'Push'|'Pull'|'Legs'|'Other'`; `hevyFreqHeatmap(workouts, days)` → HTML string

- [ ] **Step 1: Implement `hevyMuscleTag` in test file to make existing tests pass**

In `tests/hevy-volume-logic.html`, replace the placeholder `hevyMuscleTag`:

```js
function hevyMuscleTag(workout) {
  const tag = hevyWorkoutTag(workout.title);
  if (!tag) return 'Other';
  const { label } = tag;
  if (label === 'Pull') return 'Pull';
  if (label === 'Push' || label === 'Upper' || label === 'Full') return 'Push';
  if (label === 'Legs' || label === 'Lower') return 'Legs';
  return 'Other';
}
```

- [ ] **Step 2: Verify all 8 hevyMuscleTag tests PASS**

Reload `tests/hevy-volume-logic.html`. Expected: 8 green ✅ for hevyMuscleTag.

- [ ] **Step 3: Add `hevyFreqHeatmap` test**

Add to test file before the summary line:

```js
// ── hevyFreqHeatmap ───────────────────────────────────────────────────────────
function hevyFreqHeatmap(workouts, days) { return ''; } // placeholder

const todayMs = new Date().setHours(0,0,0,0);
const wToday  = { start_time: todayMs, exercises: [{ sets:[{ weight_kg:100, reps:5 }] }] };
const wYest   = { start_time: todayMs - 86400000, exercises: [{ sets:[{ weight_kg:100, reps:5 }] }] };
const html7   = hevyFreqHeatmap([wToday, wYest], 7);
assert('hevyFreqHeatmap returns non-empty string', html7.length > 0, true);
assert('hevyFreqHeatmap contains 7 cells', (html7.match(/hevy-hm-cell/g)||[]).length, 7);
assert('hevyFreqHeatmap has teal cell for workout day', html7.includes('rgba(34,211,238'), true);
```

- [ ] **Step 4: Verify 3 hevyFreqHeatmap tests FAIL**

Reload test file. Expected: 3 ❌ for hevyFreqHeatmap (empty string returned).

- [ ] **Step 5: Implement `hevyMuscleTag` and `hevyFreqHeatmap` in `index.html`**

Insert both functions after `hevyVolKpis` (before `hevySetVolRange`):

```js
function hevyMuscleTag(workout) {
  const tag = hevyWorkoutTag(workout.title);
  if (!tag) return 'Other';
  const { label } = tag;
  if (label === 'Pull') return 'Pull';
  if (label === 'Push' || label === 'Upper' || label === 'Full') return 'Push';
  if (label === 'Legs' || label === 'Lower') return 'Legs';
  return 'Other';
}

function hevyFreqHeatmap(workouts, days) {
  const now      = Date.now();
  const todayMs  = new Date().setHours(0, 0, 0, 0);
  const cutoffMs = todayMs - (days - 1) * 86400000;

  // Build a map of date → total volume for fast lookup
  const volByDate = {};
  workouts.forEach(w => {
    const ms = hevyParseMs(w.start_time);
    if (ms < cutoffMs) return;
    const d = localDate(new Date(ms));
    volByDate[d] = (volByDate[d] || 0) + hevyWorkoutVolume(w);
  });

  // Median session volume (for brightness scaling)
  const vols = Object.values(volByDate).filter(v => v > 0);
  vols.sort((a, b) => a - b);
  const median = vols.length ? vols[Math.floor(vols.length / 2)] : 1;

  const cells = [];
  for (let i = days - 1; i >= 0; i--) {
    const ms  = todayMs - i * 86400000;
    const d   = localDate(new Date(ms));
    const vol = volByDate[d] || 0;
    let bg;
    if (!vol) {
      bg = 'var(--bg-card-hover)';
    } else {
      const ratio = Math.min(vol / median, 2); // cap at 2× median
      const alpha = ratio <= 1 ? 0.35 + 0.30 * ratio : 0.65 + 0.35 * (ratio - 1);
      bg = `rgba(34,211,238,${Math.min(alpha, 1).toFixed(2)})`;
    }
    const title = vol
      ? `${d} · ${workouts.find(w => localDate(new Date(hevyParseMs(w.start_time))) === d)?.title || 'Workout'} · ${Math.round(vol).toLocaleString()} lbs`
      : d;
    cells.push(`<div class="hevy-hm-cell" title="${escHtml(title)}" style="width:12px;height:12px;border-radius:2px;background:${bg};flex-shrink:0;"></div>`);
  }

  return `<div style="display:flex;flex-wrap:wrap;gap:3px;">${cells.join('')}</div>`;
}
```

- [ ] **Step 6: Wire heatmap into `renderHevyVolume`**

In the `renderHevyVolume` function, find:
```js
    <div id="hevy-vol-heatmap" style="margin-bottom:16px;"></div>
```

Replace with:
```js
    <div style="margin-bottom:4px;font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:var(--text-muted);">Training Frequency</div>
    <div style="margin-bottom:16px;">${hevyFreqHeatmap(workouts, _hevyVolRange)}</div>
```

- [ ] **Step 7: Update test file to use real implementation**

In `tests/hevy-volume-logic.html`, replace the placeholder `hevyFreqHeatmap` function with the real one (copy from index.html). Also add `localDate` and `escHtml` stubs:

```js
function localDate(d) { return d.toLocaleDateString('en-CA'); } // YYYY-MM-DD
function escHtml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
```

- [ ] **Step 8: Verify all 3 hevyFreqHeatmap tests PASS**

Reload `tests/hevy-volume-logic.html`. Expected: 3 green ✅.

- [ ] **Step 9: Verify heatmap in browser**

Navigate to Workouts → Volume. Confirm:
- A row of colored cells appears below the KPI cards
- Rest days are dark, workout days are teal (brighter = heavier session)
- Hovering a cell shows the tooltip with date + title + volume

- [ ] **Step 10: Commit**

```bash
git add index.html tests/hevy-volume-logic.html
git commit -m "feat: Volume tab frequency heatmap"
```

---

### Task 4: Weekly volume stacked bar chart

**Files:**
- Modify: `index.html` — add `hevyVolByWeek`; update `renderHevyVolume` to call `makeChart`

**Interfaces:**
- Consumes: `workouts[]`, `cutoffMs`, `hevyMuscleTag`, `hevyWorkoutVolume`, `hevyParseMs`, `makeChart(id, type, labels, datasets, opts)`
- Produces: `hevyVolByWeek(workouts, cutoffMs)` → `{ weeks: string[], push: number[], pull: number[], legs: number[], other: number[] }`

- [ ] **Step 1: Add `hevyVolByWeek` test to test file**

Add before the summary line:

```js
// ── hevyVolByWeek ────────────────────────────────────────────────────────────
function hevyVolByWeek(workouts, cutoffMs) { return { weeks:[], push:[], pull:[], legs:[], other:[] }; }

// Monday of week containing a date
function weekKey(ms) {
  const d = new Date(ms);
  const day = d.getDay(); // 0=Sun
  const mon = new Date(ms - ((day === 0 ? 6 : day - 1) * 86400000));
  return mon.toLocaleDateString('en-CA').slice(0, 10);
}

const wPush = { start_time: Date.now() - 2*86400000, title:'Push A', exercises:[{sets:[{weight_kg:100,reps:5}]}] };
const wPull = { start_time: Date.now() - 3*86400000, title:'Pull B', exercises:[{sets:[{weight_kg:80, reps:8}]}] };
const wLegs = { start_time: Date.now() - 4*86400000, title:'Leg Day', exercises:[{sets:[{weight_kg:120,reps:6}]}] };
const cutoff = Date.now() - 30*86400000;
const vbw = hevyVolByWeek([wPush, wPull, wLegs], cutoff);

assert('hevyVolByWeek returns weeks array', Array.isArray(vbw.weeks), true);
assert('hevyVolByWeek has matching array lengths', vbw.weeks.length === vbw.push.length && vbw.push.length === vbw.pull.length, true);
assert('hevyVolByWeek push vol > 0', vbw.push.some(v => v > 0), true);
assert('hevyVolByWeek pull vol > 0', vbw.pull.some(v => v > 0), true);
assert('hevyVolByWeek legs vol > 0', vbw.legs.some(v => v > 0), true);
```

- [ ] **Step 2: Verify 5 hevyVolByWeek tests FAIL**

Reload test file. Expected: 5 ❌.

- [ ] **Step 3: Implement `hevyVolByWeek` in `index.html`**

Insert after `hevyFreqHeatmap` (before `hevySetVolRange`):

```js
function hevyVolByWeek(workouts, cutoffMs) {
  const byWeek = {}; // weekKey → { push, pull, legs, other }

  workouts.forEach(w => {
    const ms = hevyParseMs(w.start_time);
    if (ms < cutoffMs) return;
    const d   = new Date(ms);
    const day = d.getDay();
    const monMs = ms - (day === 0 ? 6 : day - 1) * 86400000;
    const wk  = localDate(new Date(new Date(monMs).setHours(0,0,0,0)));
    if (!byWeek[wk]) byWeek[wk] = { push:0, pull:0, legs:0, other:0 };
    const vol  = hevyWorkoutVolume(w);
    const grp  = hevyMuscleTag(w).toLowerCase();
    byWeek[wk][grp] = (byWeek[wk][grp] || 0) + vol;
  });

  const weeks = Object.keys(byWeek).sort();
  return {
    weeks: weeks.map(w => {
      const d = new Date(w + 'T00:00:00');
      return d.toLocaleDateString('en-US', { month:'short', day:'numeric' });
    }),
    push:  weeks.map(w => Math.round(byWeek[w].push)),
    pull:  weeks.map(w => Math.round(byWeek[w].pull)),
    legs:  weeks.map(w => Math.round(byWeek[w].legs)),
    other: weeks.map(w => Math.round(byWeek[w].other)),
  };
}
```

- [ ] **Step 4: Update test file with real `hevyVolByWeek` and add `hevyMuscleTag` dependency**

In `tests/hevy-volume-logic.html`, replace the placeholder `hevyVolByWeek` with the real implementation (copy from index.html). Ensure `hevyMuscleTag`, `hevyWorkoutTag`, `hevyParseMs`, `hevyWorkoutVolume`, and `localDate` are all defined above it in the test file.

- [ ] **Step 5: Verify all 5 hevyVolByWeek tests PASS**

Reload test file. Expected: 5 green ✅. Total across all tasks: 20 green ✅.

- [ ] **Step 6: Wire chart into `renderHevyVolume`**

In `renderHevyVolume`, after the `content.innerHTML = ...` assignment, add:

```js
  // Render stacked bar chart
  const { weeks, push, pull, legs, other } = hevyVolByWeek(workouts, cutoffMs);
  if (weeks.length) {
    const lm = document.documentElement.dataset.theme === 'light';
    makeChart('hevy-chart-vol-muscle', 'bar', weeks, [
      { label: 'Push', data: push,  backgroundColor: 'rgba(245,197,24,0.85)' },
      { label: 'Pull', data: pull,  backgroundColor: 'rgba(34,211,238,0.85)' },
      { label: 'Legs', data: legs,  backgroundColor: 'rgba(192,132,252,0.85)' },
      { label: 'Other',data: other, backgroundColor: 'rgba(144,144,152,0.5)'  },
    ], {
      plugins: { legend: { labels: { color: lm ? '#1a1a2e' : '#E8E8ED', font:{ size:12 } } } },
      scales: {
        x: { stacked: true, ticks:{ color: lm?'#374151':'#909098' }, grid:{ color:'rgba(255,255,255,0.05)' } },
        y: { stacked: true, ticks:{ color: lm?'#374151':'#909098' }, grid:{ color:'rgba(255,255,255,0.05)' } },
      },
    });
  }
```

- [ ] **Step 7: Verify full Volume tab in browser**

Navigate to Workouts → Volume. Confirm:
- Toggle, KPI cards, heatmap all still present
- Stacked bar chart renders below heatmap with 4 colored segments
- Switching 7d / 30d / 90d updates KPIs, heatmap, and chart
- Light mode toggle (Settings) doesn't break chart colors

- [ ] **Step 8: Run smoke test**

```bash
cd ~/.claude/skills/playwright-skill
node run.js /path/to/hrt-dashboard/tests/smoke-test.js
```

Expected: exit 0.

- [ ] **Step 9: Commit and push**

```bash
git add index.html tests/hevy-volume-logic.html
git commit -m "feat: Volume tab stacked bar chart by muscle group"
git pull origin cloudflare/workers-autoconfig --rebase
git push origin main
```
