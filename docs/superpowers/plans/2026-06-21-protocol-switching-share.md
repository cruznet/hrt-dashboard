# Protocol Switching + Share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When activating a new protocol while one is active, show a close-out modal that records how the old cycle ended (Completed/Abandoned) and writes a log entry; add a Share button on each protocol card that opens a print-optimized view.

**Architecture:** All changes are in `index-v2.html` (single-file vanilla JS app). The switch flow is gated in `setActiveProtocol()` — if the current active protocol has `status: 'active'`, it shows a modal before switching; otherwise it switches silently. Print/Share generates a self-contained HTML document in a new tab using `window.open()`.

**Tech Stack:** Vanilla JS · localStorage · no build system · no npm

## Global Constraints

- Single file: ALL changes go in `index-v2.html`. Do NOT split into multiple files.
- No build system, no npm, no bundler.
- All CSS uses existing variables: `--primary`, `--primary-dim`, `--primary-bright`, `--primary-border`, `--green`, `--amber`, `--red`, `--border`, `--text-primary`, `--text-secondary`, `--text-muted`, `--bg-card`. No hardcoded colors.
- Do not use `c.weeklyDose` — weekly totals always computed from `perInjection × injectionsPerWeek`.
- Do not rename `normalizeCompound()`.
- All user content rendered via `escHtml()` — no raw user strings in innerHTML.
- `lsGet(key, fallback)` is the localStorage read helper (line 1891). Write via `localStorage.setItem(key, JSON.stringify(value))` — there is no `lsSet`.
- Test harness: `tests/protocol-logic.html` — a plain HTML file with inline `<script>` blocks. Add new test blocks without removing existing tests.
- The browser test harness can be opened at `http://localhost:3000/tests/protocol-logic.html`. Run server with `python3 server.py` from the project root.

---

## File Map

| File | Changes |
|---|---|
| `index-v2.html` | All JS + HTML changes (Tasks 1–5) |
| `tests/protocol-logic.html` | New test blocks for Tasks 2 and 4 |

---

### Task 1: Status badges on protocol cards

Add a status badge to every protocol card in `renderProtocolsPage()`. Currently only `Active` is shown (if `isActive`). After this task, all four statuses render a badge: Planning, Active, Completed, Abandoned.

**Files:**
- Modify: `index-v2.html:3767–3798` (`renderProtocolsPage` inner map)

**Interfaces:**
- Consumes: `p.status` (string, may be undefined on old protocols — treat as `'planning'`), `isActive` (bool)
- Produces: nothing new — purely visual

- [ ] **Step 1: Replace the existing Active badge with a full status badge**

In `renderProtocolsPage()`, the current line (~3779–3781) is:
```js
<div style="font-size:15px;font-weight:600;color:var(--text-primary);margin-bottom:4px;">${p.name}
  ${isActive ? '<span style="margin-left:8px;font-size:11px;background:var(--primary-dim);color:var(--primary-bright);border:1px solid var(--primary-border);padding:2px 8px;border-radius:4px;">Active</span>' : ''}
</div>
```

Replace the badge expression with this block computed before the template literal. Insert immediately before the `return \`` line (around line 3775):

```js
const status = p.status || 'planning';
const statusBadgeHtml = isActive
  ? '<span style="margin-left:8px;font-size:11px;background:rgba(16,185,129,0.12);color:var(--green);border:1px solid rgba(16,185,129,0.3);padding:2px 8px;border-radius:4px;">Active</span>'
  : status === 'completed'
    ? '<span style="margin-left:8px;font-size:11px;background:var(--primary-dim);color:var(--primary-bright);border:1px solid var(--primary-border);padding:2px 8px;border-radius:4px;">Completed</span>'
    : status === 'abandoned'
      ? '<span style="margin-left:8px;font-size:11px;background:rgba(100,116,139,0.12);color:var(--text-muted);border:1px solid var(--border);padding:2px 8px;border-radius:4px;">Abandoned</span>'
      : '<span style="margin-left:8px;font-size:11px;background:rgba(99,102,241,0.08);color:var(--text-secondary);border:1px solid var(--border);padding:2px 8px;border-radius:4px;">Planning</span>';
```

Then update the name div to use `statusBadgeHtml`:
```js
<div style="font-size:15px;font-weight:600;color:var(--text-primary);margin-bottom:4px;">${escHtml(p.name)}${statusBadgeHtml}</div>
```

Note: also wrap `p.name` in `escHtml()` — it was previously unescaped.

- [ ] **Step 2: Verify visually**

