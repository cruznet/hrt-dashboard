# Dashboard Redesign (Option C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the dashboard around two use cases — "what do I need to do today" and "protocol/cycle status" — by replacing the current two-column layout with a full-width hero protocol card plus a compact 4-card vitals row (including a new Mood card).

**Architecture:** All changes are confined to `index-v2.html` (the single-file vanilla JS app). The HTML layout is restructured first so later JS tasks have stable DOM targets. Tasks proceed in dependency order: layout → new functions → data wiring → label/cleanup.

**Tech Stack:** Vanilla JS, HTML/CSS, no build system. LocalStorage only (`hrt_active_protocol_data`, `hrt_vitals_log`). No Supabase, no npm.

## Global Constraints

- All changes confined to `index-v2.html`
- No new localStorage keys
- No new CSS files — use existing CSS variables (`var(--primary)`, `var(--green)`, `var(--teal)`, `var(--font-data)`, etc.) and existing classes (`metric-card`, `mc-*`, `badge-*`, `progress-wrap`, etc.)
- Existing IDs preserved: `m-weight`, `m-bp`, `m-glucose`, `cycle-bar`, `ss-bar`, `ss-label`, `cycle-label`, `cycle-pct`, `cycle-active-compounds`, `protocol-display`
- New IDs added: `m-mood`, `m-mood-badge`, `m-mood-delta`, `cycle-week-strip`
- All user-content rendered into innerHTML must go through `escHtml()` or `.textContent` (no raw interpolation of `c.name`, `c.dose`, etc.)
- Test runner: open `tests/protocol-logic.html` in a browser — all assertions must pass

---

## File Map

| File | Role |
|---|---|
| `index-v2.html` (HTML ~560-657) | Dashboard section markup — restructured |
| `index-v2.html` (CSS ~199-203) | `.metrics-grid` — changed to flex |
| `index-v2.html` (CSS ~204-212) | `.metric-card` — add `flex:1; min-width:0` |
| `index-v2.html` (JS ~2050-2200) | `buildWeekStrip` added, `renderCycleProgress` updated |
| `index-v2.html` (JS ~1730-1805) | `renderVitalsToCards` updated for mood card + sparkline removal |
| `index-v2.html` (JS ~1720-1726) | `loadDemoData` — dead calls removed |
| `tests/protocol-logic.html` | New test assertions for `buildWeekStrip` and mood extraction |

---

### Task 1: HTML Restructure

**Files:**
- Modify: `index-v2.html` — dashboard HTML section (lines ~560–657) and metric CSS (lines ~199–212)

**Interfaces:**
- Produces: `id="cycle-week-strip"` div (empty, hidden) — Task 2 renders into it
- Produces: `id="m-mood"`, `id="m-mood-badge"`, `id="m-mood-delta"` elements — Task 3 populates them
- Preserves all existing IDs listed in Global Constraints

This is a pure HTML/CSS change — no JS logic changes. The goal is to give Tasks 2 and 3 stable DOM targets to work against.

- [ ] **Step 1: Change `.metrics-grid` CSS from grid to flex**

Find and replace (around line 199):

```css
/* BEFORE */
.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 10px; margin-bottom: 16px;
}

/* AFTER */
.metrics-grid {
  display: flex;
  gap: 10px;
  margin-bottom: 16px;
}
```

- [ ] **Step 2: Add `flex: 1; min-width: 0` to `.metric-card`**

Find and replace (around line 204):

```css
/* BEFORE */
.metric-card {
  background: var(--bg-card);
  border: 0.5px solid var(--border);
  border-radius: var(--radius);
  border-top-width: 2px;
  padding: 10px 12px;
  cursor: default;
  transition: background var(--transition);
}

/* AFTER */
.metric-card {
  background: var(--bg-card);
  border: 0.5px solid var(--border);
  border-radius: var(--radius);
  border-top-width: 2px;
  padding: 10px 12px;
  cursor: default;
  transition: background var(--transition);
  flex: 1;
  min-width: 0;
}
```

- [ ] **Step 3: Add Mood metric card to `#metrics-grid`**

Find the closing `</div>` of the glucose card and insert the Mood card immediately before the closing `</div>` of `#metrics-grid`. The current `#metrics-grid` block (around lines 560–582) ends with:

```html
        <div class="metric-card mc-purple">
          <div class="metric-label">Glucose</div>
          <div class="metric-value" id="m-glucose">—</div>
          <div class="metric-unit">mg/dL</div>
          <span class="metric-badge badge-muted" id="m-glucose-badge">No data</span>
          <div class="metric-delta" id="m-glucose-delta"></div>
        </div>
      </div>
```

Replace with:

```html
        <div class="metric-card mc-purple">
          <div class="metric-label">Glucose</div>
          <div class="metric-value" id="m-glucose">—</div>
          <div class="metric-unit">mg/dL</div>
          <span class="metric-badge badge-muted" id="m-glucose-badge">No data</span>
          <div class="metric-delta" id="m-glucose-delta"></div>
        </div>
        <div class="metric-card mc-teal">
          <div class="metric-label">Mood</div>
          <div class="metric-value" id="m-mood">—</div>
          <div class="metric-unit">/10</div>
          <span class="metric-badge badge-muted" id="m-mood-badge">No data</span>
          <div class="metric-delta" id="m-mood-delta"></div>
        </div>
      </div>
```

- [ ] **Step 4: Replace `grid-2-1` wrapper with a single full-width hero card**

The current block starting at `<div class="grid-2-1" ...>` and ending at the outer `</div>` (around lines 584–640) contains the left card (Active Protocol + Cycle Progress) and the right card (Upcoming + Last Entry + Mood-energy sparklines). Replace the entire block with just the left card content, unwrapped, and add `id="cycle-week-strip"` after the cycle progress bar.

Current block to remove (lines ~584–640):
```html
      <div class="grid-2-1" style="margin-bottom:14px;">
        <!-- Active protocol card -->
        <div class="card">
          <div class="card-title">Active Protocol</div>
          <div id="protocol-display">
            <div style="color:var(--text-muted);font-size:12px;">No active protocol. <a href="#" onclick="nav('builder');return false;" style="color:var(--primary-bright);">Build one →</a></div>
          </div>
          <hr class="divider">
          <div class="card-title">Cycle Progress</div>
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
            <span style="font-size:12px;color:var(--text-secondary);" id="cycle-label">—</span>
            <span style="font-size:12px;font-family:var(--font-data);color:var(--primary-bright);" id="cycle-pct">—</span>
          </div>
          <div class="progress-wrap">
            <div class="progress-bar" id="cycle-bar" style="width:0%;background:var(--primary);"></div>
          </div>
          <div style="margin-top:10px;">
            <div style="font-size:10px;color:var(--text-muted);margin-bottom:3px;">Steady State</div>
            <div class="progress-wrap">
              <div class="progress-bar" id="ss-bar" style="width:0%;background:var(--teal);"></div>
            </div>
            <div style="font-size:11px;font-family:var(--font-data);color:var(--teal);margin-top:3px;" id="ss-label">—</div>
          </div>
          <div id="cycle-active-compounds" style="margin-top:10px;"></div>
        </div>

        <!-- Upcoming doses -->
        <div class="card">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
            <div class="card-title" style="margin:0;">Upcoming</div>
            <span id="adherence-badge" class="metric-badge badge-muted" style="display:none;"></span>
          </div>
          <div id="upcoming-list" style="font-size:12px;color:var(--text-muted);">
            Log a protocol to see upcoming doses.
          </div>
          <hr class="divider">
          <div class="card-title">Last Entry</div>
          <div id="last-entry" style="font-size:12px;color:var(--text-muted);">No entries yet.</div>
          <div id="mood-energy-row" style="display:none;margin-top:10px;">
            <div style="display:flex;gap:14px;">
              <div style="flex:1;">
                <div style="font-size:10px;color:var(--text-muted);margin-bottom:4px;">MOOD (7d)</div>
                <div id="mood-sparkline" style="display:flex;gap:2px;align-items:flex-end;height:24px;"></div>
              </div>
              <div style="flex:1;">
                <div style="font-size:10px;color:var(--text-muted);margin-bottom:4px;">ENERGY (7d)</div>
                <div id="energy-sparkline" style="display:flex;gap:2px;align-items:flex-end;height:24px;"></div>
              </div>
              <div style="flex:1;">
                <div style="font-size:10px;color:var(--text-muted);margin-bottom:4px;">LOG STREAK</div>
                <div id="log-streak-display" style="font-size:18px;font-family:var(--font-data);color:var(--primary-bright);">—</div>
                <div style="font-size:10px;color:var(--text-muted);">days</div>
              </div>
            </div>
          </div>
        </div>
      </div>
```

