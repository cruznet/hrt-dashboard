# Phased Protocol Builder — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the Protocol Builder so compounds have phase-based dosing (start week / end week / dose), support cycle-level metadata (length, start date, status), track mid-cycle modifications in a log, and surface the active cycle position on the Dashboard.

**Architecture:** All changes are confined to `index-v2.html` (single-file, no build system). Pure logic functions (normalizeProtocol, pbFreqToInjectionsPerWeek, phaseWeeklyTotal, buildWeekGrid) are added as standalone JS functions near their siblings. The Builder page gains a three-tab layout (Builder / Timeline / Log) via CSS display toggling. The Dashboard cycle card extends the existing `renderCycleProgress()`.

**Tech Stack:** Vanilla JS · HTML/CSS variables · localStorage · Python dev server (`python3 server.py` → `http://localhost:3000`)

## Global Constraints

- Do NOT split `index-v2.html` into multiple files
- Do NOT add a build system, package.json, or npm
- All colors must use existing CSS variables — no hardcoded hex values
- Font data values use `var(--font-data)` (JetBrains Mono)
- Do NOT rename `normalizeCompound()` — backward compat with v1 protocol data
- Do NOT use `c.weeklyDose` for weekly totals — always compute from `dose × pbFreqToInjectionsPerWeek(freq)`
- Phase `dose` field = **per-injection amount** (not weekly total); weekly total is always computed and shown as a hint
- Test harness: `tests/protocol-logic.html` — open in browser, no CLI runner needed
- Server: `cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard" && python3 server.py`

---

## File Map

| File | Action | What changes |
|---|---|---|
| `index-v2.html:3328–3341` | Modify | `pbFreqToInjectionsPerWeek()` — add PWO + array support |
| `index-v2.html:3793` | Modify | Add `normalizeProtocol()` after `normalizeCompound()` |
| `index-v2.html:3325` | Modify | Expand `pbState` with cycleLengthWeeks, startDate, status, modificationLog |
| `index-v2.html:3618` | Modify | COMPOUNDS array — add SLU-PP-332 |
| `index-v2.html:1206–1427` | Replace | `page-builder` HTML — tabbed layout, cycle settings, phase cards, remove-compound modal |
| `index-v2.html:3361–3542` | Replace | pbAddCompound, pbRender, pbAddPhase, pbRemovePhase, pbRemoveCompound, pbShowDayPicker |
| `index-v2.html:3544–3572` | Modify | `_pbDoSave()` — save new protocol shape, write modificationLog entries |
| `index-v2.html:2956–3003` | Modify | `renderCycleProgress()` — use startDate, show active compounds + upcoming |
| `index-v2.html` (new fns) | Add | `renderProtocolTimeline()`, `renderProtocolLog()`, `pbSwitchTab()` |
| `tests/protocol-logic.html` | Create | Lightweight browser test harness for pure logic functions |

---

## Task 1: Logic Foundation — pbFreqToInjectionsPerWeek + normalizeProtocol + test harness

**Files:**
- Modify: `index-v2.html:3328–3341`
- Modify: `index-v2.html:3793` (add normalizeProtocol after normalizeCompound)
- Create: `tests/protocol-logic.html`

**Interfaces:**
- Produces: `pbFreqToInjectionsPerWeek(freq)` — accepts string or `string[]`, returns number
- Produces: `normalizeProtocol(p)` — accepts old or new protocol shape, always returns new shape
- Produces: `phaseWeeklyTotal(phase, freq)` — returns `phase.dose * pbFreqToInjectionsPerWeek(freq)`

---

- [ ] **Step 1: Create test harness**

Create `tests/protocol-logic.html`:

```html
<!DOCTYPE html>
<html>
<head><title>Protocol Logic Tests</title>
<style>
  body { font-family: monospace; padding: 20px; background: #0f1117; color: #f1f5f9; }
  .pass { color: #10B981; } .fail { color: #EF4444; }
  h2 { color: #6366F1; margin-top: 24px; }
</style>
</head>
<body>
<h1>Protocol Logic Tests</h1>
<div id="results"></div>
<script>
const results = document.getElementById('results');
let passed = 0, failed = 0;
function assert(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) passed++; else failed++;
  results.innerHTML += `<div class="${ok ? 'pass' : 'fail'}">${ok ? '✓' : '✗'} ${label}${ok ? '' : ` — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`}</div>`;
}
function section(name) { results.innerHTML += `<h2>${name}</h2>`; }
</script>
<!-- paste functions under test here during development -->
<script>
// ── pbFreqToInjectionsPerWeek ──
function pbFreqToInjectionsPerWeek(freq) {
  if (Array.isArray(freq)) return freq.length;
  const f = (freq || '').toUpperCase().trim();
  if (f === 'ED')       return 7;
  if (f === 'EOD')      return 3.5;
  if (f === 'E3D')      return 7 / 3;
  if (f === 'E3.5D' || f === '2X/WK') return 2;
  if (f === 'E4D')      return 7 / 4;
  if (f === 'E5D')      return 7 / 5;
  if (f === '3X/WK')   return 3;
  if (f === 'WEEKLY')   return 1;
  if (f === 'BI-WKLY')  return 0.5;
  if (f === 'MONTHLY')  return 7 / 30;
  if (f === 'PWO')      return 7;
  return 1;
}

section('pbFreqToInjectionsPerWeek');
assert('ED → 7',                       pbFreqToInjectionsPerWeek('ED'), 7);
assert('EOD → 3.5',                    pbFreqToInjectionsPerWeek('EOD'), 3.5);
assert('E3.5D → 2',                    pbFreqToInjectionsPerWeek('E3.5D'), 2);
assert('Weekly → 1',                   pbFreqToInjectionsPerWeek('Weekly'), 1);
assert('PWO → 7',                      pbFreqToInjectionsPerWeek('PWO'), 7);
assert('array [Mon,Thu] → 2',          pbFreqToInjectionsPerWeek(['Mon','Thu']), 2);
assert('array [Mon,Wed,Fri] → 3',      pbFreqToInjectionsPerWeek(['Mon','Wed','Fri']), 3);
assert('empty string → 1',             pbFreqToInjectionsPerWeek(''), 1);
assert('null → 1',                     pbFreqToInjectionsPerWeek(null), 1);

// ── normalizeProtocol ──
function normalizeProtocol(p) {
  if (!p) return p;
  const weeks = parseInt(p.cycleLengthWeeks || p.weeks) || 12;
  const compounds = (p.compounds || []).map(c => {
    if (Array.isArray(c.phases)) return c;
    const dose = parseFloat(c.perInjection || c.dose) || 0;
    return {
      name: c.name || '',
      cat: c.cat || '',
      unit: c.unit || '',
      freq: c.freq || 'Weekly',
      phases: [{ startWeek: 1, endWeek: weeks, dose }]
    };
  });
  return {
    ...p,
    cycleLengthWeeks: weeks,
    startDate: p.startDate || '',
    status: p.status || 'planning',
    compounds,
    modificationLog: p.modificationLog || []
  };
}

section('normalizeProtocol — migration');
const old = { name: 'Test', weeks: '12', saved_at: '2026-01-01', phase: 'blast',
  compounds: [{ name: 'Test E', dose: 100, unit: 'mg', freq: 'E3.5D', perInjection: 100 }] };
const migrated = normalizeProtocol(old);
assert('cycleLengthWeeks set from weeks',  migrated.cycleLengthWeeks, 12);
assert('status defaults to planning',       migrated.status, 'planning');
assert('modificationLog defaults to []',    migrated.modificationLog, []);
assert('compound gains phases array',       Array.isArray(migrated.compounds[0].phases), true);
assert('phase startWeek = 1',              migrated.compounds[0].phases[0].startWeek, 1);
assert('phase endWeek = cycleLengthWeeks', migrated.compounds[0].phases[0].endWeek, 12);
assert('phase dose from perInjection',     migrated.compounds[0].phases[0].dose, 100);

section('normalizeProtocol — already new shape');
const newP = { name: 'N', cycleLengthWeeks: 16, status: 'active', startDate: '2026-06-01',
  compounds: [{ name: 'Primo', cat: 'AAS', unit: 'mg', freq: 'Weekly',
    phases: [{ startWeek: 1, endWeek: 16, dose: 200 }] }],
  modificationLog: [] };
const noop = normalizeProtocol(newP);
assert('new shape passes through unchanged', noop.compounds[0].phases[0].dose, 200);
assert('cycleLengthWeeks preserved',         noop.cycleLengthWeeks, 16);

// ── phaseWeeklyTotal ──
function phaseWeeklyTotal(phase, freq) {
  return parseFloat((phase.dose * pbFreqToInjectionsPerWeek(freq)).toFixed(2));
}

section('phaseWeeklyTotal');
assert('100mg E3.5D → 200mg/wk',  phaseWeeklyTotal({ dose: 100 }, 'E3.5D'), 200);
assert('6IU ED → 42IU/wk',        phaseWeeklyTotal({ dose: 6 }, 'ED'), 42);
assert('50mg Mon,Thu → 100mg/wk', phaseWeeklyTotal({ dose: 50 }, ['Mon','Thu']), 100);

// ── summary ──
results.innerHTML += `<h2 style="color:${failed ? '#EF4444' : '#10B981'}">${passed} passed, ${failed} failed</h2>`;
</script>
</body>
</html>
```