Open `http://localhost:3000/index-v2.html`, navigate to My Protocols. If you have a saved protocol, its status badge should render. Open DevTools console — no JS errors expected.

To test all four badges without real data, temporarily run in console:
```js
const p = lsGet('hrt_protocols', []);
if (p[0]) { p[0].status = 'abandoned'; localStorage.setItem('hrt_protocols', JSON.stringify(p)); renderProtocolsPage(); }
```
Confirm badge reads "Abandoned" in muted style. Then restore:
```js
if (p[0]) { p[0].status = 'planning'; localStorage.setItem('hrt_protocols', JSON.stringify(p)); renderProtocolsPage(); }
```

- [ ] **Step 3: Commit**

```bash
git add index-v2.html
git commit -m "feat: status badges for all 4 protocol statuses (planning/active/completed/abandoned)"
```

---

### Task 2: `cycle_closed` log type

Add `cycle_closed` to `_pbLogIcons` and update `renderProtocolLog()` to render it correctly — icon color is green for completed, muted for abandoned, determined by `entry.closed_as`. Also adds a human-readable label ("Cycle completed" / "Cycle abandoned") since `cycle_closed` entries have no `compound` field.

**Files:**
- Modify: `index-v2.html:3669–3676` (`_pbLogIcons`)
- Modify: `index-v2.html:3690–3704` (`renderProtocolLog` inner map)
- Modify: `tests/protocol-logic.html` (new test block)

**Interfaces:**
- Consumes: log entry shape `{ type: 'cycle_closed', closed_as: 'completed'|'abandoned', week, note, ts }`
- Produces: `_pbLogIcons['cycle_closed']` (used by Task 4 indirectly)

- [ ] **Step 1: Add `cycle_closed` to `_pbLogIcons`**

Current `_pbLogIcons` (line 3669):
```js
const _pbLogIcons = {
  addition:        { icon: '+', color: 'var(--green)' },
  removal:         { icon: '×', color: 'var(--red)' },
  dose_change:     { icon: '↕', color: 'var(--amber)' },
  cycle_extended:  { icon: '→', color: 'var(--primary-bright)' },
  cycle_shortened: { icon: '←', color: 'var(--amber)' },
  note:            { icon: '✎', color: 'var(--text-muted)' }
};
```

Replace with:
```js
const _pbLogIcons = {
  addition:        { icon: '+', color: 'var(--green)' },
  removal:         { icon: '×', color: 'var(--red)' },
  dose_change:     { icon: '↕', color: 'var(--amber)' },
  cycle_extended:  { icon: '→', color: 'var(--primary-bright)' },
  cycle_shortened: { icon: '←', color: 'var(--amber)' },
  cycle_closed:    { icon: '✓', color: 'var(--green)' },
  note:            { icon: '✎', color: 'var(--text-muted)' }
};
```

- [ ] **Step 2: Update `renderProtocolLog` to handle `cycle_closed`**

Current inner map block (lines 3690–3703):
```js
el.innerHTML = log.map(entry => {
  const meta   = _pbLogIcons[entry.type] || { icon: '•', color: 'var(--text-muted)' };
  const date   = entry.ts ? new Date(entry.ts).toLocaleDateString() : '';
  const label  = entry.compound ? `<strong style="color:var(--text-primary);">${escHtml(entry.compound)}</strong>` : '';
  const noteEl = entry.note ? `<span style="color:var(--text-secondary);"> — ${escHtml(entry.note)}</span>` : '';
  return `<div style="display:flex;gap:10px;align-items:flex-start;padding:8px 0;border-bottom:1px solid var(--border);">
    <span style="font-size:14px;color:${meta.color};min-width:18px;text-align:center;">${meta.icon}</span>
    <div style="flex:1;font-size:12px;">
      <span style="color:var(--text-muted);">Wk ${escHtml(String(entry.week || '?'))}</span>
      <span style="color:var(--text-muted);margin:0 6px;">·</span>
      ${label}${noteEl}
    </div>
    <span style="font-size:11px;color:var(--text-muted);white-space:nowrap;">${date}</span>
  </div>`;
}).join('');
```