Replace with:

```html
      <div style="margin-bottom:14px;">
        <div class="card">
          <div class="card-title">Active Protocol</div>
          <div id="protocol-display">
            <div style="color:var(--text-muted);font-size:12px;">No active protocol. <a href="#" onclick="nav('builder');return false;" style="color:var(--primary-bright);">Build one →</a></div>
          </div>
          <hr class="divider">
          <div class="card-title">Cycle Progress</div>
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
            <span style="font-size:12px;color:var(--text-secondary);" id="cycle-label">—</span>
            <span style="font-size:12px;font-family:var(--font-data);color:var(--primary-bright);" id="cycle-pct">—</span>
          </div>
          <div class="progress-wrap">
            <div class="progress-bar" id="cycle-bar" style="width:0%;background:var(--primary);"></div>
          </div>
          <div id="cycle-week-strip" style="overflow-x:auto;margin:8px 0;display:none;"></div>
          <div style="margin-top:10px;">
            <div style="font-size:10px;color:var(--text-muted);margin-bottom:3px;">Steady State</div>
            <div class="progress-wrap">
              <div class="progress-bar" id="ss-bar" style="width:0%;background:var(--teal);"></div>
            </div>
            <div style="font-size:11px;font-family:var(--font-data);color:var(--teal);margin-top:3px;" id="ss-label">—</div>
          </div>
          <div id="cycle-active-compounds" style="margin-top:10px;"></div>
        </div>
      </div>
```

- [ ] **Step 5: Verify layout in browser**

Open `index-v2.html` (or `http://localhost:3000/index-v2.html` if a server is running). Confirm:
- 4 metric cards render in a single horizontal row (Weight, BP, Glucose, Mood)
- One full-width hero card renders with "Active Protocol" + "Cycle Progress" + cycle bar
- No "Upcoming" / "Last Entry" right column visible
- Weight chart still renders below the vitals row
- No console errors about missing elements

- [ ] **Step 6: Commit**

```bash
git add index-v2.html
git commit -m "feat: restructure dashboard to full-width hero card + 4-card vitals row (no JS changes)"
```

---

### Task 2: Week Timeline Strip

**Files:**
- Modify: `index-v2.html` — add `buildWeekStrip` function (before `renderCycleProgress`) and update `renderCycleProgress` to render into `#cycle-week-strip`
- Modify: `tests/protocol-logic.html` — add test section for `buildWeekStrip`

**Interfaces:**
- Consumes: `id="cycle-week-strip"` div from Task 1
- Produces: `buildWeekStrip(currentWeek, totalWeeks)` — pure function, no DOM access, returns HTML string
- `renderCycleProgress` updated: calls `buildWeekStrip` and injects into `#cycle-week-strip`; hides strip when `!protocol.startDate || totalWeeks === 0`

- [ ] **Step 1: Write the failing test for `buildWeekStrip`**

Open `tests/protocol-logic.html`. Add before the summary block (the `results.innerHTML += ...` line near the bottom):

```html
<script>
// ── buildWeekStrip ──
function buildWeekStrip(currentWeek, totalWeeks) {
  const squares = [];
  for (let w = 1; w <= totalWeeks; w++) {
    if (w < currentWeek) {
      squares.push(`<div style="width:14px;height:14px;border-radius:2px;background:var(--primary);opacity:0.3;flex-shrink:0;" title="Week ${w}"></div>`);
    } else if (w === currentWeek) {
      squares.push(
        `<div style="display:flex;flex-direction:column;align-items:center;flex-shrink:0;">` +
        `<div style="width:14px;height:14px;border-radius:2px;background:var(--primary);" title="Week ${w}"></div>` +
        `<div style="font-size:8px;color:var(--primary-bright);margin-top:2px;font-family:var(--font-data);white-space:nowrap;">Wk ${w}</div>` +
        `</div>`
      );
    } else {
      squares.push(`<div style="width:14px;height:14px;border-radius:2px;border:1px solid var(--primary);opacity:0.4;flex-shrink:0;" title="Week ${w}"></div>`);
    }
  }
  return `<div style="display:flex;gap:3px;align-items:flex-end;padding:2px 0;">${squares.join('')}</div>`;
}

section('buildWeekStrip');
(function() {
  assert('returns a non-empty string',
    typeof buildWeekStrip(3, 10) === 'string' && buildWeekStrip(3, 10).length > 0, true);
  assert('contains current week label "Wk 3" when currentWeek=3',
    buildWeekStrip(3, 10).includes('Wk 3'), true);
  assert('does NOT contain "Wk 2" label when currentWeek=3 (past weeks have no label)',
    buildWeekStrip(3, 10).includes('Wk 2'), false);
  assert('week 1 of 1 is just the current week, no past or future',
    buildWeekStrip(1, 1).includes('Wk 1'), true);
  assert('totalWeeks=0 returns empty wrapper div',
    buildWeekStrip(1, 0), '<div style="display:flex;gap:3px;align-items:flex-end;padding:2px 0;"></div>');
  assert('contains "Wk 12" label when currentWeek=12',
    buildWeekStrip(12, 12).includes('Wk 12'), true);
})();
</script>
```