- [ ] **Step 2: Open test harness in browser and verify all tests pass**

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard" && python3 server.py
```

Open: `http://localhost:3000/tests/protocol-logic.html`

Expected: Green "13 passed, 0 failed" heading.

- [ ] **Step 3: Replace pbFreqToInjectionsPerWeek in index-v2.html**

Find lines 3328–3341 and replace the function body:

```js
function pbFreqToInjectionsPerWeek(freq) {
  if (Array.isArray(freq)) return freq.length;
  const f = (freq || '').toUpperCase().trim();
  if (f === 'ED')       return 7;
  if (f === 'EOD')      return 3.5;
  if (f === 'E3D')      return 7 / 3;
  if (f === 'E3.5D' || f === '2X/WK') return 2;
  if (f === 'E4D')      return 7 / 4;
  if (f === 'E5D')      return 7 / 5;
  if (f === '3X/WK')   return 3;
  if (f === 'WEEKLY')   return 1;
  if (f === 'BI-WKLY')  return 0.5;
  if (f === 'MONTHLY')  return 7 / 30;
  if (f === 'PWO')      return 7;
  return 1;
}
```

- [ ] **Step 4: Add normalizeProtocol and phaseWeeklyTotal after normalizeCompound (line ~3805)**

Insert immediately after the closing `}` of `normalizeCompound`:

```js
function normalizeProtocol(p) {
  if (!p) return p;
  const weeks = parseInt(p.cycleLengthWeeks || p.weeks) || 12;
  const compounds = (p.compounds || []).map(c => {
    if (Array.isArray(c.phases)) return c;
    const dose = parseFloat(c.perInjection || c.dose) || 0;
    return {
      name: c.name || '',
      cat: c.cat || '',
      unit: c.unit || '',
      freq: c.freq || 'Weekly',
      phases: [{ startWeek: 1, endWeek: weeks, dose }]
    };
  });
  return {
    ...p,
    cycleLengthWeeks: weeks,
    startDate: p.startDate || '',
    status: p.status || 'planning',
    compounds,
    modificationLog: p.modificationLog || []
  };
}

function phaseWeeklyTotal(phase, freq) {
  return parseFloat((phase.dose * pbFreqToInjectionsPerWeek(freq)).toFixed(2));
}
```

- [ ] **Step 5: Update lsGet('hrt_protocols') call sites to run normalizeProtocol**

There are three call sites that read protocols. Each needs to map through `normalizeProtocol`:

In `renderProtocolsPage` (line ~3442):
```js
const saved = lsGet('hrt_protocols', []).map(normalizeProtocol);
```

In `editProtocol` (line ~3519):
```js
const p = normalizeProtocol(saved[index]);
```

In `setActiveProtocol` (line ~3487):
```js
const p = normalizeProtocol(saved[index]);
```

- [ ] **Step 6: Verify migration in browser**

With the server running, open `http://localhost:3000/index-v2.html`. Open browser console. Run:
```js
localStorage.setItem('hrt_protocols', JSON.stringify([{
  name: 'Old Format', weeks: '12', saved_at: new Date().toISOString(), phase: 'blast',
  compounds: [{ name: 'Test E', dose: 100, unit: 'mg', freq: 'E3.5D', perInjection: 100 }]
}]));
location.reload();
```

Navigate to My Protocols. Expected: protocol card renders without JS errors. Open console and run `lsGet('hrt_protocols', []).map(normalizeProtocol)[0].compounds[0].phases` — expected: `[{startWeek:1, endWeek:12, dose:100}]`.

- [ ] **Step 7: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat(protocol): add normalizeProtocol, phaseWeeklyTotal, extend pbFreqToInjectionsPerWeek for arrays/PWO"
```

---

## Task 2: SLU-PP-332 — COMPOUNDS Library Addition

**Files:**
- Modify: `index-v2.html:3618+` (COMPOUNDS array, end of list)
- Modify: `index-v2.html:1206+` (compound dropdown `<select id="pb-add-select">`)

**Interfaces:**
- Produces: SLU-PP-332 entry visible in Compound Library page and Protocol Builder dropdown

---

- [ ] **Step 1: Add SLU-PP-332 to COMPOUNDS array**

In the COMPOUNDS array (near line 3667, after the last SARM entry), find a comment separator for Other/Research compounds and add:

```js
  // ── Research / Metabolic ──
  { name: 'SLU-PP-332', cat: 'Research/Metabolic', hl: '~4 hrs', dose: '10–50mg/day', ai: 'No', dht: 'No', note: 'ERRα/γ agonist — exercise mimetic, research compound' },
```

- [ ] **Step 2: Add SLU-PP-332 to the builder dropdown**

In `page-builder` HTML, find the `<select id="pb-add-select">` dropdown. Add an optgroup (or find an existing "Support / Other" optgroup) and include:

```html
<optgroup label="── Research / Metabolic ──">
  <option>SLU-PP-332</option>
</optgroup>
```

- [ ] **Step 3: Verify in browser**

Open `http://localhost:3000/index-v2.html`. Navigate to Compound Library — verify SLU-PP-332 appears in search results with correct category. Navigate to Protocol Builder → Add Compound dropdown — verify SLU-PP-332 appears.

- [ ] **Step 4: Commit**

```bash
git add index-v2.html
git commit -m "feat(compounds): add SLU-PP-332 to library and builder dropdown"
```

---

## Task 3: Protocol Builder HTML — Tabbed Layout + Cycle Settings

**Files:**
- Modify: `index-v2.html:1206–1427` (replace entire `<section id="page-builder">` block)

**Interfaces:**
- Produces: `#pb-tab-builder`, `#pb-tab-timeline`, `#pb-tab-log` tab buttons
- Produces: `#pb-cycle-weeks`, `#pb-cycle-start-date`, `#pb-cycle-status` inputs
- Produces: `#pb-compounds-list` (unchanged ID, retains JS hook)
- Produces: `#pb-timeline-grid` container for Task 7
- Produces: `#pb-log-list` container for Task 7
- Produces: `#pb-remove-modal` — remove compound modal

---

- [ ] **Step 1: Replace page-builder HTML**

Replace the entire `<section class="page" id="page-builder">` block (lines 1206–1427) with:

```html
    <!-- ── PROTOCOL BUILDER PAGE ── -->
    <section class="page" id="page-builder">
      <div class="section-heading">Protocol Builder</div>

      <!-- Tab bar -->
      <div style="display:flex;gap:0;border-bottom:1px solid var(--border);margin-bottom:18px;">
        <button id="pb-tab-builder" class="pb-tab pb-tab-active" onclick="pbSwitchTab('builder')">Builder</button>
        <button id="pb-tab-timeline" class="pb-tab" onclick="pbSwitchTab('timeline')">Timeline</button>
        <button id="pb-tab-log" class="pb-tab" onclick="pbSwitchTab('log')">Log</button>
      </div>

      <!-- ── BUILDER TAB ── -->
      <div id="pb-panel-builder">
        <div class="grid-1-2">
          <div>
            <div class="card" style="margin-bottom:14px;">
              <div class="card-title">Cycle Settings</div>
              <div class="form-group">
                <label class="form-label">Protocol Name</label>
                <input type="text" class="form-input" id="pb-name" placeholder="e.g. Summer Lean Bulk 2026">
              </div>
              <div class="form-row">
                <div class="form-group">
                  <label class="form-label">Phase</label>
                  <select class="form-select" id="pb-phase">
                    <option value="cruise">Cruise / TRT</option>
                    <option value="bulk">Bulk</option>
                    <option value="cut">Cut</option>
                    <option value="rebound">Rebound / PCT</option>
                  </select>
                </div>
                <div class="form-group">
                  <label class="form-label">Total Weeks</label>
                  <input type="number" class="form-input" id="pb-cycle-weeks" value="16" min="1" max="52" oninput="pbOnWeeksChange()">
                </div>
              </div>
              <div class="form-row">
                <div class="form-group">
                  <label class="form-label">Start Date <span style="color:var(--text-muted);font-size:11px;">(optional)</span></label>
                  <input type="date" class="form-input" id="pb-cycle-start-date">
                </div>
                <div class="form-group">
                  <label class="form-label">Status</label>
                  <select class="form-select" id="pb-cycle-status">
                    <option value="planning">Planning</option>
                    <option value="active">Active</option>
                    <option value="completed">Completed</option>
                  </select>
                </div>
              </div>
              <div class="form-row">
                <div class="form-group">
                  <label class="form-label">Experience Level</label>
                  <select class="form-select" id="pb-exp">
                    <option value="beginner">Beginner</option>
                    <option value="intermediate" selected>Intermediate</option>
                    <option value="advanced">Advanced</option>
                  </select>
                </div>
              </div>
              <div class="form-group">
                <label class="form-label">Notes</label>
                <textarea class="form-input" id="pb-notes" rows="2" placeholder="Goals, context, diet strategy..."></textarea>
              </div>
            </div>

            <div class="card">
              <div class="card-title">Add Compound</div>
              <div class="form-group">
                <label class="form-label">Compound</label>
                <select class="form-select" id="pb-add-select" onchange="pbOnCompoundSelect()">
                  <option value="">Select to add...</option>
                  <optgroup label="── Testosterone ──">
                    <option>Testosterone Suspension</option>
                    <option>Testosterone Propionate</option>
                    <option>Testosterone Phenylpropionate</option>
                    <option>Testosterone Enanthate</option>
                    <option>Testosterone Cypionate</option>
                    <option>Sustanon (Mixed Esters)</option>
                    <option>Testosterone Undecanoate</option>
                  </optgroup>
                  <optgroup label="── 19-nor ──">
                    <option>Nandrolone Phenylpropionate (NPP)</option>
                    <option>Nandrolone Decanoate (Deca)</option>
                    <option>Trenbolone Acetate</option>
                    <option>Trenbolone Enanthate</option>
                    <option>Trenbolone Hexahydrobenzylcarbonate (Parabolan)</option>
                  </optgroup>
                  <optgroup label="── Anabolics / Injectables ──">
                    <option>Boldenone Undecylenate (EQ)</option>
                    <option>Boldenone Cypionate</option>
                    <option>DHB (Dihydroboldenone Cypionate)</option>
                    <option>Masteron Propionate</option>
                    <option>Masteron Enanthate</option>
                    <option>Primobolan (Methenolone E)</option>
                    <option>Stanozolol Depot (Winstrol Inj)</option>
                  </optgroup>
                  <optgroup label="── Orals ──">
                    <option>Methandrostenolone (Dianabol)</option>
                    <option>Oxandrolone (Anavar)</option>
                    <option>Stanozolol (Winstrol Oral)</option>
                    <option>Oxymetholone (Anadrol)</option>
                    <option>Turinabol</option>
                    <option>Fluoxymesterone (Halotestin)</option>
                    <option>Mesterolone (Proviron)</option>
                    <option>Primobolan Oral (Methenolone Acetate)</option>
                  </optgroup>
                  <optgroup label="── AI / SERM ──">
                    <option>Anastrozole</option>
                    <option>Exemestane</option>
                    <option>Letrozole</option>
                    <option>HCG</option>
                    <option>Enclomiphene</option>
                  </optgroup>
                  <optgroup label="── Peptides / GH ──">
                    <option>Growth Hormone (rHGH)</option>
                    <option>BPC-157</option>
                    <option>TB-500</option>
                  </optgroup>
                  <optgroup label="── GLP-1 ──">
                    <option>Semaglutide</option>
                    <option>Tirzepatide</option>
                    <option>Retatrutide</option>
                  </optgroup>
                  <optgroup label="── SARMs ──">
                    <option>Ostarine (MK-2866)</option>
                    <option>Ligandrol (LGD-4033)</option>
                    <option>RAD-140 (Testolone)</option>
                    <option>YK-11</option>
                    <option>Andarine (S4)</option>
                    <option>S23</option>
                  </optgroup>
                  <optgroup label="── Research / Metabolic ──">
                    <option>SLU-PP-332</option>
                  </optgroup>
                </select>
              </div>
              <div class="form-row">
                <div class="form-group">
                  <label class="form-label">Unit</label>
                  <select class="form-select" id="pb-unit">
                    <option value="mg">mg</option>
                    <option value="IU">IU</option>
                    <option value="mcg">mcg</option>
                    <option value="mL">mL</option>
                  </select>
                </div>
                <div class="form-group">
                  <label class="form-label">Frequency</label>
                  <select class="form-select" id="pb-freq" onchange="pbOnFreqChange()">
                    <option value="ED">ED (daily)</option>
                    <option value="EOD">EOD</option>
                    <option value="E3D">E3D</option>
                    <option value="E3.5D" selected>E3.5D</option>
                    <option value="E4D">E4D</option>
                    <option value="E5D">E5D</option>
                    <option value="2x/wk">2x/wk</option>
                    <option value="3x/wk">3x/wk</option>
                    <option value="Weekly">Weekly</option>
                    <option value="Bi-Wkly">Bi-Weekly</option>
                    <option value="Monthly">Monthly</option>
                    <option value="PWO">PWO</option>
                    <option value="custom-days">Specific days…</option>
                  </select>
                </div>
              </div>
              <!-- Weekday picker — hidden unless "Specific days…" chosen -->
              <div id="pb-day-picker" style="display:none;margin-bottom:10px;">
                <label class="form-label">Select days</label>
                <div style="display:flex;gap:6px;flex-wrap:wrap;">
                  <button type="button" class="pb-day-btn" data-day="Mon" onclick="pbToggleDay(this)">Mon</button>
                  <button type="button" class="pb-day-btn" data-day="Tue" onclick="pbToggleDay(this)">Tue</button>
                  <button type="button" class="pb-day-btn" data-day="Wed" onclick="pbToggleDay(this)">Wed</button>
                  <button type="button" class="pb-day-btn" data-day="Thu" onclick="pbToggleDay(this)">Thu</button>
                  <button type="button" class="pb-day-btn" data-day="Fri" onclick="pbToggleDay(this)">Fri</button>
                  <button type="button" class="pb-day-btn" data-day="Sat" onclick="pbToggleDay(this)">Sat</button>
                  <button type="button" class="pb-day-btn" data-day="Sun" onclick="pbToggleDay(this)">Sun</button>
                </div>
              </div>
              <div class="form-row">
                <div class="form-group">
                  <label class="form-label">Start Week</label>
                  <input type="number" class="form-input" id="pb-start-week" value="1" min="1">
                </div>
                <div class="form-group">
                  <label class="form-label">End Week</label>
                  <input type="number" class="form-input" id="pb-end-week" value="16" min="1">
                </div>
                <div class="form-group">
                  <label class="form-label">Dose (per injection)</label>
                  <input type="number" class="form-input" id="pb-dose" placeholder="200" step="0.1" oninput="pbUpdateDoseHint()">
                </div>
              </div>
              <div id="pb-dose-hint" style="font-size:11px;color:var(--text-muted);margin-bottom:8px;min-height:16px;"></div>
              <button class="btn-primary" style="width:100%;" onclick="pbAddCompound()">Add to Protocol</button>
            </div>
          </div>

          <div>
            <div class="card" style="margin-bottom:14px;">
              <div class="card-title">Compounds</div>
              <div id="pb-compounds-list" style="min-height:60px;">
                <div style="color:var(--text-muted);font-size:12px;">No compounds added yet.</div>
              </div>
            </div>

            <div class="card">
              <div class="card-title">Actions</div>
              <div style="display:flex;gap:8px;flex-wrap:wrap;">
                <button class="btn-primary" onclick="pbSave()">Save Protocol</button>
                <button class="btn-secondary" onclick="pbSaveAndActivate()" style="color:var(--teal);border-color:var(--teal);">Set Active</button>
                <button class="btn-secondary" onclick="pbExportJson()">Export JSON</button>
                <button class="btn-secondary" onclick="pbReset()">Reset</button>
              </div>
              <div id="pb-save-status" style="font-size:12px;color:var(--green);margin-top:8px;display:none;"></div>
            </div>
          </div>
        </div>
      </div>

      <!-- ── TIMELINE TAB ── -->
      <div id="pb-panel-timeline" style="display:none;">
        <div class="card">
          <div class="card-title">Week-by-Week Timeline</div>
          <div id="pb-timeline-grid" style="overflow-x:auto;">
            <div style="color:var(--text-muted);font-size:12px;">Build a protocol in the Builder tab to see the timeline.</div>
          </div>
        </div>
      </div>

      <!-- ── LOG TAB ── -->
      <div id="pb-panel-log" style="display:none;">
        <div class="card">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
            <div class="card-title" style="margin:0;">Modification Log</div>
            <button class="btn-secondary" style="font-size:12px;padding:5px 12px;" onclick="pbAddNote()">+ Add Note</button>
          </div>
          <div id="pb-log-list">
            <div style="color:var(--text-muted);font-size:12px;">No modifications recorded yet.</div>
          </div>
        </div>
      </div>

      <!-- ── REMOVE COMPOUND MODAL ── -->
      <div id="pb-remove-modal" style="display:none;position:fixed;inset:0;background:rgba(0,0,0,0.7);z-index:1000;align-items:center;justify-content:center;">
        <div class="card" style="width:360px;max-width:90vw;">
          <div class="card-title">Remove Compound</div>
          <p id="pb-remove-modal-title" style="font-size:13px;color:var(--text-secondary);margin-bottom:14px;"></p>
          <div class="form-group">
            <label class="form-label">At which week?</label>
            <input type="number" class="form-input" id="pb-remove-week" min="1" placeholder="e.g. 6">
          </div>
          <div class="form-group">
            <label class="form-label">Reason</label>
            <textarea class="form-input" id="pb-remove-reason" rows="2" placeholder="e.g. High BP, side effects..."></textarea>
          </div>
          <div style="display:flex;gap:8px;margin-top:12px;">
            <button class="btn-primary" style="background:var(--red);border-color:var(--red);" onclick="pbConfirmRemove()">Remove</button>
            <button class="btn-secondary" onclick="pbCloseRemoveModal()">Cancel</button>
          </div>
        </div>
      </div>
    </section>
```

