# Mood & Energy Trend Charts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Mood and Energy trend charts to the dashboard, cycle-window-aligned with a shared `getCycleChartData` helper that also updates the existing weight chart.

**Architecture:** One pure helper function (`getCycleChartData`) handles data slicing and label generation for all three charts. A new render function (`renderMoodEnergyCharts`) populates the two new charts and is called from both the localStorage and Supabase render paths. HTML is added before JS so DOM targets exist when the render functions run.

**Tech Stack:** Vanilla JS, Chart.js (already loaded), localStorage (`hrt_vitals_log`, `hrt_active_protocol_data`), no build system.

## Global Constraints

- All changes confined to `index-v2.html` and `tests/protocol-logic.html`
- No new localStorage keys
- No new CSS files — use `var(--purple)`, `var(--amber)`, existing classes
- New canvas IDs: `chart-mood`, `chart-energy`; new empty-state IDs: `chart-mood-empty`, `chart-energy-empty`
- `getCycleChartData(logs, fieldKey, protocol)` is a pure function — no localStorage access, no DOM access
- Date parsing always uses local-time construction: `const [y,m,d] = s.split('-').map(Number); new Date(y,m-1,d)` — never `new Date(dateString)` for date-only strings
- `lsGet(key, fallback)` is the existing localStorage helper — parses JSON, returns fallback on missing/corrupt

---

## File Map

| File | What changes |
|---|---|
| `index-v2.html` (JS ~line 1700) | Add `getCycleChartData` before `renderVitalsToCards` |
| `index-v2.html` (JS ~line 1758) | Replace weight chart inline slice with `getCycleChartData` call |
| `index-v2.html` (JS ~line 1771) | Add `renderMoodEnergyCharts()` call at end of `renderVitalsToCards` |
| `index-v2.html` (JS ~line 1875) | Add `renderMoodEnergyCharts()` call at end of `renderRealCharts` |
| `index-v2.html` (JS ~line 1876) | Add `renderMoodEnergyCharts` function definition |
| `index-v2.html` (HTML ~line 633) | Add new `grid-2` row with Mood and Energy chart cards after weight chart row |
| `tests/protocol-logic.html` | Add `getCycleChartData` test section before summary block |

---

### Task 1: `getCycleChartData` Pure Function + Tests

**Files:**
- Modify: `index-v2.html` — add `getCycleChartData` function immediately before `function renderVitalsToCards()`
- Modify: `tests/protocol-logic.html` — add test section before the `// ── summary ──` block

**Interfaces:**
- Produces: `getCycleChartData(logs, fieldKey, protocol) → { entries, labels }`
  - `logs`: `hrt_vitals_log` array, newest-first (each entry has `date: 'YYYY-MM-DD'` and field values as strings)
  - `fieldKey`: `'weight'`, `'mood'`, or `'energy'`
  - `protocol`: parsed `hrt_active_protocol_data` object or `null`
  - `entries`: array of log objects, oldest-first, filtered to field present and `> 0`
  - `labels`: parallel string array — `"Wk N"` when cycle active, `"Mon DD"` otherwise

- [ ] **Step 1: Add test copy of `getCycleChartData` and assertions to `tests/protocol-logic.html`**

Find the `// ── summary ──` script block near the bottom of `tests/protocol-logic.html`. Insert a new `<script>` block immediately before it:

```html
<script>
// ── getCycleChartData ──
function getCycleChartData(logs, fieldKey, protocol) {
  const filtered = logs.filter(l => l[fieldKey] && parseFloat(l[fieldKey]) > 0);
  const startDate = protocol && (protocol.startDate || protocol.saved_at);
  const cycleLengthWeeks = protocol && (protocol.cycleLengthWeeks || parseInt(protocol.weeks) || 0);
  const usingCycle = !!(startDate && cycleLengthWeeks > 0);
  let entries = usingCycle
    ? filtered.filter(l => l.date >= startDate)
    : filtered.slice(0, 30);
  entries = [...entries].reverse(); // oldest-first
  let labels;
  if (usingCycle) {
    const [sy, sm, sd] = startDate.split('-').map(Number);
    const startMs = new Date(sy, sm - 1, sd).getTime();
    labels = entries.map(l => {
      const [ly, lm, ld] = l.date.split('-').map(Number);
      const daysSinceStart = Math.round((new Date(ly, lm - 1, ld).getTime() - startMs) / 86400000);
      return `Wk ${Math.ceil((daysSinceStart + 1) / 7)}`;
    });
  } else {
    labels = entries.map(l => {
      const [y, m, d] = l.date.split('-').map(Number);
      return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    });
  }
  return { entries, labels };
}

section('getCycleChartData');
(function() {
  const proto = { startDate: '2026-06-01', cycleLengthWeeks: 4 };
  // logs newest-first, as stored in hrt_vitals_log
  const logs = [
    { date: '2026-06-21', weight: '195', mood: '8' },  // day 20 → Wk 3
    { date: '2026-06-14', weight: '196', mood: '7' },  // day 13 → Wk 2
    { date: '2026-06-07', weight: '197', mood: '6' },  // day 6  → Wk 1
    { date: '2026-06-01', weight: '198', mood: '5' },  // day 0  → Wk 1
  ];

  const { entries: e1, labels: l1 } = getCycleChartData(logs, 'weight', proto);
  assert('cycle: returns 4 entries', e1.length, 4);
  assert('cycle: oldest entry first', e1[0].date, '2026-06-01');
  assert('cycle: newest entry last', e1[3].date, '2026-06-21');
  assert('cycle: day 0 → Wk 1', l1[0], 'Wk 1');
  assert('cycle: day 6 → Wk 1', l1[1], 'Wk 1');
  assert('cycle: day 13 → Wk 2', l1[2], 'Wk 2');
  assert('cycle: day 20 → Wk 3', l1[3], 'Wk 3');

  const { entries: e2, labels: l2 } = getCycleChartData(logs, 'weight', null);
  assert('no protocol: returns entries oldest-first', e2[0].date, '2026-06-01');
  assert('no protocol: labels are not Wk format', l2[0].includes('Wk'), false);

  const mixedLogs = [{ date: '2026-06-21', mood: '8' }, { date: '2026-06-14', weight: '196' }];
  const { entries: e3 } = getCycleChartData(mixedLogs, 'weight', null);
  assert('filters out entries missing fieldKey', e3.length, 1);

  const { entries: e4, labels: l4 } = getCycleChartData([], 'mood', proto);
  assert('empty logs → empty entries', e4.length, 0);
  assert('empty logs → empty labels', l4.length, 0);

  const withOld = [{ date: '2026-06-21', weight: '195' }, { date: '2026-05-31', weight: '200' }];
  const { entries: e5 } = getCycleChartData(withOld, 'weight', proto);
  assert('cycle: excludes entries before startDate', e5.length, 1);

  const onStart = [{ date: '2026-06-01', weight: '198' }];
  assert('cycle: includes entry on startDate', getCycleChartData(onStart, 'weight', proto).entries.length, 1);
})();
</script>
```

- [ ] **Step 2: Open `tests/protocol-logic.html` in a browser — confirm the new section appears and all 13 assertions pass**

Expected: Green "✓" for all 13 new assertions. The `getCycleChartData` section appears before the pass/fail summary.

- [ ] **Step 3: Add `getCycleChartData` to `index-v2.html`**

Find `function renderVitalsToCards()` (search for that exact string). Add the following function immediately before it — the function body must be byte-for-byte identical to the test copy above:

```js
function getCycleChartData(logs, fieldKey, protocol) {
  const filtered = logs.filter(l => l[fieldKey] && parseFloat(l[fieldKey]) > 0);
  const startDate = protocol && (protocol.startDate || protocol.saved_at);
  const cycleLengthWeeks = protocol && (protocol.cycleLengthWeeks || parseInt(protocol.weeks) || 0);
  const usingCycle = !!(startDate && cycleLengthWeeks > 0);
  let entries = usingCycle
    ? filtered.filter(l => l.date >= startDate)
    : filtered.slice(0, 30);
  entries = [...entries].reverse(); // oldest-first
  let labels;
  if (usingCycle) {
    const [sy, sm, sd] = startDate.split('-').map(Number);
    const startMs = new Date(sy, sm - 1, sd).getTime();
    labels = entries.map(l => {
      const [ly, lm, ld] = l.date.split('-').map(Number);
      const daysSinceStart = Math.round((new Date(ly, lm - 1, ld).getTime() - startMs) / 86400000);
      return `Wk ${Math.ceil((daysSinceStart + 1) / 7)}`;
    });
  } else {
    labels = entries.map(l => {
      const [y, m, d] = l.date.split('-').map(Number);
      return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    });
  }
  return { entries, labels };
}
```