Replace with:
```js
el.innerHTML = log.map(entry => {
  let meta = _pbLogIcons[entry.type] || { icon: '•', color: 'var(--text-muted)' };
  if (entry.type === 'cycle_closed' && entry.closed_as === 'abandoned') {
    meta = { icon: '✓', color: 'var(--text-muted)' };
  }
  const date   = entry.ts ? new Date(entry.ts).toLocaleDateString() : '';
  let label;
  if (entry.type === 'cycle_closed') {
    const closedLabel = entry.closed_as === 'abandoned' ? 'Cycle abandoned' : 'Cycle completed';
    label = `<strong style="color:var(--text-primary);">${closedLabel}</strong>`;
  } else {
    label = entry.compound ? `<strong style="color:var(--text-primary);">${escHtml(entry.compound)}</strong>` : '';
  }
  const noteEl = entry.note ? `<span style="color:var(--text-secondary);"> — ${escHtml(entry.note)}</span>` : '';
  const weekStr = entry.week != null ? `Wk ${escHtml(String(entry.week))}` : 'Wk —';
  return `<div style="display:flex;gap:10px;align-items:flex-start;padding:8px 0;border-bottom:1px solid var(--border);">
    <span style="font-size:14px;color:${meta.color};min-width:18px;text-align:center;">${meta.icon}</span>
    <div style="flex:1;font-size:12px;">
      <span style="color:var(--text-muted);">${weekStr}</span>
      <span style="color:var(--text-muted);margin:0 6px;">·</span>
      ${label}${noteEl}
    </div>
    <span style="font-size:11px;color:var(--text-muted);white-space:nowrap;">${date}</span>
  </div>`;
}).join('');
```

- [ ] **Step 3: Add tests to `tests/protocol-logic.html`**

At the end of the `<script>` block, add:

```js
section('cycle_closed log entries');

// Copy in the updated _pbLogIcons and renderProtocolLog support logic for test
const _pbLogIconsTest = {
  addition:        { icon: '+', color: 'var(--green)' },
  removal:         { icon: '×', color: 'var(--red)' },
  dose_change:     { icon: '↕', color: 'var(--amber)' },
  cycle_extended:  { icon: '→', color: 'var(--primary-bright)' },
  cycle_shortened: { icon: '←', color: 'var(--amber)' },
  cycle_closed:    { icon: '✓', color: 'var(--green)' },
  note:            { icon: '✎', color: 'var(--text-muted)' }
};

function getLogMeta(entry) {
  let meta = _pbLogIconsTest[entry.type] || { icon: '•', color: 'var(--text-muted)' };
  if (entry.type === 'cycle_closed' && entry.closed_as === 'abandoned') {
    meta = { icon: '✓', color: 'var(--text-muted)' };
  }
  return meta;
}

function getLogLabel(entry) {
  if (entry.type === 'cycle_closed') {
    return entry.closed_as === 'abandoned' ? 'Cycle abandoned' : 'Cycle completed';
  }
  return entry.compound || '';
}

assert('cycle_closed icon is ✓',
  _pbLogIconsTest['cycle_closed'].icon, '✓');

assert('cycle_closed completed → green color',
  getLogMeta({ type: 'cycle_closed', closed_as: 'completed' }).color, 'var(--green)');

assert('cycle_closed abandoned → muted color',
  getLogMeta({ type: 'cycle_closed', closed_as: 'abandoned' }).color, 'var(--text-muted)');

assert('cycle_closed completed label',
  getLogLabel({ type: 'cycle_closed', closed_as: 'completed' }), 'Cycle completed');

assert('cycle_closed abandoned label',
  getLogLabel({ type: 'cycle_closed', closed_as: 'abandoned' }), 'Cycle abandoned');

assert('unknown type falls back to bullet icon',
  (function() { let m = _pbLogIconsTest['unknown_type'] || { icon: '•', color: 'var(--text-muted)' }; return m.icon; })(), '•');
```

- [ ] **Step 4: Run tests**

Open `http://localhost:3000/tests/protocol-logic.html`. Confirm all previous tests still pass AND the 6 new `cycle_closed` tests pass. No red lines.

- [ ] **Step 5: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat: cycle_closed log type with completed/abandoned color distinction"
```

---

### Task 3: Close-out modal HTML + state variables + cancel/toggle functions

Add the `#pb-close-modal` overlay div to the My Protocols section, and add the JS state variables and UI-only functions (`pbSetCloseStatus`, `pbCancelSwitch`). No switch logic yet — that's Task 4.

**Files:**
- Modify: `index-v2.html:1206–1209` (page-protocols HTML section)
- Modify: `index-v2.html:3443` (state variables block, after `_pbRemoveTargetIndex`)

**Interfaces:**
- Produces: `_pbPendingSwitch` (object `{ newIndex }` or `null`), `_pbCloseStatus` (`'completed'|'abandoned'`), `pbSetCloseStatus(val)`, `pbCancelSwitch()` — all consumed by Task 4
- Produces: `#pb-close-modal` DOM element — consumed by Tasks 4 and 5

