# Insulin Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-injection insulin log to the Health Log page (renamed from Vitals), with a modal form, color-coded BG table, and Supabase sync.

**Architecture:** Single-file vanilla JS app (`index.html`). Three tasks: (1) HTML rename + new card + modal markup, (2) all insulin JS functions, (3) Supabase fetch wired into `loadUserData`. Each task is independently testable.

**Tech Stack:** Vanilla JS, localStorage, Supabase JS v2 (CDN), existing `.modal`/`.form-input`/`.card` CSS classes, Tabler icons

## Global Constraints

- All changes confined to `index.html`
- No new CSS files — use only existing classes: `.card`, `.modal`, `.modal-overlay`, `.btn-primary`, `.btn-secondary`, `.form-input`, `.form-select`, `.form-group`, `.form-row`, `.form-label`
- `escHtml(s)` wraps every user-supplied string written to innerHTML
- `saveInsulinEntry` is fire-and-forget — never awaited at call sites, never blocks UI
- Internal page ID `page-vitals` and `nav('vitals')` remain unchanged
- No editing or deleting entries — append-only log
- BG color thresholds: green 70–140, amber 141–180, red <70 or >180 (mg/dL)
- `_supaUser` (not `_user`) is the existing global holding the signed-in user

---

## Pre-flight: Create Supabase table

Before any task, the user runs this SQL once in Supabase SQL Editor:

```sql
create table if not exists insulin_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  date        date not null,
  time        text,
  type        text not null,
  name        text not null,
  units       numeric not null,
  timing      text,
  bg_before   numeric,
  carbs       numeric,
  bg_after    numeric,
  notes       text,
  created_at  timestamptz not null default now()
);

alter table insulin_log enable row level security;

create policy "Users manage own insulin log"
  on insulin_log for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index insulin_log_user_date on insulin_log(user_id, date desc);
```

---

### Task 1: Page rename + Insulin Log HTML (card + modal)

**Files:**
- Modify: `index.html`

**Interfaces:**
- Produces: `id="insulin-log-content"` — target for Task 2's `renderInsulinLog()`
- Produces: `id="insulin-modal"` modal with field IDs consumed by Task 2
- Produces: `openInsulinModal()` call in button onclick — defined in Task 2

**Field IDs produced for Task 2:**
`ins-date`, `ins-time`, `ins-type`, `ins-name`, `ins-other-wrap`, `ins-other-name`, `ins-units`, `ins-timing-wrap`, `ins-timing`, `ins-bg-before`, `ins-carbs-wrap`, `ins-carbs`, `ins-bg-after`, `ins-notes`

- [ ] **Step 1: Rename sidebar nav label**

Find (~line 638–641):
```html
    <div class="nav-item" onclick="nav('vitals')">
      <span class="nav-icon"><i class="ti ti-heart-rate-monitor"></i></span>
      <span class="nav-text">Vitals</span>
    </div>
```

Replace with:
```html
    <div class="nav-item" onclick="nav('vitals')">
      <span class="nav-icon"><i class="ti ti-heart-rate-monitor"></i></span>
      <span class="nav-text">Health Log</span>
    </div>
```

- [ ] **Step 2: Rename page section heading and Vitals Log card title**

Find (~line 995–996):
```html
    <section class="page" id="page-vitals">
      <div class="section-heading">Vitals &amp; Daily Metrics</div>
```

Replace with:
```html
    <section class="page" id="page-vitals">
      <div class="section-heading">Health Log</div>
```

Find (~line 1012):
```html
        <div class="card-title">Vitals Log</div>
```

Replace with:
```html
        <div class="card-title">Daily Log</div>
```

- [ ] **Step 3: Insert Insulin Log card before the Daily Log card**

Find the existing Daily Log card opening (just after the glucose chart grid closes, ~line 1011):
```html
      <div class="card">
        <div class="card-title">Daily Log</div>
        <div id="vitals-table-wrap">
```