- [ ] **Step 4: Verify by reading back the inserted function in `index-v2.html`**

Confirm it appears immediately before `function renderVitalsToCards()` and matches the test copy exactly.

- [ ] **Step 5: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat: add getCycleChartData pure function + 13 tests"
```

---

### Task 2: Update Weight Chart to Use `getCycleChartData`

**Files:**
- Modify: `index-v2.html` — update `renderVitalsToCards` (add protocol read, replace weight chart inline slice)

**Interfaces:**
- Consumes: `getCycleChartData(logs, fieldKey, protocol)` from Task 1
- Preserves: `makeChart('chart-weight', ...)` call, `showChart('chart-weight')` call, all existing dataset options

- [ ] **Step 1: Add protocol read to `renderVitalsToCards`**

Find `function renderVitalsToCards()`. The first line currently reads `const logs = lsGet('hrt_vitals_log', []);`. Add the protocol read on the very next line:

```js
// FIND:
function renderVitalsToCards() {
  const logs = lsGet('hrt_vitals_log', []);

// REPLACE WITH:
function renderVitalsToCards() {
  const logs = lsGet('hrt_vitals_log', []);
  const protocol = lsGet('hrt_active_protocol_data', null);
```

- [ ] **Step 2: Replace the weight chart inline slice with `getCycleChartData`**

Find and replace the weight chart block inside `renderVitalsToCards` (currently around line 1758):

```js
// FIND (exact block):
  // ── Weight chart from local data ──
  if (weightLogs.length >= 2) {
    const chartLogs = weightLogs.slice(0, 30).reverse(); // oldest → newest, max 30
    const labels = chartLogs.map(l => {
      const d = new Date(l.date + 'T00:00:00');
      return d.toLocaleDateString('en-US', { month:'short', day:'numeric' });
    });
    const data = chartLogs.map(l => parseFloat(l.weight).toFixed(1));
    showChart('chart-weight');
    makeChart('chart-weight', 'line', labels,
      [{ label:'Weight (lbs)', data, borderColor:'#F59E0B', backgroundColor:'rgba(245,158,11,0.08)',
         tension:0.4, fill:true, pointBackgroundColor:'#FCD34D', pointRadius:3 }]);
  }

// REPLACE WITH:
  // ── Weight chart from local data ──
  const { entries: wEntries, labels: wLabels } = getCycleChartData(logs, 'weight', protocol);
  if (wEntries.length >= 2) {
    const data = wEntries.map(l => parseFloat(l.weight).toFixed(1));
    showChart('chart-weight');
    makeChart('chart-weight', 'line', wLabels,
      [{ label:'Weight (lbs)', data, borderColor:'#F59E0B', backgroundColor:'rgba(245,158,11,0.08)',
         tension:0.4, fill:true, pointBackgroundColor:'#FCD34D', pointRadius:3 }]);
  }
```

- [ ] **Step 3: Verify in browser — weight chart still renders correctly**

Open `index-v2.html` with existing weight log data. Confirm:
- Weight chart renders as before when no active protocol (date labels, up to 30 entries)
- If an active protocol with `startDate` exists, x-axis shows `"Wk N"` labels
- If fewer than 2 weight entries, chart stays hidden (empty state shown)
- No console errors

- [ ] **Step 4: Commit**

```bash
git add index-v2.html
git commit -m "feat: update weight chart to use getCycleChartData cycle window"
```

---

### Task 3: Dashboard HTML — Mood & Energy Chart Cards

**Files:**
- Modify: `index-v2.html` — add new `grid-2` row after the weight chart row in `page-dashboard`

**Interfaces:**
- Produces: `id="chart-mood"`, `id="chart-mood-empty"`, `id="chart-energy"`, `id="chart-energy-empty"` — consumed by Task 4

This is a pure HTML change — no JS.

- [ ] **Step 1: Add the Mood & Energy chart row to the dashboard**

Find the closing `</div>` of the weight chart row — the exact block is (around line 621):

```html
      <!-- Charts row -->
      <div class="grid-2" style="margin-bottom:14px;">
        <div class="card">
          <div class="card-title">Weight &amp; Body Comp</div>
          <div class="chart-wrap" style="height:180px;position:relative;">
            <canvas id="chart-weight" style="display:none;"></canvas>
            <div id="chart-weight-empty" style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:6px;text-align:center;">
              <i class="ti ti-weight" style="font-size:28px;color:var(--text-muted);opacity:0.4;"></i>
              <div style="font-size:12px;color:var(--text-muted);">No weight data yet</div>
              <div style="font-size:11px;color:var(--text-muted);opacity:0.7;">Log your weight via <a href="#" onclick="nav('log');return false;" style="color:var(--primary-bright);">Log Entry</a> to track body composition</div>
            </div>
          </div>
        </div>
      </div>
```

Replace with:

```html
      <!-- Charts row -->
      <div class="grid-2" style="margin-bottom:14px;">
        <div class="card">
          <div class="card-title">Weight &amp; Body Comp</div>
          <div class="chart-wrap" style="height:180px;position:relative;">
            <canvas id="chart-weight" style="display:none;"></canvas>
            <div id="chart-weight-empty" style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:6px;text-align:center;">
              <i class="ti ti-weight" style="font-size:28px;color:var(--text-muted);opacity:0.4;"></i>
              <div style="font-size:12px;color:var(--text-muted);">No weight data yet</div>
              <div style="font-size:11px;color:var(--text-muted);opacity:0.7;">Log your weight via <a href="#" onclick="nav('log');return false;" style="color:var(--primary-bright);">Log Entry</a> to track body composition</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Mood & Energy charts row -->
      <div class="grid-2" style="margin-bottom:14px;">
        <div class="card">
          <div class="card-title">Mood Trend</div>
          <div class="chart-wrap" style="height:180px;position:relative;">
            <canvas id="chart-mood" style="display:none;"></canvas>
            <div id="chart-mood-empty" style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:6px;text-align:center;">
              <i class="ti ti-mood-smile" style="font-size:28px;color:var(--text-muted);opacity:0.4;"></i>
              <div style="font-size:12px;color:var(--text-muted);">No mood data yet</div>
              <div style="font-size:11px;color:var(--text-muted);opacity:0.7;">Log your mood via <a href="#" onclick="nav('log');return false;" style="color:var(--primary-bright);">Log Entry</a></div>
            </div>
          </div>
        </div>
        <div class="card">
          <div class="card-title">Energy Trend</div>
          <div class="chart-wrap" style="height:180px;position:relative;">
            <canvas id="chart-energy" style="display:none;"></canvas>
            <div id="chart-energy-empty" style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:6px;text-align:center;">
              <i class="ti ti-bolt" style="font-size:28px;color:var(--text-muted);opacity:0.4;"></i>
              <div style="font-size:12px;color:var(--text-muted);">No energy data yet</div>
              <div style="font-size:11px;color:var(--text-muted);opacity:0.7;">Log your energy via <a href="#" onclick="nav('log');return false;" style="color:var(--primary-bright);">Log Entry</a></div>
            </div>
          </div>
        </div>
      </div>
```

- [ ] **Step 2: Verify layout in browser**

Open `index-v2.html`. Confirm:
- Two new cards appear below the weight chart in a side-by-side `grid-2` row
- Both show their empty state (icon + text) with no console errors
- Weight chart row is unchanged above them

- [ ] **Step 3: Commit**

```bash
git add index-v2.html
git commit -m "feat: add mood and energy chart card HTML to dashboard"
```

---

### Task 4: `renderMoodEnergyCharts` Function + Call Sites

**Files:**
- Modify: `index-v2.html` — add `renderMoodEnergyCharts` function, call it from `renderVitalsToCards` and `renderRealCharts`

**Interfaces:**
- Consumes: `getCycleChartData(logs, fieldKey, protocol)` from Task 1
- Consumes: `chart-mood`, `chart-mood-empty`, `chart-energy`, `chart-energy-empty` from Task 3
- Consumes: `lsGet(key, fallback)` — existing helper at line ~1591
- Consumes: `makeChart(id, type, labels, datasets)` — existing helper at line ~3332
- Consumes: `showChart(chartId)` — existing helper at line ~3344

- [ ] **Step 1: Add `renderMoodEnergyCharts` function**

Find the closing `}` of `renderVitalsToCards` (the `}` on the line immediately after the weight chart block ends, now reading `const { entries: wEntries...`). Add the new function immediately after `renderVitalsToCards` closes, before `function setDelta(`:

```js
function renderMoodEnergyCharts() {
  const logs     = lsGet('hrt_vitals_log', []);
  const protocol = lsGet('hrt_active_protocol_data', null);

  const { entries: mEntries, labels: mLabels } = getCycleChartData(logs, 'mood', protocol);
  if (mEntries.length >= 1) {
    showChart('chart-mood');
    makeChart('chart-mood', 'line', mLabels,
      [{ label: 'Mood (1–10)', data: mEntries.map(l => parseInt(l.mood)),
         borderColor: 'var(--purple)', backgroundColor: 'rgba(168,85,247,0.08)',
         tension: 0.4, fill: true, pointBackgroundColor: '#C084FC', pointRadius: 3 }]);
  }

  const { entries: eEntries, labels: eLabels } = getCycleChartData(logs, 'energy', protocol);
  if (eEntries.length >= 1) {
    showChart('chart-energy');
    makeChart('chart-energy', 'line', eLabels,
      [{ label: 'Energy (1–10)', data: eEntries.map(l => parseInt(l.energy)),
         borderColor: 'var(--amber)', backgroundColor: 'rgba(245,158,11,0.08)',
         tension: 0.4, fill: true, pointBackgroundColor: '#FCD34D', pointRadius: 3 }]);
  }
}
```

- [ ] **Step 2: Call `renderMoodEnergyCharts()` from `renderVitalsToCards`**

Find the closing `}` of the updated `renderVitalsToCards` — the line after the weight chart block:

```js
// FIND (end of renderVitalsToCards):
  const { entries: wEntries, labels: wLabels } = getCycleChartData(logs, 'weight', protocol);
  if (wEntries.length >= 2) {
    const data = wEntries.map(l => parseFloat(l.weight).toFixed(1));
    showChart('chart-weight');
    makeChart('chart-weight', 'line', wLabels,
      [{ label:'Weight (lbs)', data, borderColor:'#F59E0B', backgroundColor:'rgba(245,158,11,0.08)',
         tension:0.4, fill:true, pointBackgroundColor:'#FCD34D', pointRadius:3 }]);
  }
}