- [ ] **Step 1: Add modal HTML inside `page-protocols`**

Current `page-protocols` section (lines 1206–1209):
```html
    <section class="page" id="page-protocols">
      <div class="section-heading">My Protocols</div>
      <div id="protocols-list"></div>
    </section>
```

Replace with:
```html
    <section class="page" id="page-protocols">
      <div class="section-heading">My Protocols</div>
      <div id="protocols-list"></div>

      <!-- Close-out modal: shown when switching away from an active protocol -->
      <div id="pb-close-modal" style="display:none;position:fixed;inset:0;background:rgba(0,0,0,0.7);z-index:1000;align-items:center;justify-content:center;">
        <div class="card" style="width:380px;max-width:90vw;">
          <div class="card-title">Before switching — how did this protocol end?</div>
          <p id="pb-close-modal-name" style="font-size:13px;color:var(--text-secondary);margin-bottom:14px;"></p>
          <div class="form-group" style="margin-bottom:14px;">
            <label class="form-label">How did it end?</label>
            <div style="display:flex;gap:8px;">
              <button id="pb-close-btn-completed" class="btn-primary" style="flex:1;" onclick="pbSetCloseStatus('completed')">Completed</button>
              <button id="pb-close-btn-abandoned" class="btn-secondary" style="flex:1;" onclick="pbSetCloseStatus('abandoned')">Abandoned</button>
            </div>
          </div>
          <div class="form-group">
            <label class="form-label">Week ended (optional)</label>
            <input type="number" class="form-input" id="pb-close-week" min="1" placeholder="e.g. 12">
          </div>
          <div class="form-group">
            <label class="form-label">Reason / notes (optional)</label>
            <textarea class="form-input" id="pb-close-note" rows="2" placeholder="e.g. Coach adjustment, side effects..."></textarea>
          </div>
          <div style="display:flex;gap:8px;margin-top:12px;">
            <button class="btn-primary" onclick="pbConfirmSwitch()">Confirm &amp; Switch</button>
            <button class="btn-secondary" onclick="pbSkipSwitch()">Skip — just switch</button>
            <button class="btn-secondary" onclick="pbCancelSwitch()">Cancel</button>
          </div>
        </div>
      </div>
    </section>
```

- [ ] **Step 2: Add state variables**

After line 3443 (`let _pbRemoveTargetIndex = -1;`), add:
```js
let _pbPendingSwitch = null;   // { newIndex } while close-out modal is open
let _pbCloseStatus = 'completed'; // 'completed' | 'abandoned'
```

- [ ] **Step 3: Add `pbSetCloseStatus` and `pbCancelSwitch` functions**

Add these two functions after `pbCloseRemoveModal()` (after line 3608):
```js
function pbSetCloseStatus(val) {
  _pbCloseStatus = val;
  const btnC = document.getElementById('pb-close-btn-completed');
  const btnA = document.getElementById('pb-close-btn-abandoned');
  if (!btnC || !btnA) return;
  btnC.className = val === 'completed' ? 'btn-primary' : 'btn-secondary';
  btnA.className = val === 'abandoned' ? 'btn-primary' : 'btn-secondary';
  btnC.style.flex = '1';
  btnA.style.flex = '1';
}

function pbCancelSwitch() {
  _pbPendingSwitch = null;
  document.getElementById('pb-close-modal').style.display = 'none';
}
```

- [ ] **Step 4: Verify modal renders**

Open `http://localhost:3000/index-v2.html`, go to My Protocols. In DevTools console, run:
```js
document.getElementById('pb-close-modal').style.display = 'flex';
```
Modal should appear. Click Cancel — nothing happens yet (pbCancelSwitch exists but pbConfirmSwitch/pbSkipSwitch don't exist yet — that's Task 4). Run:
```js
pbCancelSwitch();
```
Modal should hide. No JS errors.

- [ ] **Step 5: Commit**

```bash
git add index-v2.html
git commit -m "feat: close-out modal HTML + state variables for protocol switching"
```

---

### Task 4: Switch logic — rewrite `setActiveProtocol` + helpers

Rewrite `setActiveProtocol(index)` to intercept active→active switches. Add `_doSwitch`, `_pbCloseOutOld`, `pbConfirmSwitch`, `pbSkipSwitch` helpers. After this task, switching away from an active protocol shows the close-out modal and writes a `cycle_closed` log entry.