- [ ] **Step 2: Add tab + day-picker styles** (inside the existing `<style>` block)

Find the closing `</style>` tag and insert before it:

```css
.pb-tab { background:none;border:none;border-bottom:2px solid transparent;color:var(--text-muted);cursor:pointer;font-size:13px;font-weight:500;padding:8px 18px;transition:color .15s,border-color .15s; }
.pb-tab:hover { color:var(--text-secondary); }
.pb-tab.pb-tab-active { color:var(--primary-bright);border-bottom-color:var(--primary-bright); }
.pb-day-btn { background:var(--bg-card);border:1px solid var(--border);border-radius:4px;color:var(--text-secondary);cursor:pointer;font-size:12px;padding:4px 10px;transition:all .15s; }
.pb-day-btn.selected { background:var(--primary-dim);border-color:var(--primary-border);color:var(--primary-bright); }
```

- [ ] **Step 3: Verify in browser**

Open `http://localhost:3000/index-v2.html`. Navigate to Protocol Builder. Expected:
- Three tab buttons visible: Builder / Timeline / Log
- Builder tab is active by default
- Cycle Settings card shows: Name, Phase, Total Weeks, Start Date, Status, Experience, Notes
- Add Compound card shows: Compound dropdown, Unit, Frequency (with "Specific days…" option), Start Week, End Week, Dose
- No JS errors in console

- [ ] **Step 4: Commit**

```bash
git add index-v2.html
git commit -m "feat(protocol): replace builder HTML with tabbed layout, cycle settings, weekday picker scaffold"
```

---

## Task 4: pbState Expansion + Phase Management JS

**Files:**
- Modify: `index-v2.html:3325` (pbState definition)
- Modify: `index-v2.html:3361–3440` (pbAddCompound, pbRender, pbUpdateDoseHint + new functions)

**Interfaces:**
- Consumes: `pbFreqToInjectionsPerWeek(freq)` from Task 1
- Consumes: `phaseWeeklyTotal(phase, freq)` from Task 1
- Produces: `pbState` with shape `{ name, phase, cycleLengthWeeks, startDate, status, exp, notes, compounds, modificationLog }`
- Produces: `pbSwitchTab(tab)` — shows/hides panels
- Produces: `pbOnFreqChange()` — shows/hides day picker
- Produces: `pbToggleDay(btn)` — toggles weekday selection
- Produces: `pbGetSelectedDays()` — returns `string[]` of selected days
- Produces: `pbOnCompoundSelect()` — pre-fills unit from COMPOUNDS
- Produces: `pbAddCompound()` — adds compound with initial phase to pbState
- Produces: `pbAddPhase(compoundIndex)` — appends a new phase row to a compound
- Produces: `pbRemovePhase(compoundIndex, phaseIndex)` — removes one phase
- Produces: `pbOpenRemoveModal(compoundIndex)` — opens the removal modal
- Produces: `pbCloseRemoveModal()` — hides modal
- Produces: `pbConfirmRemove()` — removes compound + logs event
- Produces: `pbRender()` — renders compound cards with phases
- Produces: `pbOnWeeksChange()` — syncs end-week input default + optionally extends phases

---

- [ ] **Step 1: Replace pbState definition (line 3325)**

```js
let pbState = {
  name: '', phase: 'cruise', cycleLengthWeeks: 16,
  startDate: '', status: 'planning', exp: 'intermediate',
  notes: '', compounds: [], modificationLog: []
};
let _pbRemoveTargetIndex = -1;
```

- [ ] **Step 2: Replace pbUpdateDoseHint**

```js
function pbUpdateDoseHint() {
  const hint  = document.getElementById('pb-dose-hint');
  const dose  = parseFloat(document.getElementById('pb-dose').value);
  const unit  = document.getElementById('pb-unit').value;
  const freq  = pbGetCurrentFreq();
  if (!hint) return;
  if (!dose || isNaN(dose)) { hint.textContent = 'Enter per-injection dose.'; return; }
  const weekly = phaseWeeklyTotal({ dose }, freq);
  const freqLabel = Array.isArray(freq) ? freq.join(', ') : freq;
  hint.innerHTML = `→ <span style="color:var(--primary-bright);font-family:var(--font-data);">${weekly}${unit}/wk</span> at ${freqLabel}`;
}
```

- [ ] **Step 3: Add helper functions for freq picker and compound select**