- [ ] **Step 2: Open `tests/protocol-logic.html` in a browser — verify the new assertions FAIL**

Expected: "buildWeekStrip" section shows failures (function not yet imported from `index-v2.html`). The rest of the test suite (isDueToday, daysUntilNextDose) should still pass.

Note: The test file includes a local copy of the function for isolation. When the function is added to `index-v2.html` in Step 3, the test copy and the app copy must match exactly.

- [ ] **Step 3: Add `buildWeekStrip` to `index-v2.html`**

In `index-v2.html`, find the `renderCycleProgress` function (search for `function renderCycleProgress`). Add the following function immediately before it (so before `function renderCycleProgress(rawProtocol) {`):

```js
function buildWeekStrip(currentWeek, totalWeeks) {
  const squares = [];
  for (let w = 1; w <= totalWeeks; w++) {
    if (w < currentWeek) {
      squares.push(`<div style="width:14px;height:14px;border-radius:2px;background:var(--primary);opacity:0.3;flex-shrink:0;" title="Week ${w}"></div>`);
    } else if (w === currentWeek) {
      squares.push(
        `<div style="display:flex;flex-direction:column;align-items:center;flex-shrink:0;">` +
        `<div style="width:14px;height:14px;border-radius:2px;background:var(--primary);" title="Week ${w}"></div>` +
        `<div style="font-size:8px;color:var(--primary-bright);margin-top:2px;font-family:var(--font-data);white-space:nowrap;">Wk ${w}</div>` +
        `</div>`
      );
    } else {
      squares.push(`<div style="width:14px;height:14px;border-radius:2px;border:1px solid var(--primary);opacity:0.4;flex-shrink:0;" title="Week ${w}"></div>`);
    }
  }
  return `<div style="display:flex;gap:3px;align-items:flex-end;padding:2px 0;">${squares.join('')}</div>`;
}
```

- [ ] **Step 4: Update `renderCycleProgress` to render the week strip**

In `renderCycleProgress`, find the block that sets the progress bar width (the line `if (bar) bar.style.width = ...;`). Insert the week strip rendering immediately after it, before the steady state comment:

```js
// FIND this line (around line 2100 after Task 1):
  if (bar) bar.style.width = `${progressPct}%`;

// ADD immediately after:
  const weekStripEl = document.getElementById('cycle-week-strip');
  if (weekStripEl) {
    if (protocol.startDate && totalWeeks > 0) {
      weekStripEl.innerHTML = buildWeekStrip(currentWeek, totalWeeks);
      weekStripEl.style.display = 'block';
    } else {
      weekStripEl.style.display = 'none';
    }
  }

// Then the existing steady state comment and code continues:
  // Steady state bar (unchanged logic)
```

Also, in the guard block that fires when `protocol.status !== 'active' || !protocol.startDate` (around line 2083), hide the week strip:

```js
// FIND this block:
  if (protocol.status !== 'active' || !protocol.startDate) {
    if (cycleCard) cycleCard.innerHTML = '';
    if (label) { label.textContent = '—'; }
    if (pct) { pct.textContent = '—'; }
    if (bar) { bar.style.width = '0%'; }
    if (ssBar) { ssBar.style.width = '0%'; }
    if (ssLbl) { ssLbl.textContent = '—'; }
    return;
  }

// ADD one line inside the block before the return:
    const _ws = document.getElementById('cycle-week-strip');
    if (_ws) _ws.style.display = 'none';
```

Also hide it in the no-protocol early-return (around line 2071):