Insert this block immediately before it:
```html
      <div class="card" style="margin-bottom:14px;">
        <div class="card-title" style="display:flex;justify-content:space-between;align-items:center;">
          Insulin Log
          <button class="btn-primary" style="font-size:12px;padding:5px 12px;" onclick="openInsulinModal()">+ Add</button>
        </div>
        <div id="insulin-log-content"></div>
      </div>
```

- [ ] **Step 4: Add insulin modal HTML**

Find the closing `</div>` of `log-modal` (~line 1713):
```html
    </div>
  </div>
</div>

<!-- Tabler icons -->
```

Insert the insulin modal immediately after the log-modal closing `</div>`:
```html
<div class="modal-overlay" id="insulin-modal">
  <div class="modal">
    <div class="modal-title">
      Log Insulin Injection
      <span class="modal-close" onclick="closeModal('insulin-modal')"><i class="ti ti-x"></i></span>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Date</label>
        <input type="date" class="form-input" id="ins-date">
      </div>
      <div class="form-group">
        <label class="form-label">Time</label>
        <input type="time" class="form-input" id="ins-time">
      </div>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Type</label>
        <select class="form-select" id="ins-type" onchange="updateInsulinTypeUI()">
          <option value="short">Short-acting</option>
          <option value="long">Long-acting</option>
        </select>
      </div>
      <div class="form-group">
        <label class="form-label">Units</label>
        <input type="number" class="form-input" id="ins-units" placeholder="10" step="0.5" min="0.5">
      </div>
    </div>
    <div class="form-group">
      <label class="form-label">Insulin</label>
      <select class="form-select" id="ins-name" onchange="document.getElementById('ins-other-wrap').style.display=this.value==='other'?'':'none'">
        <option>Humalog</option><option>NovoLog</option><option>Humulin R</option><option>Slin</option><option value="other">Other</option>
      </select>
      <div id="ins-other-wrap" style="display:none;margin-top:6px;">
        <input type="text" class="form-input" id="ins-other-name" placeholder="Insulin name">
      </div>
    </div>
    <div id="ins-timing-wrap" class="form-group">
      <label class="form-label">Timing</label>
      <select class="form-select" id="ins-timing">
        <option value="post-workout">Post-workout</option>
        <option value="pre-meal">Pre-meal</option>
        <option value="fasted">Fasted</option>
        <option value="other">Other</option>
      </select>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">BG Before (mg/dL)</label>
        <input type="number" class="form-input" id="ins-bg-before" placeholder="98">
      </div>
      <div id="ins-carbs-wrap" class="form-group">
        <label class="form-label">Carbs (g)</label>
        <input type="number" class="form-input" id="ins-carbs" placeholder="80">
      </div>
    </div>
    <div class="form-group">
      <label class="form-label">BG After (mg/dL)</label>
      <input type="number" class="form-input" id="ins-bg-after" placeholder="112">
    </div>
    <div class="form-group">
      <label class="form-label">Notes</label>
      <textarea class="form-input" id="ins-notes" rows="2" placeholder="Optional notes" style="resize:vertical;"></textarea>
    </div>
    <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:6px;">
      <button class="btn-secondary" onclick="closeModal('insulin-modal')">Cancel</button>
      <button class="btn-primary" onclick="submitInsulinLog()">Save Injection</button>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Verify**

```bash
grep -n 'Health Log\|insulin-log-content\|insulin-modal\|ins-date\|ins-type\|ins-bg-after' index.html
```

Expected: `Health Log` in nav and section heading; `insulin-log-content`, `insulin-modal`, `ins-date`, `ins-type`, `ins-bg-after` each appear at least once.

- [ ] **Step 6: Smoke test**

Open `index.html` in a browser. Confirm:
- Sidebar shows "Health Log" (not "Vitals")
- Navigate to Health Log — heading reads "Health Log", section shows "Insulin Log" card with "+ Add" button and "Daily Log" table below
- Clicking "+ Add" opens the modal with all fields visible
- Switching Type to "Long-acting" hides Timing and Carbs fields
- Switching back to "Short-acting" shows them again

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "feat: rename Vitals to Health Log, add insulin log card and modal HTML"
```