```js
function pbSwitchTab(tab) {
  ['builder','timeline','log'].forEach(t => {
    document.getElementById(`pb-panel-${t}`).style.display = t === tab ? '' : 'none';
    document.getElementById(`pb-tab-${t}`).classList.toggle('pb-tab-active', t === tab);
  });
  if (tab === 'timeline') renderProtocolTimeline();
  if (tab === 'log')      renderProtocolLog();
}

function pbOnFreqChange() {
  const val = document.getElementById('pb-freq').value;
  const picker = document.getElementById('pb-day-picker');
  picker.style.display = val === 'custom-days' ? '' : 'none';
  if (val !== 'custom-days') {
    document.querySelectorAll('.pb-day-btn').forEach(b => b.classList.remove('selected'));
  }
  pbUpdateDoseHint();
}

function pbToggleDay(btn) {
  btn.classList.toggle('selected');
  pbUpdateDoseHint();
}

function pbGetSelectedDays() {
  return [...document.querySelectorAll('.pb-day-btn.selected')].map(b => b.dataset.day);
}

function pbGetCurrentFreq() {
  const sel = document.getElementById('pb-freq').value;
  if (sel === 'custom-days') {
    const days = pbGetSelectedDays();
    return days.length ? days : 'ED';
  }
  return sel;
}

function pbOnCompoundSelect() {
  const name = document.getElementById('pb-add-select').value;
  if (!name) return;
  const match = COMPOUNDS.find(c => c.name === name);
  if (!match) return;
  // Pre-fill unit from COMPOUNDS library
  const unitEl = document.getElementById('pb-unit');
  if (match.dose) {
    const unitGuess = match.dose.includes('IU') ? 'IU' : match.dose.includes('mcg') ? 'mcg' : 'mg';
    if ([...unitEl.options].some(o => o.value === unitGuess)) unitEl.value = unitGuess;
  }
}

function pbOnWeeksChange() {
  const weeks = parseInt(document.getElementById('pb-cycle-weeks').value) || 16;
  pbState.cycleLengthWeeks = weeks;
  // Sync end-week default
  const endWk = document.getElementById('pb-end-week');
  if (endWk && parseInt(endWk.value) > weeks) endWk.value = weeks;
}
```

- [ ] **Step 4: Replace pbAddCompound**

```js
function pbAddCompound() {
  const name      = document.getElementById('pb-add-select').value;
  const unit      = document.getElementById('pb-unit').value;
  const freq      = pbGetCurrentFreq();
  const dose      = parseFloat(document.getElementById('pb-dose').value);
  const startWeek = parseInt(document.getElementById('pb-start-week').value) || 1;
  const endWeek   = parseInt(document.getElementById('pb-end-week').value) || pbState.cycleLengthWeeks;
  if (!name || !dose) return;
  const match = COMPOUNDS.find(c => c.name === name);
  pbState.compounds.push({
    name,
    cat: match?.cat || '',
    unit,
    freq,
    phases: [{ startWeek, endWeek, dose }]
  });
  document.getElementById('pb-add-select').value = '';
  document.getElementById('pb-dose').value = '';
  document.getElementById('pb-dose-hint').textContent = '';
  pbRender();
}
```

- [ ] **Step 5: Add pbAddPhase, pbRemovePhase, pbOpenRemoveModal, pbCloseRemoveModal, pbConfirmRemove**

```js
function pbAddPhase(ci) {
  const c = pbState.compounds[ci];
  const lastPhase = c.phases[c.phases.length - 1];
  const newStart = Math.min(lastPhase.endWeek + 1, pbState.cycleLengthWeeks);
  c.phases.push({ startWeek: newStart, endWeek: pbState.cycleLengthWeeks, dose: lastPhase.dose });
  pbRender();
}

function pbRemovePhase(ci, pi) {
  if (pbState.compounds[ci].phases.length <= 1) return; // must keep at least one phase
  pbState.compounds[ci].phases.splice(pi, 1);
  pbRender();
}

function pbOpenRemoveModal(ci) {
  _pbRemoveTargetIndex = ci;
  const name = pbState.compounds[ci].name;
  document.getElementById('pb-remove-modal-title').textContent = `Remove "${name}" from this protocol?`;
  document.getElementById('pb-remove-week').value = pbState.cycleLengthWeeks;
  document.getElementById('pb-remove-reason').value = '';
  document.getElementById('pb-remove-modal').style.display = 'flex';
}

function pbCloseRemoveModal() {
  document.getElementById('pb-remove-modal').style.display = 'none';
  _pbRemoveTargetIndex = -1;
}

function pbConfirmRemove() {
  const ci = _pbRemoveTargetIndex;
  if (ci < 0 || ci >= pbState.compounds.length) { pbCloseRemoveModal(); return; }
  const week   = parseInt(document.getElementById('pb-remove-week').value) || pbState.cycleLengthWeeks;
  const reason = document.getElementById('pb-remove-reason').value.trim();
  const name   = pbState.compounds[ci].name;
  pbState.modificationLog.push({ week, type: 'removal', compound: name, note: reason, ts: Date.now() });
  pbState.compounds.splice(ci, 1);
  pbCloseRemoveModal();
  pbRender();
}
```

- [ ] **Step 6: Replace pbRender**

```js
function pbRender() {
  const list = document.getElementById('pb-compounds-list');
  if (!list) return;
  if (!pbState.compounds.length) {
    list.innerHTML = '<div style="color:var(--text-muted);font-size:12px;">No compounds added yet.</div>';
    return;
  }
  list.innerHTML = pbState.compounds.map((c, ci) => {
    const freqLabel = Array.isArray(c.freq) ? c.freq.join(', ') : c.freq;
    const phasesHtml = c.phases.map((ph, pi) => {
      const weekly = phaseWeeklyTotal(ph, c.freq);
      return `<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;font-size:12px;">
        <span style="color:var(--text-muted);min-width:28px;">Wk</span>
        <input type="number" value="${ph.startWeek}" min="1" max="${pbState.cycleLengthWeeks}" style="width:52px;" class="form-input" style="padding:3px 6px;font-size:12px;" onchange="pbState.compounds[${ci}].phases[${pi}].startWeek=parseInt(this.value)||1">
        <span style="color:var(--text-muted);">–</span>
        <input type="number" value="${ph.endWeek}" min="1" max="${pbState.cycleLengthWeeks}" style="width:52px;" class="form-input" onchange="pbState.compounds[${ci}].phases[${pi}].endWeek=parseInt(this.value)||1">
        <input type="number" value="${ph.dose}" min="0" step="0.1" style="width:70px;" class="form-input" onchange="pbState.compounds[${ci}].phases[${pi}].dose=parseFloat(this.value)||0;pbRender()" placeholder="dose">
        <span style="color:var(--text-muted);">${c.unit}</span>
        <span style="color:var(--text-muted);font-size:11px;">(${weekly}${c.unit}/wk)</span>
        ${c.phases.length > 1 ? `<button onclick="pbRemovePhase(${ci},${pi})" style="background:none;border:none;color:var(--red);cursor:pointer;font-size:14px;padding:0;">×</button>` : ''}
      </div>`;
    }).join('');
    return `<div style="border:1px solid var(--border);border-radius:6px;padding:12px;margin-bottom:10px;">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
        <div>
          <span style="font-size:13px;font-weight:600;color:var(--text-primary);">${c.name}</span>
          <span style="margin-left:8px;font-size:11px;color:var(--text-muted);">${freqLabel}</span>
        </div>
        <div style="display:flex;gap:6px;">
          <button class="btn-secondary" style="font-size:11px;padding:3px 10px;" onclick="pbAddPhase(${ci})">+ Phase</button>
          <button class="btn-secondary" style="font-size:11px;padding:3px 10px;color:var(--red);border-color:var(--red);" onclick="pbOpenRemoveModal(${ci})">Remove</button>
        </div>
      </div>
      ${phasesHtml}
    </div>`;
  }).join('');
}
```

- [ ] **Step 7: Update editProtocol to load new pbState fields**

Find `function editProtocol(index)` (line ~3518). Replace the pre-fill section:

```js
function editProtocol(index) {
  const saved = lsGet('hrt_protocols', []).map(normalizeProtocol);
  const p = saved[index];
  if (!p) return;

  document.getElementById('pb-name').value              = p.name || '';
  document.getElementById('pb-phase').value             = p.phase || 'cruise';
  document.getElementById('pb-cycle-weeks').value       = p.cycleLengthWeeks || p.weeks || 16;
  document.getElementById('pb-cycle-start-date').value  = p.startDate || '';
  document.getElementById('pb-cycle-status').value      = p.status || 'planning';
  document.getElementById('pb-exp').value               = p.exp || 'intermediate';
  document.getElementById('pb-notes').value             = p.notes || '';

  pbState.cycleLengthWeeks = p.cycleLengthWeeks || parseInt(p.weeks) || 16;
  pbState.startDate        = p.startDate || '';
  pbState.status           = p.status || 'planning';
  pbState.compounds        = p.compounds || [];
  pbState.modificationLog  = p.modificationLog || [];
  pbEditIndex = index;

  pbRender();
  nav('builder');
  pbSwitchTab('builder');
  const st = document.getElementById('pb-save-status');
  if (st) { st.textContent = `Editing "${p.name}" — save to update.`; st.style.color = 'var(--amber)'; st.style.display = 'block'; }
}
```