```js
// FIND:
  if (!rawProtocol || !rawProtocol.saved_at) {
    label.textContent = '—'; pct.textContent = '—';
    if (bar) bar.style.width = '0%';
    if (ssBar) ssBar.style.width = '0%';
    if (ssLbl) ssLbl.textContent = '—';
    return;
  }

// ADD before the return:
    const _ws2 = document.getElementById('cycle-week-strip');
    if (_ws2) _ws2.style.display = 'none';
```

- [ ] **Step 5: Open `tests/protocol-logic.html` in a browser — all assertions should pass**

Expected: All 67 + 6 new = 73 assertions pass. The `buildWeekStrip` section shows 6 green passes.

- [ ] **Step 6: Verify strip renders in browser**

Open `index-v2.html`. With an active protocol that has a `startDate`:
- The week strip appears below the cycle progress bar: small colored squares, one labeled "Wk N"
- Past weeks are filled at 30% opacity, current is filled full, future are outlined
- Strip is hidden when no protocol or no startDate

- [ ] **Step 7: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat: add week timeline strip to hero protocol card"
```

---

### Task 3: Mood Metric Card Data

**Files:**
- Modify: `index-v2.html` — update `renderVitalsToCards` to populate `m-mood`, remove sparkline/streak dead code
- Modify: `tests/protocol-logic.html` — add mood extraction test section

**Interfaces:**
- Consumes: `id="m-mood"`, `id="m-mood-badge"`, `id="m-mood-delta"` from Task 1
- Consumes: `updateMetricCard(id, value, badge, badgeClass)` — existing helper, unchanged
- Consumes: `setDelta(elId, current, prev, unit, lowerIsBetter)` — existing helper, unchanged
- Consumes: `hrt_vitals_log` entries where `l.mood` is a numeric string 1–10

- [ ] **Step 1: Write the failing test for mood extraction logic**

Open `tests/protocol-logic.html`. Add before the summary block (append to the same location as Task 2's additions):

```html
<script>
// ── Mood extraction logic ──
function extractLatestMood(logs) {
  const moodLogs = logs.filter(l => l.mood && parseInt(l.mood) > 0);
  if (!moodLogs.length) return null;
  return parseInt(moodLogs[0].mood);
}

section('Mood extraction');
(function() {
  assert('empty logs → null',
    extractLatestMood([]), null);
  assert('single entry with mood returns its value',
    extractLatestMood([{ mood: '7' }]), 7);
  assert('picks first (newest) entry when multiple have mood',
    extractLatestMood([{ mood: '8', date: '2026-06-10' }, { mood: '5', date: '2026-06-09' }]), 8);
  assert('skips entries without mood field',
    extractLatestMood([{ weight: '150' }, { mood: '6' }]), 6);
  assert('ignores mood: "0" (zero is falsy after parseInt check)',
    extractLatestMood([{ mood: '0' }, { mood: '9' }]), 9);
  assert('badge is "Good" for mood >= 8',
    (function() {
      const v = extractLatestMood([{ mood: '8' }]);
      return v >= 8 ? 'Good' : v >= 5 ? 'Fair' : 'Low';
    })(), 'Good');
  assert('badge is "Fair" for mood = 6',
    (function() {
      const v = extractLatestMood([{ mood: '6' }]);
      return v >= 8 ? 'Good' : v >= 5 ? 'Fair' : 'Low';
    })(), 'Fair');
  assert('badge is "Low" for mood = 3',
    (function() {
      const v = extractLatestMood([{ mood: '3' }]);
      return v >= 8 ? 'Good' : v >= 5 ? 'Fair' : 'Low';
    })(), 'Low');
})();
</script>
```

- [ ] **Step 2: Open `tests/protocol-logic.html` — verify new assertions FAIL**

Expected: "Mood extraction" section shows failures (function not yet in `index-v2.html`, but the local copy in the test file is fine — all 8 new assertions should actually PASS since the test file defines `extractLatestMood` locally). Verify all 8 pass.

Note: Unlike `isDueToday` and `daysUntilNextDose`, `extractLatestMood` is a test-file-only helper that mirrors the inline logic in `renderVitalsToCards`. There is no copy in `index-v2.html` — the logic is embedded directly in `renderVitalsToCards`.

- [ ] **Step 3: Update `renderVitalsToCards` in `index-v2.html`**

Find `function renderVitalsToCards()` (around line 1730).

**3a — Update the no-data guard** (around line 1734):

```js
// BEFORE:
  if (!logs.length) {
    ['m-weight','m-bp','m-glucose'].forEach(id =>
      updateMetricCard(id, '—', 'No data', 'badge-muted'));
    return;
  }