// REPLACE WITH (add one call before the closing brace):
  const { entries: wEntries, labels: wLabels } = getCycleChartData(logs, 'weight', protocol);
  if (wEntries.length >= 2) {
    const data = wEntries.map(l => parseFloat(l.weight).toFixed(1));
    showChart('chart-weight');
    makeChart('chart-weight', 'line', wLabels,
      [{ label:'Weight (lbs)', data, borderColor:'#F59E0B', backgroundColor:'rgba(245,158,11,0.08)',
         tension:0.4, fill:true, pointBackgroundColor:'#FCD34D', pointRadius:3 }]);
  }

  renderMoodEnergyCharts();
}
```

- [ ] **Step 3: Call `renderMoodEnergyCharts()` from `renderRealCharts`**

Find `function renderRealCharts()`. The function currently ends with:

```js
  // else: leave empty state visible
}
```

Add `renderMoodEnergyCharts()` before the closing brace:

```js
// FIND:
function renderRealCharts() {
  const weights = window._weightHistory || [];

  // Weight chart from daily_metrics
  if (weights.length > 1) {
    const wSorted = [...weights].filter(w => w.weight_lbs).reverse().slice(-8);
    const wLabels = wSorted.map(w => {
      const d = parseLocalDate(w.date);
      return d.toLocaleDateString('en-US', { month:'short', day:'numeric' });
    });
    const wData = wSorted.map(w => parseFloat(w.weight_lbs).toFixed(1));
    showChart('chart-weight');
    makeChart('chart-weight','line', wLabels,
      [{ label:'Weight (lbs)', data:wData, borderColor:'#22D3EE', backgroundColor:'rgba(34,211,238,0.08)', tension:0.4, fill:true, pointBackgroundColor:'#22D3EE', pointRadius:3 }]);
  }
  // else: leave empty state visible
}