- [ ] **Step 8: Update pbReset**

```js
function pbReset() {
  pbState = { name:'', phase:'cruise', cycleLengthWeeks:16, startDate:'', status:'planning', exp:'intermediate', notes:'', compounds:[], modificationLog:[] };
  pbEditIndex = -1;
  pbRender();
}
```

- [ ] **Step 9: Verify in browser**

Open `http://localhost:3000/index-v2.html` → Protocol Builder:
1. Add Testosterone Enanthate — unit auto-fills mg, set 200mg dose, E3.5D, weeks 1–12 → click Add → card appears showing "Weeks 1–12: 200mg (400mg/wk)"
2. Click "+ Phase" → a second phase row appears
3. Click "Remove" on a compound → modal appears with compound name, week and reason fields
4. Cancel — compound stays; Remove — compound disappears, no console errors
5. Select "Specific days…" in frequency → weekday button row appears; click Mon + Thu → dose hint shows correct weekly total

- [ ] **Step 10: Commit**

```bash
git add index-v2.html
git commit -m "feat(protocol): phase-based compound management, weekday freq picker, remove-compound modal"
```

---

## Task 5: Save + Modification Log Writes

**Files:**
- Modify: `index-v2.html:3544–3572` (`_pbDoSave`)

**Interfaces:**
- Consumes: `pbState` from Task 4
- Produces: protocol saved to `hrt_protocols` in new shape
- Produces: `type: 'dose_change'` log entries written when editing an active protocol

---

- [ ] **Step 1: Replace _pbDoSave**

```js
function _pbDoSave() {
  const cycleLengthWeeks = parseInt(document.getElementById('pb-cycle-weeks').value) || 16;
  const startDate        = document.getElementById('pb-cycle-start-date').value || '';
  const status           = document.getElementById('pb-cycle-status').value || 'planning';
  const savedAt          = pbEditIndex >= 0
    ? (lsGet('hrt_protocols', []).map(normalizeProtocol)[pbEditIndex]?.saved_at || new Date().toISOString())
    : new Date().toISOString();

  // Detect dose changes on active protocols
  let modLog = [...pbState.modificationLog];
  if (pbEditIndex >= 0 && status === 'active') {
    const prev = normalizeProtocol(lsGet('hrt_protocols', [])[pbEditIndex]);
    if (prev) {
      pbState.compounds.forEach(c => {
        const prevC = (prev.compounds || []).find(pc => pc.name === c.name);
        if (!prevC) return;
        c.phases.forEach((ph, pi) => {
          const prevPh = prevC.phases[pi];
          if (prevPh && prevPh.dose !== ph.dose) {
            modLog.push({
              week: pbCurrentCycleWeek(startDate),
              type: 'dose_change',
              compound: c.name,
              note: `${prevPh.dose}${c.unit} → ${ph.dose}${c.unit}`,
              ts: Date.now()
            });
          }
        });
      });
    }
  }

  const protocol = {
    name: document.getElementById('pb-name').value || 'Untitled Protocol',
    phase: document.getElementById('pb-phase').value,
    cycleLengthWeeks,
    weeks: String(cycleLengthWeeks),   // keep for backward compat
    startDate,
    status,
    exp: document.getElementById('pb-exp').value,
    notes: document.getElementById('pb-notes').value,
    compounds: pbState.compounds,
    modificationLog: modLog,
    saved_at: savedAt
  };

  const saved = lsGet('hrt_protocols', []);
  if (pbEditIndex >= 0 && pbEditIndex < saved.length) {
    saved.splice(pbEditIndex, 1, protocol);
  } else {
    saved.unshift(protocol);
  }
  localStorage.setItem('hrt_protocols', JSON.stringify(saved));

  // Refresh active protocol if this one is active
  const active = localStorage.getItem('hrt_active_protocol');
  if (active === protocol.saved_at) {
    localStorage.setItem('hrt_active_protocol_data', JSON.stringify(protocol));
    renderUpcoming();
  }

  pbState.modificationLog = modLog;
  pbEditIndex = -1;
  return protocol;
}
```

- [ ] **Step 2: Add pbCurrentCycleWeek helper (near renderCycleProgress)**

```js
function pbCurrentCycleWeek(startDate) {
  if (!startDate) return 1;
  const days = Math.max(0, (Date.now() - Date.parse(startDate)) / 86400000);
  return Math.floor(days / 7) + 1;
}
```

- [ ] **Step 3: Add pbOnWeeksChange extend-all option**

Find `pbOnWeeksChange` (added in Task 4) and extend it:

```js
function pbOnWeeksChange() {
  const weeks = parseInt(document.getElementById('pb-cycle-weeks').value) || 16;
  const old   = pbState.cycleLengthWeeks;
  pbState.cycleLengthWeeks = weeks;
  if (weeks > old && pbState.compounds.length) {
    const extend = confirm(`Extend all currently running compounds from week ${old} to week ${weeks}?`);
    if (extend) {
      pbState.compounds.forEach(c => {
        const last = c.phases[c.phases.length - 1];
        if (last.endWeek === old) last.endWeek = weeks;
      });
      pbState.modificationLog.push({ week: pbCurrentCycleWeek(pbState.startDate), type: 'cycle_extended', compound: '', note: `Cycle extended ${old}wk → ${weeks}wk`, ts: Date.now() });
    }
  } else if (weeks < old && pbState.compounds.some(c => c.phases.some(ph => ph.endWeek > weeks))) {
    alert(`⚠ Some compound phases extend past week ${weeks}. Review them in the Builder.`);
  }
  const endWk = document.getElementById('pb-end-week');
  if (endWk && parseInt(endWk.value) > weeks) endWk.value = weeks;
  pbRender();
}
```

- [ ] **Step 4: Verify in browser**

1. Build a protocol (Testosterone Enanthate 200mg E3.5D wks 1–12). Save it. Open browser console: `JSON.parse(localStorage.getItem('hrt_protocols'))[0]` — verify `cycleLengthWeeks: 12`, `startDate`, `status`, `compounds[0].phases` all present.
2. Set protocol as Active, set a start date, edit the dose from 200mg to 175mg, save. Check `modificationLog` — verify a `dose_change` entry is present.
3. Change Total Weeks from 12 → 16 with a compound present → confirm dialog appears.

- [ ] **Step 5: Commit**

```bash
git add index-v2.html
git commit -m "feat(protocol): update _pbDoSave for phased shape, modificationLog writes on active edits, cycle extend confirm"
```

---

## Task 6: Timeline Tab — renderProtocolTimeline

**Files:**
- Modify: `index-v2.html` (add `renderProtocolTimeline` + `buildWeekGrid` near renderProtocolsPage)

**Interfaces:**
- Consumes: `pbState.compounds` (phases), `pbState.cycleLengthWeeks`
- Produces: `buildWeekGrid(compounds, totalWeeks)` — returns `{ weeks: number[], rows: Array<{name, unit, cells: Array<string|null>}> }`
- Produces: `renderProtocolTimeline()` — renders HTML into `#pb-timeline-grid`

---

- [ ] **Step 1: Add buildWeekGrid to test harness**

In `tests/protocol-logic.html`, add after the existing tests:

```html
<script>
// ── buildWeekGrid ──
function buildWeekGrid(compounds, totalWeeks) {
  const weeks = Array.from({ length: totalWeeks }, (_, i) => i + 1);
  const rows = compounds.map(c => ({
    name: c.name,
    unit: c.unit,
    freq: c.freq,
    cells: weeks.map(w => {
      const ph = (c.phases || []).find(p => w >= p.startWeek && w <= p.endWeek);
      return ph ? String(ph.dose) : null;
    })
  }));
  return { weeks, rows };
}

section('buildWeekGrid');
const compounds = [
  { name: 'Test E', unit: 'mg', freq: 'E3.5D', phases: [{ startWeek:1, endWeek:5, dose:200 },{ startWeek:6, endWeek:12, dose:150 }] },
  { name: 'Anavar', unit: 'mg', freq: 'ED', phases: [{ startWeek:9, endWeek:12, dose:50 }] }
];
const grid = buildWeekGrid(compounds, 12);
assert('grid has 12 week columns',        grid.weeks.length, 12);
assert('Test E week 1 = 200',             grid.rows[0].cells[0], '200');
assert('Test E week 5 = 200',             grid.rows[0].cells[4], '200');
assert('Test E week 6 = 150',             grid.rows[0].cells[5], '150');
assert('Test E week 12 = 150',            grid.rows[0].cells[11], '150');
assert('Anavar week 8 = null (inactive)', grid.rows[1].cells[7], null);
assert('Anavar week 9 = 50',             grid.rows[1].cells[8], '50');
assert('Anavar week 12 = 50',            grid.rows[1].cells[11], '50');
</script>
```