**Files:**
- Modify: `index-v2.html:3801–3818` (rewrite `setActiveProtocol`)
- Modify: `index-v2.html` (add new functions after `setActiveProtocol`)
- Modify: `tests/protocol-logic.html` (new test block)

**Interfaces:**
- Consumes: `_pbPendingSwitch`, `_pbCloseStatus`, `pbSetCloseStatus()`, `pbCancelSwitch()`, `#pb-close-modal` (from Task 3)
- Consumes: `lsGet`, `normalizeProtocol`, `pbCurrentCycleWeek`, `renderProtocolsPage`, `renderCycleProgress`, `renderUpcoming`, `updateTopbarBadge`, `normalizeCompound` (all existing)
- Produces: `_pbCloseOutOld(closedAs, week, note)`, `_doSwitch(newIndex)`, `pbConfirmSwitch()`, `pbSkipSwitch()`

- [ ] **Step 1: Rewrite `setActiveProtocol`**

Current `setActiveProtocol` (lines 3801–3818):
```js
function setActiveProtocol(index) {
  const saved = lsGet('hrt_protocols', []).map(normalizeProtocol);
  const p = saved[index];
  if (!p) return;
  localStorage.setItem('hrt_active_protocol', p.saved_at);
  localStorage.setItem('hrt_active_protocol_data', JSON.stringify(p));
  renderProtocolsPage();
  // Update dashboard protocol display if visible
  const pills = (p.compounds || []).map(raw => {
    const c = normalizeCompound(raw);
    return `<span class="pill pill-primary">${c.name} ${c.dose}${c.unit} ${c.freq}</span>`;
  }).join(' ');
  const pd = document.getElementById('protocol-display');
  if (pd) pd.innerHTML = `<div style="margin-bottom:8px;">${pills}</div>`;
  renderCycleProgress(p);
  renderUpcoming();
  updateTopbarBadge();
}
```

Replace the entire function with:
```js
function setActiveProtocol(index) {
  const currentSavedAt = localStorage.getItem('hrt_active_protocol');
  if (currentSavedAt) {
    const allSaved = lsGet('hrt_protocols', []).map(normalizeProtocol);
    const current = allSaved.find(p => p.saved_at === currentSavedAt);
    if (current && current.status === 'active') {
      _pbPendingSwitch = { newIndex: index };
      _pbCloseStatus = 'completed';
      pbSetCloseStatus('completed');
      document.getElementById('pb-close-modal-name').textContent = current.name;
      document.getElementById('pb-close-week').value = current.startDate ? pbCurrentCycleWeek(current.startDate) : '';
      document.getElementById('pb-close-note').value = '';
      document.getElementById('pb-close-modal').style.display = 'flex';
      return;
    }
  }
  _doSwitch(index);
}
```

- [ ] **Step 2: Add `_doSwitch` helper**

Add immediately after `setActiveProtocol` (after its closing `}`):
```js
function _doSwitch(newIndex) {
  const saved = lsGet('hrt_protocols', []).map(normalizeProtocol);
  const p = saved[newIndex];
  if (!p) return;
  localStorage.setItem('hrt_active_protocol', p.saved_at);
  localStorage.setItem('hrt_active_protocol_data', JSON.stringify(p));
  renderProtocolsPage();
  const pills = (p.compounds || []).map(raw => {
    const c = normalizeCompound(raw);
    return `<span class="pill pill-primary">${c.name} ${c.dose}${c.unit} ${c.freq}</span>`;
  }).join(' ');
  const pd = document.getElementById('protocol-display');
  if (pd) pd.innerHTML = `<div style="margin-bottom:8px;">${pills}</div>`;
  renderCycleProgress(p);
  renderUpcoming();
  updateTopbarBadge();
}
```

- [ ] **Step 3: Add `_pbCloseOutOld` helper**

Add after `_doSwitch`:
```js
function _pbCloseOutOld(closedAs, week, note) {
  const currentSavedAt = localStorage.getItem('hrt_active_protocol');
  if (!currentSavedAt) return;
  const allRaw = lsGet('hrt_protocols', []);
  const idx = allRaw.findIndex(p => p.saved_at === currentSavedAt);
  if (idx === -1) return;
  const p = normalizeProtocol(allRaw[idx]);
  p.status = closedAs;
  p.modificationLog = p.modificationLog || [];
  p.modificationLog.push({ type: 'cycle_closed', closed_as: closedAs, week: week || null, note: note || '', ts: Date.now() });
  allRaw[idx] = p;
  localStorage.setItem('hrt_protocols', JSON.stringify(allRaw));
  localStorage.removeItem('hrt_active_protocol');
  localStorage.removeItem('hrt_active_protocol_data');
}
```