---

### Task 2: Insulin JS functions

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: field IDs from Task 1 (`ins-date`, `ins-time`, `ins-type`, `ins-name`, `ins-other-wrap`, `ins-other-name`, `ins-units`, `ins-timing-wrap`, `ins-timing`, `ins-bg-before`, `ins-carbs-wrap`, `ins-carbs`, `ins-bg-after`, `ins-notes`)
- Consumes: `lsGet(key, fallback)`, `escHtml(s)`, `openModal(id)`, `closeModal(id)` — existing globals
- Consumes: `_supa`, `_supaUser` — existing globals
- Produces: `openInsulinModal()`, `updateInsulinTypeUI()`, `submitInsulinLog()`, `saveInsulinEntry(entry)`, `renderInsulinLog()` — called by HTML onclick and Task 3

- [ ] **Step 1: Add all five insulin functions after `renderVitalsPage` closes**

Find `renderVitalsPage` and the function that follows it (~line 2632–2668). Insert the five functions after `renderVitalsPage` closes (after its closing `}`):

```js
function openInsulinModal() {
  const now = new Date();
  document.getElementById('ins-date').value = now.toISOString().split('T')[0];
  document.getElementById('ins-time').value = now.toTimeString().slice(0, 5);
  document.getElementById('ins-type').value = 'short';
  document.getElementById('ins-units').value = '';
  document.getElementById('ins-bg-before').value = '';
  document.getElementById('ins-carbs').value = '';
  document.getElementById('ins-bg-after').value = '';
  document.getElementById('ins-notes').value = '';
  document.getElementById('ins-other-wrap').style.display = 'none';
  document.getElementById('ins-other-name').value = '';
  updateInsulinTypeUI();
  openModal('insulin-modal');
}

function updateInsulinTypeUI() {
  const isShort = document.getElementById('ins-type').value === 'short';
  const nameEl  = document.getElementById('ins-name');
  const shortOpts = '<option>Humalog</option><option>NovoLog</option><option>Humulin R</option><option>Slin</option><option value="other">Other</option>';
  const longOpts  = '<option>Lantus</option><option>Levemir</option><option>Tresiba</option><option>Basaglar</option><option value="other">Other</option>';
  nameEl.innerHTML = isShort ? shortOpts : longOpts;
  document.getElementById('ins-timing-wrap').style.display = isShort ? '' : 'none';
  document.getElementById('ins-carbs-wrap').style.display  = isShort ? '' : 'none';
  document.getElementById('ins-other-wrap').style.display  = 'none';
}

function submitInsulinLog() {
  const date  = document.getElementById('ins-date').value;
  const units = parseFloat(document.getElementById('ins-units').value);
  if (!date)          { alert('Please enter a date.');       return; }
  if (!units || units <= 0) { alert('Please enter units > 0.'); return; }

  const type    = document.getElementById('ins-type').value;
  const nameEl  = document.getElementById('ins-name');
  const nameVal = nameEl.value === 'other'
    ? (document.getElementById('ins-other-name').value.trim() || 'Other')
    : nameEl.value;
  const isShort = type === 'short';

  const entry = {
    date,
    time:      document.getElementById('ins-time').value || '',
    type,
    name:      nameVal,
    units,
    timing:    isShort ? document.getElementById('ins-timing').value : '',
    bg_before: parseFloat(document.getElementById('ins-bg-before').value) || null,
    carbs:     isShort ? (parseFloat(document.getElementById('ins-carbs').value) || null) : null,
    bg_after:  parseFloat(document.getElementById('ins-bg-after').value) || null,
    notes:     document.getElementById('ins-notes').value.trim()
  };

  saveInsulinEntry(entry);
  closeModal('insulin-modal');
}

async function saveInsulinEntry(entry) {
  entry.id         = crypto.randomUUID();
  entry.created_at = new Date().toISOString();
  const log = lsGet('hrt_insulin_log', []);
  log.unshift(entry);
  localStorage.setItem('hrt_insulin_log', JSON.stringify(log));
  renderInsulinLog();
  if (_supa && _supaUser) {
    const { error } = await _supa.from('insulin_log').insert({ ...entry, user_id: _supaUser.id });
    if (error) console.warn('[insulin] save failed:', error.message);
  }
}

function renderInsulinLog() {
  const el = document.getElementById('insulin-log-content');
  if (!el) return;
  const entries = lsGet('hrt_insulin_log', []).slice(0, 30);
  if (!entries.length) {
    el.innerHTML = `<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100px;gap:6px;text-align:center;">
      <i class="ti ti-syringe" style="font-size:28px;color:var(--text-muted);opacity:0.4;"></i>
      <div style="color:var(--text-muted);font-size:13px;">No insulin entries yet</div>
      <div style="font-size:11px;color:var(--text-muted);opacity:0.7;">Track your first injection with + Add</div>
    </div>`;
    return;
  }
  const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const bgStyle = v => {
    if (!v) return '';
    const n = parseFloat(v);
    if (n < 70 || n > 180) return 'color:var(--red);font-weight:500;';
    if (n > 140)            return 'color:var(--amber);';
    return 'color:var(--green);';
  };
  const rows = entries.map(e => {
    const [y, m, d] = e.date.split('-').map(Number);
    const dateLabel = `${MON[m-1]} ${d}${e.time ? ' · ' + e.time : ''}`;
    const badge = e.type === 'short'
      ? `<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:var(--primary-dim);color:var(--primary-bright);">Short</span>`
      : `<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:var(--purple-dim);color:var(--purple);">Long</span>`;
    const bgAfter = e.bg_after != null
      ? `<span style="${bgStyle(e.bg_after)}">${escHtml(String(e.bg_after))}</span>`
      : '—';
    return `<tr style="border-bottom:0.5px solid var(--border);">
      <td style="padding:8px 6px;font-size:12px;color:var(--text-secondary);white-space:nowrap;">${escHtml(dateLabel)}</td>
      <td style="padding:8px 6px;">${badge}</td>
      <td style="padding:8px 6px;font-size:12px;">${escHtml(e.name)}</td>
      <td style="padding:8px 6px;font-size:12px;font-family:var(--font-data);">${escHtml(String(e.units))}u</td>
      <td style="padding:8px 6px;font-size:12px;color:var(--text-muted);">${e.bg_before != null ? escHtml(String(e.bg_before)) : '—'}</td>
      <td style="padding:8px 6px;font-size:12px;color:var(--text-muted);">${e.carbs != null ? escHtml(String(e.carbs)) + 'g' : '—'}</td>
      <td style="padding:8px 6px;font-size:12px;">${bgAfter}</td>
    </tr>`;
  }).join('');
  el.innerHTML = `<table style="width:100%;border-collapse:collapse;">
    <thead><tr style="border-bottom:0.5px solid var(--border);">
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Date / Time</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Type</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Name</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Units</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">BG Before</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Carbs</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">BG After</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}
```