- [ ] **Step 2: Open tests/protocol-logic.html and verify new tests pass**

Expected: all grid tests pass (green).

- [ ] **Step 3: Add buildWeekGrid and renderProtocolTimeline to index-v2.html**

Add near `renderProtocolsPage` (around line 3440):

```js
function buildWeekGrid(compounds, totalWeeks) {
  const weeks = Array.from({ length: totalWeeks }, (_, i) => i + 1);
  const rows = compounds.map(c => ({
    name: c.name,
    unit: c.unit,
    freq: c.freq,
    cells: weeks.map(w => {
      const ph = (c.phases || []).find(p => w >= p.startWeek && w <= p.endWeek);
      return ph ? String(ph.dose) : null;
    })
  }));
  return { weeks, rows };
}

function renderProtocolTimeline() {
  const el = document.getElementById('pb-timeline-grid');
  if (!el) return;
  if (!pbState.compounds.length) {
    el.innerHTML = '<div style="color:var(--text-muted);font-size:12px;">Build a protocol in the Builder tab to see the timeline.</div>';
    return;
  }
  const { weeks, rows } = buildWeekGrid(pbState.compounds, pbState.cycleLengthWeeks || 12);
  const thStyle = 'padding:5px 10px;font-size:11px;font-weight:600;color:var(--text-muted);text-align:center;white-space:nowrap;';
  const nameStyle = 'padding:6px 10px;font-size:12px;color:var(--text-secondary);font-weight:500;white-space:nowrap;';
  const activeStyle = 'padding:5px 8px;font-size:11px;font-family:var(--font-data);background:var(--primary-dim);color:var(--primary-bright);border-radius:3px;text-align:center;';
  const emptyStyle  = 'padding:5px 8px;font-size:11px;color:var(--text-muted);text-align:center;';

  const headerCells = weeks.map(w => `<th style="${thStyle}">Wk${w}</th>`).join('');
  const bodyRows = rows.map(r => {
    const freqLabel = Array.isArray(r.freq) ? r.freq.join(',') : r.freq;
    const cells = r.cells.map(v =>
      v !== null
        ? `<td style="${activeStyle}">${v}${r.unit}</td>`
        : `<td style="${emptyStyle}">—</td>`
    ).join('');
    return `<tr>
      <td style="${nameStyle}">${r.name}<br><span style="font-size:10px;color:var(--text-muted);">${freqLabel}</span></td>
      ${cells}
    </tr>`;
  }).join('');

  el.innerHTML = `<table style="border-collapse:collapse;min-width:100%;">
    <thead><tr><th style="${thStyle};text-align:left;">Compound</th>${headerCells}</tr></thead>
    <tbody>${bodyRows}</tbody>
  </table>`;
}
```

- [ ] **Step 4: Verify in browser**

Build a protocol with Test E (200mg, wks 1–12) and Anavar (50mg, wks 9–12). Click the Timeline tab. Expected: table with 12 week columns; Test E shows 200mg in all columns; Anavar shows `—` in wks 1–8, `50mg` in wks 9–12.

- [ ] **Step 5: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat(protocol): timeline tab with week-by-week grid via buildWeekGrid"
```

---

## Task 7: Modification Log Tab — renderProtocolLog + Add Note

**Files:**
- Modify: `index-v2.html` (add `renderProtocolLog`, `pbAddNote`)

**Interfaces:**
- Consumes: `pbState.modificationLog`
- Produces: `renderProtocolLog()` — renders HTML into `#pb-log-list`
- Produces: `pbAddNote()` — prompts for week + note, pushes `type:'note'` entry

---

- [ ] **Step 1: Add renderProtocolLog and pbAddNote**

Add near `renderProtocolTimeline`:

```js
const _pbLogIcons = {
  addition:        { icon: '+', color: 'var(--green)' },
  removal:         { icon: '×', color: 'var(--red)' },
  dose_change:     { icon: '↕', color: 'var(--amber)' },
  cycle_extended:  { icon: '→', color: 'var(--primary-bright)' },
  cycle_shortened: { icon: '←', color: 'var(--amber)' },
  note:            { icon: '✎', color: 'var(--text-muted)' }
};

function renderProtocolLog() {
  const el = document.getElementById('pb-log-list');
  if (!el) return;
  const log = [...(pbState.modificationLog || [])].sort((a, b) => b.ts - a.ts);
  if (!log.length) {
    el.innerHTML = '<div style="color:var(--text-muted);font-size:12px;">No modifications recorded yet.</div>';
    return;
  }
  el.innerHTML = log.map(entry => {
    const meta   = _pbLogIcons[entry.type] || { icon: '•', color: 'var(--text-muted)' };
    const date   = entry.ts ? new Date(entry.ts).toLocaleDateString() : '';
    const label  = entry.compound ? `<strong style="color:var(--text-primary);">${entry.compound}</strong>` : '';
    const noteEl = entry.note ? `<span style="color:var(--text-secondary);"> — ${entry.note}</span>` : '';
    return `<div style="display:flex;gap:10px;align-items:flex-start;padding:8px 0;border-bottom:1px solid var(--border);">
      <span style="font-size:14px;color:${meta.color};min-width:18px;text-align:center;">${meta.icon}</span>
      <div style="flex:1;font-size:12px;">
        <span style="color:var(--text-muted);">Wk ${entry.week || '?'}</span>
        <span style="color:var(--text-muted);margin:0 6px;">·</span>
        ${label}${noteEl}
      </div>
      <span style="font-size:11px;color:var(--text-muted);white-space:nowrap;">${date}</span>
    </div>`;
  }).join('');
}

function pbAddNote() {
  const week = parseInt(prompt('At which week?', pbCurrentCycleWeek(pbState.startDate)));
  if (!week || isNaN(week)) return;
  const note = prompt('Note:');
  if (!note) return;
  pbState.modificationLog.push({ week, type: 'note', compound: '', note: note.trim(), ts: Date.now() });
  renderProtocolLog();
}
```

- [ ] **Step 2: Wire pbAddNote to mid-cycle compound addition**

In `pbAddCompound`, after pushing to `pbState.compounds`, add:

```js
  // Log addition if protocol is active
  if (pbState.status === 'active') {
    pbState.modificationLog.push({
      week: pbCurrentCycleWeek(pbState.startDate),
      type: 'addition',
      compound: name,
      note: `${dose}${unit} ${Array.isArray(freq) ? freq.join(',') : freq} starting week ${startWeek}`,
      ts: Date.now()
    });
  }
```

- [ ] **Step 3: Verify in browser**

1. Build protocol with Test E. Open Remove modal → remove with reason "Testing log" at week 4. Click Log tab → entry appears: `× Wk 4 · Test E — Testing log`.
2. Click "+ Add Note" → enter week 5, note "Feeling strong" → entry appears in log.
3. Log sorted newest-first.

- [ ] **Step 4: Commit**

```bash
git add index-v2.html
git commit -m "feat(protocol): modification log tab with addition/removal/note events"
```

---

## Task 8: Dashboard Cycle Card

**Files:**
- Modify: `index-v2.html:2956–3003` (replace `renderCycleProgress`)

**Interfaces:**
- Consumes: `normalizeProtocol(p)` from Task 1
- Consumes: `buildWeekGrid(compounds, totalWeeks)` from Task 6
- Consumes: `pbCurrentCycleWeek(startDate)` from Task 5
- Produces: updated `renderCycleProgress(protocol)` — shows current week, active compounds, upcoming changes
- Produces: "due today" indicator when compound's `freq` array contains today's weekday abbreviation

---

- [ ] **Step 1: Replace renderCycleProgress**