// REPLACE WITH:
function renderRealCharts() {
  const weights = window._weightHistory || [];

  // Weight chart from daily_metrics
  if (weights.length > 1) {
    const wSorted = [...weights].filter(w => w.weight_lbs).reverse().slice(-8);
    const wLabels = wSorted.map(w => {
      const d = parseLocalDate(w.date);
      return d.toLocaleDateString('en-US', { month:'short', day:'numeric' });
    });
    const wData = wSorted.map(w => parseFloat(w.weight_lbs).toFixed(1));
    showChart('chart-weight');
    makeChart('chart-weight','line', wLabels,
      [{ label:'Weight (lbs)', data:wData, borderColor:'#22D3EE', backgroundColor:'rgba(34,211,238,0.08)', tension:0.4, fill:true, pointBackgroundColor:'#22D3EE', pointRadius:3 }]);
  }
  // else: leave empty state visible

  renderMoodEnergyCharts();
}
```

- [ ] **Step 4: Verify in browser**

Open `index-v2.html`. Log a vitals entry with mood and energy values (1–10) via Log Entry. Return to the dashboard. Confirm:
- Mood Trend chart renders (purple line, labeled "Mood (1–10)")
- Energy Trend chart renders (amber line, labeled "Energy (1–10)")
- X-axis shows "Wk N" labels when an active protocol with `startDate` exists, date labels otherwise
- Empty state cards show when no mood/energy data exists
- No console errors
- Weight chart continues to work

- [ ] **Step 5: Commit**

```bash
git add index-v2.html
git commit -m "feat: add renderMoodEnergyCharts function, wire into dashboard render paths"
```

---

## Self-Review

### Spec coverage

| Spec requirement | Task |
|---|---|
| Mood Trend chart, purple, var(--purple), canvas id="chart-mood" | Tasks 3 + 4 |
| Energy Trend chart, amber, var(--amber), canvas id="chart-energy" | Tasks 3 + 4 |
| Empty state for each chart | Task 3 |
| 180px chart height | Task 3 |
| getCycleChartData pure function, no DOM/localStorage | Task 1 |
| Cycle window: entries from startDate, "Wk N" labels | Task 1 |
| Fallback: 30 entries, date labels when no cycle | Task 1 |
| Local-time date parsing | Task 1 |
| Weight chart updated to use getCycleChartData | Task 2 |
| renderMoodEnergyCharts called from renderVitalsToCards | Task 4 |
| renderMoodEnergyCharts called from renderRealCharts | Task 4 |
| 13 test assertions before summary block | Task 1 |
| grid-2 side-by-side layout | Task 3 |
| No new localStorage keys | All tasks — confirmed |
| No new CSS files | All tasks — confirmed |

### Placeholder scan
No TBD, TODO, or incomplete steps.

### Type consistency
- `getCycleChartData(logs, fieldKey, protocol)` defined Task 1, called identically in Tasks 2 and 4
- `renderMoodEnergyCharts()` defined and called Task 4 — no params, reads own data
- `chart-mood`, `chart-mood-empty`, `chart-energy`, `chart-energy-empty` defined Task 3, referenced Task 4 via `showChart` and `makeChart`
- `showChart(chartId)` and `makeChart(id, type, labels, datasets)` — existing signatures unchanged

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-25-mood-energy-charts.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — Fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