- [ ] **Step 2: Wire `renderInsulinLog()` into `renderVitalsPage`**

Find the start of `renderVitalsPage` (~line 2632):

```js
function renderVitalsPage() {
  const wrap = document.getElementById('vitals-table-wrap');
  const logs = lsGet('hrt_vitals_log', []);
```

Replace with:

```js
function renderVitalsPage() {
  renderInsulinLog();
  const wrap = document.getElementById('vitals-table-wrap');
  const logs = lsGet('hrt_vitals_log', []);
```

- [ ] **Step 3: Verify**

```bash
grep -n 'openInsulinModal\|updateInsulinTypeUI\|submitInsulinLog\|saveInsulinEntry\|renderInsulinLog' index.html
```

Expected: each function name appears at least twice (definition + call site). `renderInsulinLog` appears 3 times: definition, call in `saveInsulinEntry`, call in `renderVitalsPage`.

- [ ] **Step 4: Smoke test**

Open `index.html`, navigate to Health Log. Confirm:
- Insulin Log card shows empty state with syringe icon
- Click "+ Add", set Type=Short, fill Date, Units=10, BG Before=95, Carbs=70, BG After=112 → Save
- Entry appears in table: Short badge, `10u`, BG After shown in green
- Add another entry with BG After=55 → appears in red (hypo warning)
- Add Long-acting entry — Timing and Carbs columns show `—`

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat: add insulin log JS — render, save, modal open/submit functions"
```

---

### Task 3: `loadUserData()` — fetch insulin log from Supabase

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `renderInsulinLog()` from Task 2
- Consumes: `_supa`, `_supaUser`, `lsGet` — existing globals
- Produces: `hrt_insulin_log` populated in localStorage from Supabase on sign-in

- [ ] **Step 1: Add insulin fetch to `loadUserData` Promise.all**

Find the existing Promise.all in `loadUserData` (~line 1789–1793):

```js
    const [logsRes, metricsRes, settingsRes] = await Promise.all([
      _supa.from('administration_log').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(50),
      _supa.from('daily_metrics').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(90),
      _supa.from('user_settings').select('*').eq('user_id', uid).maybeSingle()
    ]);