```js
function renderCycleProgress(rawProtocol) {
  const label = document.getElementById('cycle-label');
  const pct   = document.getElementById('cycle-pct');
  const bar   = document.getElementById('cycle-bar');
  const ssBar = document.getElementById('ss-bar');
  const ssLbl = document.getElementById('ss-label');
  if (!label) return;

  if (!rawProtocol || !rawProtocol.saved_at) {
    label.textContent = '—'; pct.textContent = '—';
    if (bar) bar.style.width = '0%';
    if (ssBar) ssBar.style.width = '0%';
    if (ssLbl) ssLbl.textContent = '—';
    return;
  }

  const protocol     = normalizeProtocol(rawProtocol);
  const totalWeeks   = protocol.cycleLengthWeeks || parseInt(protocol.weeks) || 0;
  const startDate    = protocol.startDate || protocol.saved_at;
  const currentWeek  = Math.min(pbCurrentCycleWeek(startDate), totalWeeks || 9999);
  const progressPct  = totalWeeks > 0 ? Math.min(100, Math.round(((currentWeek - 1) / totalWeeks) * 100)) : 0;

  label.textContent = totalWeeks > 0 ? `Week ${currentWeek} of ${totalWeeks}` : `Week ${currentWeek}`;
  pct.textContent   = totalWeeks > 0 ? `${progressPct}%` : '—';
  if (bar) bar.style.width = `${progressPct}%`;

  // Steady state bar (unchanged logic)
  const halfLives = (protocol.compounds || []).map(c => {
    const n = (c.name || '').toLowerCase();
    if (n.includes('cypionate')) return 8;
    if (n.includes('enanthate')) return 4.5;
    if (n.includes('propionate')) return 2;
    if (n.includes('undecanoate')) return 21;
    if (n.includes('decanoate') || n.includes('deca')) return 15;
    if (n.includes('boldenone') || n.includes('eq')) return 14;
    if (n.includes('primobolan') || n.includes('methenolone')) return 10;
    if (n.includes('masteron')) return 10;
    if (n.includes('trenbolone enanthate') || n.includes('tren-e')) return 5.5;
    if (n.includes('trenbolone acetate') || n.includes('tren-a')) return 3;
    return 7;
  });
  const longestHL = halfLives.length ? Math.max(...halfLives) : 7;
  const daysDone  = Math.max(0, (Date.now() - Date.parse(startDate)) / 86400000);
  const ssPct     = Math.min(100, Math.round((daysDone / (longestHL * 4)) * 100));
  if (ssBar) ssBar.style.width  = `${ssPct}%`;
  if (ssLbl) ssLbl.textContent  = `${ssPct}% steady state`;

  // Active compounds this week + "due today"
  const cycleCard = document.getElementById('cycle-active-compounds');
  if (!cycleCard || !protocol.compounds.length) return;
  const todayDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][new Date().getDay()];
  const { rows } = buildWeekGrid(protocol.compounds, totalWeeks || currentWeek);
  const activeThisWeek = rows.filter(r => r.cells[currentWeek - 1] !== null);

  if (!activeThisWeek.length) { cycleCard.innerHTML = ''; return; }

  const activeHtml = activeThisWeek.map(r => {
    const dose      = r.cells[currentWeek - 1];
    const freqLabel = Array.isArray(r.freq) ? r.freq.join(', ') : r.freq;
    const dueToday  = Array.isArray(r.freq) && r.freq.includes(todayDay);
    return `<div style="display:flex;justify-content:space-between;font-size:12px;padding:3px 0;">
      <span style="color:var(--text-secondary);">${r.name}${dueToday ? ' <span style="font-size:10px;color:var(--green);">● today</span>' : ''}</span>
      <span style="font-family:var(--font-data);color:var(--primary-bright);">${dose}${r.unit}</span>
      <span style="color:var(--text-muted);">${freqLabel}</span>
    </div>`;
  }).join('');

  // Upcoming changes (next 2 weeks)
  const upcoming = [];
  protocol.compounds.forEach(c => {
    c.phases.forEach((ph, pi) => {
      const nextPh = c.phases[pi + 1];
      if (nextPh && nextPh.startWeek > currentWeek && nextPh.startWeek <= currentWeek + 2) {
        const diff = nextPh.startWeek - currentWeek;
        upcoming.push(`${c.name} → ${nextPh.dose}${c.unit} — Wk ${nextPh.startWeek} (${diff} wk${diff > 1 ? 's' : ''})`);
      }
      if (ph.startWeek > currentWeek && ph.startWeek <= currentWeek + 2 && pi === 0) {
        const diff = ph.startWeek - currentWeek;
        upcoming.push(`${c.name} starts ${ph.dose}${c.unit} — Wk ${ph.startWeek} (${diff} wk${diff > 1 ? 's' : ''})`);
      }
    });
  });

  const upcomingHtml = upcoming.length
    ? `<div style="margin-top:10px;padding-top:8px;border-top:1px solid var(--border);">
        <div style="font-size:11px;color:var(--text-muted);margin-bottom:4px;text-transform:uppercase;letter-spacing:.05em;">Upcoming</div>
        ${upcoming.map(u => `<div style="font-size:11px;color:var(--text-secondary);">→ ${u}</div>`).join('')}
      </div>`
    : '';

  cycleCard.innerHTML = `
    <div style="font-size:11px;color:var(--text-muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em;">Active this week</div>
    ${activeHtml}
    ${upcomingHtml}
  `;
}
```

- [ ] **Step 2: Add cycle-active-compounds div to Dashboard HTML**

Find `id="page-dashboard"` (line ~563). Locate the existing cycle progress card (contains `#cycle-label`, `#cycle-bar`). Directly after the closing `</div>` of that card section, add:

```html
<div id="cycle-active-compounds" style="margin-top:10px;"></div>
```

- [ ] **Step 3: Verify in browser**

1. Build a protocol: Test E 200mg E3.5D wks 1–12, Anavar 50mg ED wks 9–12. Set Active, set Start Date to a date ~9 weeks ago.
2. Navigate to Dashboard. Expected: "Week 9 of 12", active compounds list shows Test E (200mg) and Anavar (50mg).
3. Set Start Date to today → "Week 1 of 12". Anavar should not appear in active list.
4. Set freq for Test E to `['Mon','Thu']` via console: `let p = JSON.parse(localStorage.getItem('hrt_active_protocol_data')); p.compounds[0].freq=['Mon','Thu']; localStorage.setItem('hrt_active_protocol_data',JSON.stringify(p)); location.reload()`. If today is Mon or Thu, "● today" badge should appear.

- [ ] **Step 4: Commit**

```bash
git add index-v2.html
git commit -m "feat(dashboard): cycle card shows week position, active compounds, upcoming phase changes, due-today indicator"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Phase-based compounds (startWeek, endWeek, dose) | Task 4 |
| Compound-level freq (named + weekday array) | Task 3, 4 |
| PWO frequency | Task 1 |
| cycleLengthWeeks, startDate, status | Task 3, 5 |
| Backward compat migration via normalizeProtocol | Task 1 |
| SLU-PP-332 addition | Task 2 |
| Builder tab — phase CRUD | Task 4 |
| Timeline tab — read-only grid | Task 6 |
| Log tab — modification history | Task 7 |
| Remove compound modal + log entry | Task 4, 7 |
| Cycle extend/shorten + extend-all shortcut | Task 5 |
| Mid-cycle compound addition log entry | Task 7 |
| dose_change auto-log on active protocol edit | Task 5 |
| Dashboard cycle card (week position) | Task 8 |
| Active compounds this week | Task 8 |
| Upcoming changes (next 2 weeks) | Task 8 |
| "Due today" weekday indicator | Task 8 |

**No placeholders found.**

**Type consistency:** `buildWeekGrid` defined in Task 6, consumed in Task 8 — same signature. `normalizeProtocol` defined in Task 1, consumed in Tasks 5 and 8. `pbCurrentCycleWeek` defined in Task 5, consumed in Tasks 5 and 8. `phaseWeeklyTotal` defined in Task 1, consumed in Task 4. All consistent.

**One gap found and fixed:** `cycle-active-compounds` div added in Task 8 Step 2 but must exist in HTML before `renderCycleProgress` fires. Step 2 covers adding it.