- [ ] **Step 4: Add `pbConfirmSwitch` and `pbSkipSwitch`**

Add after `_pbCloseOutOld`:
```js
function pbConfirmSwitch() {
  if (!_pbPendingSwitch) return;
  const week = parseInt(document.getElementById('pb-close-week').value) || null;
  const note = document.getElementById('pb-close-note').value.trim();
  _pbCloseOutOld(_pbCloseStatus, week, note);
  const newIndex = _pbPendingSwitch.newIndex;
  _pbPendingSwitch = null;
  document.getElementById('pb-close-modal').style.display = 'none';
  _doSwitch(newIndex);
}

function pbSkipSwitch() {
  if (!_pbPendingSwitch) return;
  const currentSavedAt = localStorage.getItem('hrt_active_protocol');
  const current = currentSavedAt
    ? lsGet('hrt_protocols', []).map(normalizeProtocol).find(p => p.saved_at === currentSavedAt)
    : null;
  const week = current ? (pbCurrentCycleWeek(current.startDate) || null) : null;
  _pbCloseOutOld('abandoned', week, '');
  const newIndex = _pbPendingSwitch.newIndex;
  _pbPendingSwitch = null;
  document.getElementById('pb-close-modal').style.display = 'none';
  _doSwitch(newIndex);
}
```

- [ ] **Step 5: Add tests to `tests/protocol-logic.html`**

Add at end of the last `<script>` block:
```js
section('Protocol switching — _pbCloseOutOld logic');

// Set up localStorage with a fake active protocol
(function() {
  const fakeProtocol = {
    saved_at: 'test-saved-at-001',
    name: 'Test Cycle',
    status: 'active',
    cycleLengthWeeks: 12,
    startDate: '2026-01-01',
    compounds: [],
    modificationLog: []
  };
  localStorage.setItem('hrt_protocols', JSON.stringify([fakeProtocol]));
  localStorage.setItem('hrt_active_protocol', 'test-saved-at-001');

  // Copy _pbCloseOutOld logic inline for testing (since it reads from localStorage)
  function testCloseOutOld(closedAs, week, note) {
    const currentSavedAt = localStorage.getItem('hrt_active_protocol');
    if (!currentSavedAt) return;
    const allRaw = lsGet('hrt_protocols', []);
    const idx = allRaw.findIndex(p => p.saved_at === currentSavedAt);
    if (idx === -1) return;
    const p = normalizeProtocol(allRaw[idx]);
    p.status = closedAs;
    p.modificationLog = p.modificationLog || [];
    p.modificationLog.push({ type: 'cycle_closed', closed_as: closedAs, week: week || null, note: note || '', ts: Date.now() });
    allRaw[idx] = p;
    localStorage.setItem('hrt_protocols', JSON.stringify(allRaw));
    localStorage.removeItem('hrt_active_protocol');
    localStorage.removeItem('hrt_active_protocol_data');
  }

  testCloseOutOld('completed', 12, 'Full cycle done');

  const updated = lsGet('hrt_protocols', []);
  assert('close-out sets status to completed', updated[0].status, 'completed');
  assert('close-out pushes cycle_closed log entry', updated[0].modificationLog.length, 1);
  assert('cycle_closed log entry has correct type', updated[0].modificationLog[0].type, 'cycle_closed');
  assert('cycle_closed log entry closed_as completed', updated[0].modificationLog[0].closed_as, 'completed');
  assert('cycle_closed log entry week', updated[0].modificationLog[0].week, 12);
  assert('cycle_closed log entry note', updated[0].modificationLog[0].note, 'Full cycle done');
  assert('hrt_active_protocol cleared after close-out', localStorage.getItem('hrt_active_protocol'), null);

  // Test abandoned / skip path
  localStorage.setItem('hrt_protocols', JSON.stringify([{
    saved_at: 'test-saved-at-002',
    name: 'Test Cycle 2',
    status: 'active',
    cycleLengthWeeks: 16,
    startDate: null,
    compounds: [],
    modificationLog: []
  }]));
  localStorage.setItem('hrt_active_protocol', 'test-saved-at-002');

  testCloseOutOld('abandoned', null, '');
  const updated2 = lsGet('hrt_protocols', []);
  assert('skip close-out sets status to abandoned', updated2[0].status, 'abandoned');
  assert('skip close-out week is null when no startDate', updated2[0].modificationLog[0].week, null);
  assert('skip close-out note is empty string', updated2[0].modificationLog[0].note, '');

  // Clean up test data
  localStorage.removeItem('hrt_protocols');
  localStorage.removeItem('hrt_active_protocol');
  localStorage.removeItem('hrt_active_protocol_data');
})();
```