```

Replace with:

```js
    const [logsRes, metricsRes, settingsRes, insulinRes] = await Promise.all([
      _supa.from('administration_log').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(50),
      _supa.from('daily_metrics').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(90),
      _supa.from('user_settings').select('*').eq('user_id', uid).maybeSingle(),
      _supa.from('insulin_log').select('*').eq('user_id', uid).order('date', { ascending: false }).order('created_at', { ascending: false }).limit(90)
    ]);
```

- [ ] **Step 2: Add insulin error check and localStorage restore**

Find the existing error checks (~line 1794–1796):

```js
    if (logsRes.error) console.error('[loadUserData] logs query failed:', logsRes.error);
    if (metricsRes.error) console.error('[loadUserData] metrics query failed:', metricsRes.error);
    if (settingsRes.error) console.error('[loadUserData] settings query failed:', settingsRes.error);
```

Replace with:

```js
    if (logsRes.error)    console.error('[loadUserData] logs query failed:', logsRes.error);
    if (metricsRes.error) console.error('[loadUserData] metrics query failed:', metricsRes.error);
    if (settingsRes.error) console.error('[loadUserData] settings query failed:', settingsRes.error);
    if (insulinRes.error) console.error('[loadUserData] insulin query failed:', insulinRes.error);

    if (insulinRes.data?.length) {
      const insulinLog = insulinRes.data.map(r => ({
        id:        r.id,
        date:      r.date,
        time:      r.time      || '',
        type:      r.type,
        name:      r.name,
        units:     r.units,
        timing:    r.timing    || '',
        bg_before: r.bg_before ?? null,
        carbs:     r.carbs     ?? null,
        bg_after:  r.bg_after  ?? null,
        notes:     r.notes     || '',
        created_at: r.created_at
      }));
      localStorage.setItem('hrt_insulin_log', JSON.stringify(insulinLog));
      renderInsulinLog();
    }
```

- [ ] **Step 3: Verify**

```bash
grep -n 'insulinRes\|insulin_log\|hrt_insulin_log' index.html
```

Expected: `insulinRes` appears in Promise.all destructure, error check, and data block; `insulin_log` in the Supabase query; `hrt_insulin_log` in saveInsulinEntry and loadUserData restore.

- [ ] **Step 4: Smoke test — Supabase round-trip**

1. Sign in with Google at `https://hrt.cruznetllc.com`
2. Navigate to Health Log, click "+ Add", log a Humalog injection with BG Before=95, Carbs=70, BG After=115
3. Open Supabase → Table Editor → `insulin_log` — confirm the row appears
4. Open a private/incognito window, sign in — navigate to Health Log and confirm the entry restores automatically

- [ ] **Step 5: Commit and push**

```bash
git add index.html
git commit -m "feat: fetch insulin log from Supabase on sign-in, restore to localStorage"
git push
```
