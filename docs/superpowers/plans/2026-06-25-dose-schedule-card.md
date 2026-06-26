# Dose Schedule Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Dose Schedule card to the dashboard that shows today's full compound list with due/not-due status and an upcoming strip for non-daily compounds, filling the empty left column next to the Weight chart.

**Architecture:** New pure function `isDueOnDate(freq, startDate, targetDate)` generalises the existing `isDueToday` for arbitrary dates. New `renderDoseSchedule()` reads `hrt_active_protocol_data`, renders today's compounds and the upcoming strip into a static HTML element `#dose-schedule-content`, and is called from inside `renderCycleProgress` so both cards always update together.

**Tech Stack:** Vanilla JS, Chart.js (untouched), browser localStorage — single file `index-v2.html`, tests in `tests/protocol-logic.html`.

## Global Constraints

- All JS/HTML changes confined to `index-v2.html` only; all test changes confined to `tests/protocol-logic.html` only
- No new localStorage keys, no new CSS files, no new HTML files
- `isDueOnDate` is a pure function — no `new Date()` without arguments, no DOM, no localStorage
- `currentPhaseDose` is a pure function — no side effects
- Timezone-safe date parsing: always `const [y,m,d] = s.split('-').map(Number); new Date(y,m-1,d)` — never `new Date(dateString)` for date-only strings
- All user-supplied strings (`c.name`, `c.dose`, `c.unit`) passed through `escHtml()` before writing to innerHTML
- New test assertions must go as plain JS inside the existing outer `<script>` block in `tests/protocol-logic.html`, immediately before the `// ── summary ──` line — no `<script>` wrapper tags inside the block
- `isDueToday` (existing function, ~line 2031) must not be modified
- `renderCycleProgress` (existing function, lines 2131–2277) must not be modified beyond adding one `renderDoseSchedule();` call before its closing `}`

---

### Task 1: `isDueOnDate` Pure Function + Tests

**Files:**
- Modify: `index-v2.html` — add `isDueOnDate` after `isDueToday` closes (~line 2066)
- Modify: `tests/protocol-logic.html` — add test block before `// ── summary ──`

**Interfaces:**
- Produces: `isDueOnDate(freq, startDate, targetDate) → boolean` — consumed by Task 3

- [ ] **Step 1: Add `isDueOnDate` to `tests/protocol-logic.html` (test copy) before `// ── summary ──`**

Find `// ── summary ──` in `tests/protocol-logic.html`. Insert the following block of plain JS immediately before that line (no `<script>` wrapper — you are inside the existing outer `<script>` block):