- [ ] **Step 6: Run tests**

Open `http://localhost:3000/tests/protocol-logic.html`. All previous tests pass. The 10 new switching tests pass. No red lines.

- [ ] **Step 7: Manual smoke test**

1. Build two protocols in Protocol Builder, save both
2. Set one as Active (status: active, start date set)
3. Click "Set Active" on the second protocol
4. Close-out modal appears with the first protocol's name and current week pre-filled
5. Select "Abandoned", enter a reason, click "Confirm & Switch"
6. First protocol shows "Abandoned" badge in My Protocols list
7. Second protocol is now active
8. Edit first protocol → Log tab: shows "Cycle abandoned" entry with the reason

- [ ] **Step 8: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat: protocol switching close-out modal — completed/abandoned with log entry"
```

---

### Task 5: Print / Share view

Add `printProtocol(index)` function and a "Share" button on each protocol card. The function opens a self-contained, print-optimized HTML document in a new tab.

**Files:**
- Modify: `index-v2.html:3789–3793` (button group in `renderProtocolsPage`)
- Modify: `index-v2.html` (add `printProtocol` function near `renderProtocolsPage`)

**Interfaces:**
- Consumes: `lsGet`, `normalizeProtocol`, `buildWeekGrid`, `pbCurrentCycleWeek`, `escHtml` (all existing)
- Produces: `printProtocol(index)` — opens a new browser tab

- [ ] **Step 1: Add Share button to protocol cards**

In `renderProtocolsPage()`, the current button group (line ~3789–3793) is:
```js
<div style="display:flex;gap:8px;">
  ${!isActive ? `<button class="btn-primary" style="font-size:12px;padding:5px 12px;" onclick="setActiveProtocol(${i})">Set Active</button>` : ''}
  <button class="btn-secondary" style="font-size:12px;padding:5px 12px;" onclick="editProtocol(${i})">Edit</button>
  <button class="btn-secondary" style="font-size:12px;padding:5px 12px;color:var(--red);border-color:var(--red);" onclick="deleteProtocol(${i})">Delete</button>
</div>
```

Replace with:
```js
<div style="display:flex;gap:8px;flex-wrap:wrap;">
  ${!isActive ? `<button class="btn-primary" style="font-size:12px;padding:5px 12px;" onclick="setActiveProtocol(${i})">Set Active</button>` : ''}
  <button class="btn-secondary" style="font-size:12px;padding:5px 12px;" onclick="editProtocol(${i})">Edit</button>
  <button class="btn-secondary" style="font-size:12px;padding:5px 12px;" onclick="printProtocol(${i})">Share</button>
  <button class="btn-secondary" style="font-size:12px;padding:5px 12px;color:var(--red);border-color:var(--red);" onclick="deleteProtocol(${i})">Delete</button>