// AFTER:
  if (!logs.length) {
    ['m-weight','m-bp','m-glucose','m-mood'].forEach(id =>
      updateMetricCard(id, '—', 'No data', 'badge-muted'));
    return;
  }
```

**3b — Add mood card population** after the Glucose section (around line 1770, before the `// ── Mood & Energy sparklines` comment). Insert this block:

```js
  // ── Mood ──
  const moodLogs = logs.filter(l => l.mood && parseInt(l.mood) > 0);
  if (moodLogs.length) {
    const latestMood = parseInt(moodLogs[0].mood);
    const prevMood   = moodLogs.length > 1 ? parseInt(moodLogs[1].mood) : null;
    const moodBadge  = latestMood >= 8 ? ['Good','badge-green'] : latestMood >= 5 ? ['Fair','badge-amber'] : ['Low','badge-red'];
    updateMetricCard('m-mood', `${latestMood}/10`, moodBadge[0], moodBadge[1]);
    if (prevMood !== null) setDelta('m-mood-delta', latestMood, prevMood, '/10', false);
  }
```

**3c — Remove the mood/energy sparkline and log streak block** (the lines referencing removed HTML elements). Find and delete the following block (around lines 1773–1790):

```js
  // ── Mood & Energy sparklines (last 7 entries with values) ──
  const moodLogs   = logs.filter(l => l.mood   && parseInt(l.mood)   > 0).slice(0, 7).reverse();
  const energyLogs = logs.filter(l => l.energy && parseInt(l.energy) > 0).slice(0, 7).reverse();
  const hasMoodEnergy = moodLogs.length > 0 || energyLogs.length > 0;

  if (hasMoodEnergy) {
    document.getElementById('mood-energy-row').style.display = 'block';
    renderSparkline('mood-sparkline',   moodLogs.map(l => parseInt(l.mood)),   10, 'var(--purple)');
    renderSparkline('energy-sparkline', energyLogs.map(l => parseInt(l.energy)), 10, 'var(--amber)');
  }

  // ── Log streak ──
  const streak = calcLogStreak(logs);
  const streakEl = document.getElementById('log-streak-display');
  if (streakEl) {
    streakEl.textContent = streak;
    if (hasMoodEnergy || streak > 0) document.getElementById('mood-energy-row').style.display = 'block';
  }
```

Note: `calcLogStreak` and `renderSparkline` functions can remain in the file — they just won't be called from `renderVitalsToCards` anymore. No other function calls them for this dashboard flow.

Also note: the variable name `moodLogs` is now used for two things — the one you're removing (sparkline slice) and the new one you added in 3b. After removal, there is no name conflict since you're removing the old one and adding the new one. Ensure the order is: add new mood block (Step 3b) THEN remove the old block (Step 3c), or combine them as one edit.

- [ ] **Step 4: Open `tests/protocol-logic.html` — all assertions pass**

Expected: All 73 + 8 new = 81 assertions pass. The new "Mood extraction" section shows 8 green.

- [ ] **Step 5: Verify mood card in browser**

Open `index-v2.html`. Using browser dev tools or the Log Entry page, add a vitals entry with a mood value (1–10). Reload. The Mood card should show the value as `N/10` with the appropriate badge (Good/Fair/Low) and a delta if more than one mood entry exists.

With no mood data, the Mood card shows `—` / "No data".

- [ ] **Step 6: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat: add mood metric card to dashboard vitals row, remove sparkline/streak dead code"
```

---

### Task 4: Hero Card Label + Dead-Call Cleanup

**Files:**
- Modify: `index-v2.html` — update `renderCycleProgress` label, remove dead calls to `renderUpcoming`/`renderLastVitalsEntry`/`renderAdherenceBadge` from `loadDemoData` and `nav()`

**Interfaces:**
- No new functions; no new IDs
- `renderUpcoming()` and `renderAdherenceBadge()` are NOT deleted — they reference `#upcoming-list` which no longer exists and already null-guard correctly. Only the calls from `loadDemoData` and `nav()` are removed.

- [ ] **Step 1: Update the "Active this week" label in `renderCycleProgress`**

In `renderCycleProgress`, find the `cycleCard.innerHTML = ...` template string (around line 2189). Change the label from muted gray to green with "TODAY'S INJECTIONS":