```js
// ── isDueOnDate ──
function isDueOnDate(freq, startDate, targetDate) {
  const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  const targetDay = days[targetDate.getDay()];
  if (Array.isArray(freq)) return freq.includes(targetDay);
  const f = (freq || '').toUpperCase().trim();
  if (f === 'ED' || f === 'PWO') return true;
  if (!startDate) return false;
  const [sy, sm, sd] = startDate.split('-').map(Number);
  const start  = new Date(sy, sm - 1, sd);
  const target = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate());
  const daysSinceStart = Math.round((target - start) / 86400000);
  if (daysSinceStart < 0) return false;
  const startDay = days[start.getDay()];
  if (f === 'EOD')   return daysSinceStart % 2 === 0;
  if (f === 'E3D')   return daysSinceStart % 3 === 0;
  if (f === 'E4D')   return daysSinceStart % 4 === 0;
  if (f === 'E5D')   return daysSinceStart % 5 === 0;
  if (f === 'E3.5D' || f === '2X/WK') {
    const si = days.indexOf(startDay);
    return targetDay === startDay || targetDay === days[(si + 3) % 7];
  }
  if (f === '3X/WK') {
    const si = days.indexOf(startDay);
    return targetDay === startDay || targetDay === days[(si + 2) % 7] || targetDay === days[(si + 4) % 7];
  }
  if (f === 'WEEKLY')  return targetDay === startDay;
  if (f === 'BI-WKLY') return targetDay === startDay && daysSinceStart % 14 === 0;
  if (f === 'MONTHLY') return targetDate.getDate() === start.getDate();
  return false;
}

section('isDueOnDate');
// Jan 1 2024 = Monday. Use as fixed start date for all tests.
const _ioaStart = '2024-01-01';
function _d(offset) { return new Date(2024, 0, 1 + offset); } // day 0=Mon, 1=Tue, 3=Thu, 7=Mon

assert('ED always due', isDueOnDate('ED', _ioaStart, _d(5)), true);
assert('PWO always due', isDueOnDate('PWO', _ioaStart, _d(2)), true);
assert('EOD day 0 due', isDueOnDate('EOD', _ioaStart, _d(0)), true);
assert('EOD day 1 not due', isDueOnDate('EOD', _ioaStart, _d(1)), false);
assert('EOD day 2 due', isDueOnDate('EOD', _ioaStart, _d(2)), true);
assert('E3D day 3 due', isDueOnDate('E3D', _ioaStart, _d(3)), true);
assert('E3D day 1 not due', isDueOnDate('E3D', _ioaStart, _d(1)), false);
assert('2X/WK start day due', isDueOnDate('2X/WK', _ioaStart, _d(0)), true);
assert('2X/WK start+3 (Thu) due', isDueOnDate('2X/WK', _ioaStart, _d(3)), true);
assert('2X/WK start+1 (Tue) not due', isDueOnDate('2X/WK', _ioaStart, _d(1)), false);
assert('WEEKLY next Mon due', isDueOnDate('WEEKLY', _ioaStart, _d(7)), true);
assert('WEEKLY Tue not due', isDueOnDate('WEEKLY', _ioaStart, _d(1)), false);
assert('array freq Mon due', isDueOnDate(['Mon','Wed','Fri'], null, _d(0)), true);
assert('array freq Tue not due', isDueOnDate(['Mon','Wed','Fri'], null, _d(1)), false);
assert('no startDate non-ED false', isDueOnDate('E3D', null, _d(0)), false);
assert('E4D day 4 due', isDueOnDate('E4D', _ioaStart, _d(4)), true);
assert('E4D day 2 not due', isDueOnDate('E4D', _ioaStart, _d(2)), false);
```

- [ ] **Step 2: Open `tests/protocol-logic.html` in a browser and verify all assertions pass**

The test file is self-contained — `isDueOnDate` is defined in the test copy above. All 17 new assertions should pass immediately.

Expected: 17 additional assertions in the `passed` total; 0 in `failed`.

- [ ] **Step 3: Add `isDueOnDate` to `index-v2.html`**