</div>
```

- [ ] **Step 2: Add `printProtocol` function**

Add the following function after `renderProtocolsPage` (after line ~3799):

```js
function printProtocol(index) {
  const saved = lsGet('hrt_protocols', []).map(normalizeProtocol);
  const p = saved[index];
  if (!p) return;

  const totalWeeks = p.cycleLengthWeeks || parseInt(p.weeks) || 12;
  const { weeks, rows } = buildWeekGrid(p.compounds || [], totalWeeks);

  const compoundRows = (p.compounds || []).map(c => {
    const freqLabel = Array.isArray(c.freq) ? c.freq.join(', ') : (c.freq || '');
    const phases = (c.phases || []).map(ph => `Wk${ph.startWeek}–${ph.endWeek}: ${ph.dose}${c.unit}`).join(' · ');
    return `<tr><td>${escHtml(c.name)}</td><td>${escHtml(c.cat || '')}</td><td>${escHtml(freqLabel)}</td><td>${phases || '—'}</td></tr>`;
  }).join('') || '<tr><td colspan="4" style="color:#888;font-style:italic;">No compounds</td></tr>';

  const gridHeaders = weeks.map(w => `<th>Wk${w}</th>`).join('');
  const gridRows = rows.map(r => {
    const freqLabel = Array.isArray(r.freq) ? r.freq.join(',') : r.freq;
    const cells = r.cells.map(v => v !== null ? `<td>${escHtml(String(v))}${escHtml(r.unit)}</td>` : '<td style="color:#aaa;">—</td>').join('');
    return `<tr><td>${escHtml(r.name)}<br><small style="color:#888;">${escHtml(freqLabel)}</small></td>${cells}</tr>`;
  }).join('') || '<tr><td colspan="100" style="color:#888;font-style:italic;">No compounds</td></tr>';

  const log = [...(p.modificationLog || [])].sort((a, b) => (a.ts || 0) - (b.ts || 0));
  const logRows = log.length
    ? log.map(e => {
        const typeLabel = e.type === 'cycle_closed'
          ? (e.closed_as === 'abandoned' ? 'Abandoned' : 'Completed')
          : e.type.replace(/_/g, ' ');
        const week = e.week != null ? `Wk ${e.week}` : '—';
        const date = e.ts ? new Date(e.ts).toLocaleDateString() : '';
        return `<tr><td>${week}</td><td>${typeLabel}</td><td>${escHtml(e.compound || '')}</td><td>${escHtml(e.note || '')}</td><td>${date}</td></tr>`;
      }).join('')
    : '<tr><td colspan="5" style="color:#888;font-style:italic;">No modifications logged</td></tr>';

  const statusLabel = p.status ? p.status.charAt(0).toUpperCase() + p.status.slice(1) : 'Planning';
  const statusColors = {
    active:    { bg: '#d1fae5', fg: '#065f46' },
    completed: { bg: '#e0e7ff', fg: '#3730a3' },
    abandoned: { bg: '#f3f4f6', fg: '#6b7280' },
    planning:  { bg: '#eff6ff', fg: '#1e40af' }
  };
  const sc = statusColors[p.status] || statusColors.planning;
  const dateRange = p.startDate ? `Start: ${p.startDate}` : 'No start date set';
  const generatedDate = new Date().toLocaleDateString();

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${escHtml(p.name)}</title>
<style>
  body { font-family: Arial, sans-serif; padding: 32px; max-width: 1100px; margin: 0 auto; color: #111; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  .meta { font-size: 13px; color: #555; margin-bottom: 24px; }
  h2 { font-size: 15px; border-bottom: 1px solid #ddd; padding-bottom: 6px; margin: 28px 0 12px; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th { background: #f5f5f5; padding: 6px 8px; text-align: left; font-weight: 600; border: 1px solid #ddd; white-space: nowrap; }
  td { padding: 5px 8px; border: 1px solid #ddd; vertical-align: top; }
  .grid-wrap { overflow-x: auto; }
  @media print { body { padding: 16px; } }
</style>
</head>
<body>
  <h1>${escHtml(p.name)} <span style="display:inline-block;padding:2px 10px;border-radius:4px;font-size:12px;font-weight:600;background:${sc.bg};color:${sc.fg};">${statusLabel}</span></h1>
  <div class="meta">${totalWeeks} weeks · ${dateRange} · Generated ${generatedDate}</div>

  <h2>Compounds &amp; Phases</h2>
  <table>
    <thead><tr><th>Compound</th><th>Category</th><th>Frequency</th><th>Phases</th></tr></thead>
    <tbody>${compoundRows}</tbody>
  </table>

  <h2>Week-by-Week Grid</h2>
  <div class="grid-wrap">
    <table>
      <thead><tr><th>Compound</th>${gridHeaders}</tr></thead>
      <tbody>${gridRows}</tbody>
    </table>
  </div>

  <h2>Modification Log</h2>
  <table>
    <thead><tr><th>Week</th><th>Type</th><th>Compound</th><th>Note</th><th>Date</th></tr></thead>
    <tbody>${logRows}</tbody>
  </table>
</body>
</html>`;

  const w = window.open('', '_blank');
  if (!w) { alert('Pop-up blocked — please allow pop-ups for this page and try again.'); return; }
  w.document.write(html);
  w.document.close();
}
```

- [ ] **Step 3: Verify the print view**

Open `http://localhost:3000/index-v2.html`, go to My Protocols. Click "Share" on any protocol.

Expected: a new tab opens with a white-background document showing the protocol name, status badge, compounds table, week grid, and modification log. No app chrome, no dark theme.

If you have no protocols, create one with compounds and phases in Protocol Builder first.

Test pop-up blocked path: in Chrome, block pop-ups for localhost in site settings, click Share — the `alert()` fires.

- [ ] **Step 4: Commit**

```bash
git add index-v2.html
git commit -m "feat: Share button on protocol cards opens print-ready view with compounds, grid, and log"
```