```js
// BEFORE:
  cycleCard.innerHTML = `
    <div style="font-size:11px;color:var(--text-muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em;">Active this week</div>
    ${activeHtml}
    ${cycleEndBanner}
    ${upcomingHtml}
  `;

// AFTER:
  cycleCard.innerHTML = `
    <div style="font-size:10px;color:var(--green);margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em;">Today&#x27;s Injections</div>
    ${activeHtml}
    ${cycleEndBanner}
    ${upcomingHtml}
  `;
```

- [ ] **Step 2: Remove dead calls from `loadDemoData`**

Find `function loadDemoData()` (around line 1702). The function currently calls `renderLastVitalsEntry()`, `renderUpcoming()`, and `renderAdherenceBadge()`. Remove those three lines:

```js
// BEFORE:
  renderCycleProgress(p);
  renderVitalsToCards();   // populate metric cards + deltas + sparklines from localStorage
  renderLastVitalsEntry();
  renderUpcoming();
  renderAdherenceBadge();
  updateTopbarBadge();

// AFTER:
  renderCycleProgress(p);
  renderVitalsToCards();
  updateTopbarBadge();
```

- [ ] **Step 3: Remove `renderUpcoming()` call from `nav()` dashboard handler**

Find `nav()` (search for `function nav(`) or the dashboard nav handler. The line that calls `renderUpcoming()` when navigating to the dashboard (around line 1957):

```js
// FIND (inside the 'dashboard' branch of nav()):
  if (page === 'dashboard') setTimeout(() => { if (_supa && _supaUser) renderRealCharts(); else renderDemoCharts(); renderUpcoming(); }, 100);

// REPLACE with:
  if (page === 'dashboard') setTimeout(() => { if (_supa && _supaUser) renderRealCharts(); else renderDemoCharts(); }, 100);
```

- [ ] **Step 4: Verify no console errors**

Open `index-v2.html`. Open browser DevTools → Console. Navigate to the dashboard. Confirm:
- No `Cannot read properties of null` errors for `upcoming-list`, `last-entry`, `mood-energy-row`, `log-streak-display`, `adherence-badge`
- The "TODAY'S INJECTIONS" label appears in green when there is an active protocol with a start date
- All 4 vitals cards render correctly

- [ ] **Step 5: Commit**

```bash
git add index-v2.html
git commit -m "feat: update hero card injections label, remove dead dashboard render calls"
```

---

## Self-Review

### Spec coverage check

| Spec requirement | Task |
|---|---|
| Full-width hero card (replace grid-2-1) | Task 1 |
| Week timeline strip with past/current/future squares | Task 2 |
| Strip hidden when no startDate | Task 2 |
| TODAY'S INJECTIONS label in var(--green) | Task 4 |
| Upcoming changes section (already in renderCycleProgress) | No change needed — existing |
| Cycle-end banner (already in renderCycleProgress) | No change needed — existing |
| 4-card vitals row (flex, equal-width) | Task 1 |
| Mood card with id m-mood, mc-teal, /10 unit | Task 1 (HTML) + Task 3 (JS) |
| Mood badge: Good/Fair/Low | Task 3 |
| Mood delta vs previous entry | Task 3 |
| Remove mood/energy sparklines | Task 3 |
| Remove log streak counter | Task 3 |
| Remove adherence-badge container | Task 1 |
| Remove right-column Upcoming card | Task 1 |
| Remove Last Entry section | Task 1 |
| Weight chart unchanged below vitals | No change needed |
| All existing IDs preserved | Verified in Task 1 |
| No new localStorage keys | Verified — only reads existing `hrt_vitals_log[].mood` |
| escHtml() on all user content in innerHTML | No new innerHTML sinks added |
| Tests pass | Tasks 2 + 3 add assertions |

### Placeholder scan
No TBD, TODO, or incomplete steps.

### Type/name consistency
- `buildWeekStrip(currentWeek, totalWeeks)` — defined Task 2 Step 3, called Task 2 Step 4, test copy matches exactly
- `m-mood`, `m-mood-badge`, `m-mood-delta` — defined Task 1 HTML, called by `updateMetricCard` in Task 3
- `cycle-week-strip` — defined Task 1 HTML, targeted by `renderCycleProgress` in Task 2
- `updateMetricCard(id, value, badge, badgeClass)` — existing function, signature unchanged
- `setDelta(elId, current, prev, unit, lowerIsBetter)` — existing function, signature unchanged

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-24-dashboard-redesign.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — Fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