Find `isDueToday` in `index-v2.html` (~line 2031). It ends with `}` at approximately line 2065. `daysUntilNextDose` begins at approximately line 2067. Insert the following block between them (after `isDueToday`'s closing `}`, before `function daysUntilNextDose`):

```js
function isDueOnDate(freq, startDate, targetDate) {
  const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  const targetDay = days[targetDate.getDay()];
  if (Array.isArray(freq)) return freq.includes(targetDay);
  const f = (freq || '').toUpperCase().trim();
  if (f === 'ED' || f === 'PWO') return true;
  if (!startDate) return false;
  const [sy, sm, sd] = startDate.split('-').map(Number);
  const start  = new Date(sy, sm - 1, sd);
  const target = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate());
  const daysSinceStart = Math.round((target - start) / 86400000);
  if (daysSinceStart < 0) return false;
  const startDay = days[start.getDay()];
  if (f === 'EOD')   return daysSinceStart % 2 === 0;
  if (f === 'E3D')   return daysSinceStart % 3 === 0;
  if (f === 'E4D')   return daysSinceStart % 4 === 0;
  if (f === 'E5D')   return daysSinceStart % 5 === 0;
  if (f === 'E3.5D' || f === '2X/WK') {
    const si = days.indexOf(startDay);
    return targetDay === startDay || targetDay === days[(si + 3) % 7];
  }
  if (f === '3X/WK') {
    const si = days.indexOf(startDay);
    return targetDay === startDay || targetDay === days[(si + 2) % 7] || targetDay === days[(si + 4) % 7];
  }
  if (f === 'WEEKLY')  return targetDay === startDay;
  if (f === 'BI-WKLY') return targetDay === startDay && daysSinceStart % 14 === 0;
  if (f === 'MONTHLY') return targetDate.getDate() === start.getDate();
  return false;
}
```

**Critical:** the app copy must be byte-for-byte identical to the test copy in Step 1. Compare them character-by-character if needed.

- [ ] **Step 4: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat: add isDueOnDate pure function + 17 tests"
```

---

### Task 2: Dashboard HTML — Add Schedule Card, Weight Moves Right

**Files:**
- Modify: `index-v2.html` — add schedule card HTML before weight card in `<!-- Charts row -->`

**Interfaces:**
- Produces: `id="dose-schedule-content"` — consumed by Task 3's `renderDoseSchedule()`

This is a pure HTML change — no JS.

- [ ] **Step 1: Replace the Charts row in `index-v2.html`**

Find this exact block in `index-v2.html` (around line 621):

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
        <div class="card" style="min-height:212px;">
          <div class="card-title">Dose Schedule</div>
          <div id="dose-schedule-content" style="font-size:12px;line-height:1.6;"></div>
        </div>
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

- [ ] **Step 2: Verify**

```bash
grep -n 'dose-schedule-content\|chart-weight' index-v2.html | head -10
```

Expected: `dose-schedule-content` appears before `chart-weight` in the same `grid-2` block.

- [ ] **Step 3: Commit**

```bash
git add index-v2.html
git commit -m "feat: add dose schedule card HTML, move weight chart to right column"
```

---

### Task 3: `currentPhaseDose` + `renderDoseSchedule` + Wire-up

**Files:**
- Modify: `index-v2.html` — add `currentPhaseDose`, add `renderDoseSchedule`, call from `renderCycleProgress`

**Interfaces:**
- Consumes: `isDueOnDate(freq, startDate, targetDate)` from Task 1; `#dose-schedule-content` from Task 2
- Consumes (existing): `lsGet(key, fallback)`, `escHtml(s)`, `normalizeCompound(c)`, `pbCurrentCycleWeek(startDate)`, `_abbrevCompound(name)`
- Produces: `renderDoseSchedule()` — called from `renderCycleProgress`

- [ ] **Step 1: Add `currentPhaseDose` and `renderDoseSchedule` after `renderCycleProgress` closes**

`renderCycleProgress` closes with `}` at approximately line 2277. `toggleSidebar` begins at approximately line 2279. Insert the following two functions between them:

```js
function currentPhaseDose(phases, startDate) {
  if (!Array.isArray(phases) || !phases.length) return null;
  const week = pbCurrentCycleWeek(startDate);
  const phase = phases.find(ph => week >= ph.startWeek && week <= (ph.endWeek || Infinity));
  return phase ? phase.dose : phases[phases.length - 1].dose;
}

function renderDoseSchedule() {
  const el = document.getElementById('dose-schedule-content');
  if (!el) return;
  const protocol = lsGet('hrt_active_protocol_data', null);
  if (!protocol || !(protocol.compounds || []).length) {
    el.innerHTML = `<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:160px;gap:6px;text-align:center;"><i class="ti ti-calendar-off" style="font-size:28px;color:var(--text-muted);opacity:0.4;"></i><div style="color:var(--text-muted);">No active protocol</div><div style="font-size:11px;color:var(--text-muted);opacity:0.7;"><a href="#" onclick="nav('protocols');return false;" style="color:var(--primary-bright);">My Protocols →</a></div></div>`;
    return;
  }
  const startDate  = protocol.startDate || '';
  const today      = new Date();
  const DAY_NAMES  = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  const MON_NAMES  = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const todayLabel = `${DAY_NAMES[today.getDay()]} ${MON_NAMES[today.getMonth()]} ${today.getDate()}`;
  const trunc      = s => (s && s.length > 22) ? s.slice(0, 21) + '…' : (s || '');

  const compounds = protocol.compounds.map(raw => {
    const c    = normalizeCompound(raw);
    const dose = Array.isArray(raw.phases) ? currentPhaseDose(raw.phases, startDate) : c.dose;
    return { name: c.name, dose, unit: c.unit, freq: c.freq, dueToday: isDueOnDate(c.freq, startDate, today) };
  });

  // TODAY section
  let html = `<div style="font-size:11px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.05em;margin-bottom:6px;">Today · ${escHtml(todayLabel)}</div>`;
  for (const c of compounds) {
    const dot      = c.dueToday ? `<span style="color:var(--success);">●</span>` : `<span style="color:var(--text-muted);">○</span>`;
    const rowStyle = c.dueToday ? '' : 'opacity:0.5;';
    html += `<div style="display:flex;justify-content:space-between;gap:8px;${rowStyle}">${dot} <span style="flex:1;">${escHtml(trunc(c.name))}</span><span style="color:var(--text-muted);white-space:nowrap;">${escHtml(String(c.dose ?? ''))}${escHtml(c.unit)}</span></div>`;
  }

  // UPCOMING section
  const isNonDaily = c => { const f = Array.isArray(c.freq) ? '' : (c.freq || '').toUpperCase().trim(); return f !== 'ED' && f !== 'PWO'; };
  const nonDaily   = compounds.filter(isNonDaily);

  if (!nonDaily.length) {
    html += `<div style="color:var(--text-muted);font-size:11px;font-style:italic;margin-top:6px;">All compounds daily</div>`;
  } else {
    let upcomingHtml = '';
    let shown = 0;
    for (let i = 1; i <= 6 && shown < 5; i++) {
      const d   = new Date(today.getFullYear(), today.getMonth(), today.getDate() + i);
      const due = nonDaily.filter(c => isDueOnDate(c.freq, startDate, d));
      if (!due.length) continue;
      const label   = `${DAY_NAMES[d.getDay()]} ${d.getDate()}`;
      const abbrevs = due.map(c => escHtml(_abbrevCompound(c.name))).join(' · ');
      upcomingHtml += `<div style="color:var(--text-muted);font-size:11px;">${label} · ${abbrevs}</div>`;
      shown++;
    }
    if (upcomingHtml) {
      html += `<div style="font-size:11px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.05em;margin-top:10px;margin-bottom:4px;">Upcoming</div>${upcomingHtml}`;
    }
  }
  el.innerHTML = html;
}
```

- [ ] **Step 2: Wire `renderDoseSchedule()` into `renderCycleProgress`**

Find this block near the end of `renderCycleProgress` (approximately lines 2271–2277):

```js
  cycleCard.innerHTML = `
    <div style="font-size:10px;color:var(--green);margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em;">Today&#x27;s Injections</div>
    ${activeHtml}
    ${cycleEndBanner}
    ${upcomingHtml}
  `;
}
```

Replace with (add `renderDoseSchedule();` before the closing `}`):

```js
  cycleCard.innerHTML = `
    <div style="font-size:10px;color:var(--green);margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em;">Today&#x27;s Injections</div>
    ${activeHtml}
    ${cycleEndBanner}
    ${upcomingHtml}
  `;
  renderDoseSchedule();
}
```

- [ ] **Step 3: Verify**

```bash
grep -n 'renderDoseSchedule\|currentPhaseDose' index-v2.html
```

Expected output: 3 lines — `currentPhaseDose` definition, `renderDoseSchedule` definition, `renderDoseSchedule()` call inside `renderCycleProgress`.

- [ ] **Step 4: Manual smoke test**

Open `index-v2.html` in a browser with an active protocol set. Confirm:
- Dose Schedule card appears on the LEFT, Weight chart on the RIGHT
- TODAY section lists all compounds with green `●` for due-today and grey `○` for not-due
- If all compounds are ED/PWO → "All compounds daily" appears below the list
- If any compound is non-daily → UPCOMING section appears with day rows
- No console errors

- [ ] **Step 5: Commit**

```bash
git add index-v2.html
git commit -m "feat: add renderDoseSchedule with today/upcoming sections, wire into renderCycleProgress"
```

---
