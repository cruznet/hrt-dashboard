# Mobile Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the full HRT dashboard usable on mobile phones with a hamburger overlay sidebar, reflowed metric cards, stacked forms, hidden secondary table columns, and fixed inline grids.

**Architecture:** All changes confined to `index.html`. CSS additions go inside or adjacent to the existing `@media (max-width: 768px)` block (~line 465). JS additions go near the existing auth/nav helpers. HTML changes are surgical (hamburger button, backdrop div, class additions). No new files.

**Tech Stack:** Vanilla CSS media queries, vanilla JS, existing Tabler icon set (`ti-menu-2`), existing CSS variables (`--sidebar-w`, `--border`, etc.)

## Global Constraints

- All changes confined to `index.html` — no new files
- Breakpoint stays at `768px` — no new breakpoints
- `page-vitals`, `nav('vitals')`, and all internal page IDs unchanged
- Existing `.collapsed` class on `#sidebar` preserved for desktop toggle
- `escHtml(s)` wraps all user-supplied strings in innerHTML (no new XSS surface)
- CSS variables used throughout: `--sidebar-w` (200px), `--sidebar-w-col` (52px), `--border`, `--text-muted`, `--bg-card`

---

### Task 1: Hamburger Sidebar + Topbar

**Files:**
- Modify: `index.html`

**Interfaces:**
- Produces: `toggleMobileMenu()` — called by `#mob-menu-btn` onclick
- Produces: `closeMobileMenu()` — called by `#mob-backdrop` onclick and at top of `nav(page)` 
- Produces: `#mob-backdrop` div, `#mob-menu-btn` button — referenced by both JS functions and CSS

- [ ] **Step 1: Add backdrop div before `#app`**

Find (~line 625):
```html
<div id="app">
```

Insert immediately before it:
```html
<div id="mob-backdrop" onclick="closeMobileMenu()"></div>
```

- [ ] **Step 2: Add hamburger button as first child of `#topbar`**

Find (~line 658):
```html
  <header id="topbar">
    <div class="topbar-title" id="topbar-title">Dashboard</div>
```

Replace with:
```html
  <header id="topbar">
    <button id="mob-menu-btn" onclick="toggleMobileMenu()" aria-label="Open menu">
      <i class="ti ti-menu-2"></i>
    </button>
    <div class="topbar-title" id="topbar-title">Dashboard</div>
```

- [ ] **Step 3: Wrap "Log Entry" button text in `.btn-text` span**

Find (~line 661):
```html
    <button class="topbar-btn-ghost" onclick="openModal('log-modal')">
      <i class="ti ti-plus" style="font-size:13px;"></i> Log Entry
    </button>
```

Replace with:
```html
    <button class="topbar-btn-ghost" onclick="openModal('log-modal')">
      <i class="ti ti-plus" style="font-size:13px;"></i><span class="btn-text"> Log Entry</span>
    </button>
```

- [ ] **Step 4: Replace existing sidebar media query rule and add full overlay CSS**

Find (~line 465):
```css
/* ── Responsive ── */
@media (max-width: 768px) {
  #sidebar { width: var(--sidebar-w-col); }
  .grid-2, .grid-3, .grid-2-1, .grid-1-2 { grid-template-columns: 1fr; }
  #content { padding: 12px; }
}
```

Replace with:
```css
/* ── Mobile menu button ── */
#mob-menu-btn {
  display: none;
  background: none; border: none; color: var(--text-primary);
  font-size: 20px; cursor: pointer; padding: 6px; flex-shrink: 0;
}
#mob-backdrop {
  display: none; position: fixed; inset: 0;
  background: rgba(0,0,0,0.5); z-index: 99;
}

/* ── Responsive ── */
@media (max-width: 768px) {
  #mob-menu-btn { display: flex; align-items: center; }
  #sidebar {
    position: fixed; top: 0; left: 0; height: 100vh;
    width: var(--sidebar-w); z-index: 100;
    transform: translateX(calc(-1 * var(--sidebar-w)));
    transition: transform 0.22s ease;
  }
  #sidebar.mob-open { transform: translateX(0); }
  #mob-backdrop.mob-open { display: block; }
  .btn-text { display: none; }
  .grid-2, .grid-3, .grid-2-1, .grid-1-2 { grid-template-columns: 1fr; }
  #content { padding: 12px; }
}
```

- [ ] **Step 5: Add `toggleMobileMenu` and `closeMobileMenu` JS functions**

Find the `function nav(page)` declaration (~line 2237). Insert these two functions immediately before it:

```js
function toggleMobileMenu() {
  const open = document.getElementById('sidebar').classList.toggle('mob-open');
  document.getElementById('mob-backdrop').classList.toggle('mob-open', open);
}
function closeMobileMenu() {
  document.getElementById('sidebar').classList.remove('mob-open');
  document.getElementById('mob-backdrop').classList.remove('mob-open');
}
```

- [ ] **Step 6: Call `closeMobileMenu()` at the top of `nav(page)`**

Find (~line 2237):
```js
function nav(page) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
```

Replace with:
```js
function nav(page) {
  closeMobileMenu();
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
```

- [ ] **Step 7: Verify**

```bash
grep -n 'mob-menu-btn\|mob-backdrop\|toggleMobileMenu\|closeMobileMenu\|btn-text' index.html
```

Expected: `mob-menu-btn` appears in HTML + CSS + JS; `mob-backdrop` in HTML + CSS + JS; `toggleMobileMenu` in HTML onclick + JS definition; `closeMobileMenu` in HTML onclick + JS definition + `nav()` call; `btn-text` in HTML span + CSS hide rule.

- [ ] **Step 8: Smoke test**

Open `index.html` in a browser. Resize to ≤768px width. Confirm:
- Sidebar is hidden (not visible)
- Hamburger (`☰`) icon appears in topbar left
- "Log Entry" button shows icon only (no text)
- Tapping hamburger slides sidebar in over content
- Dark backdrop appears behind sidebar
- Tapping backdrop closes sidebar
- Clicking any nav item closes sidebar and navigates

- [ ] **Step 9: Commit**

```bash
git add index.html
git commit -m "feat: hamburger overlay sidebar for mobile"
```

---

### Task 2: Metric Cards 2×2 + Form Rows Stack + Modal Padding

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: existing `@media (max-width: 768px)` block from Task 1
- Produces: `.metrics-grid` reflows to 2×2 on mobile; `.form-row` stacks to 1 column; `.modal` has reduced padding

- [ ] **Step 1: Add metric card and form fixes to media query**

Find the responsive media query block added in Task 1:
```css
@media (max-width: 768px) {
  #mob-menu-btn { display: flex; align-items: center; }
  #sidebar {
    position: fixed; top: 0; left: 0; height: 100vh;
    width: var(--sidebar-w); z-index: 100;
    transform: translateX(calc(-1 * var(--sidebar-w)));
    transition: transform 0.22s ease;
  }
  #sidebar.mob-open { transform: translateX(0); }
  #mob-backdrop.mob-open { display: block; }
  .btn-text { display: none; }
  .grid-2, .grid-3, .grid-2-1, .grid-1-2 { grid-template-columns: 1fr; }
  #content { padding: 12px; }
}
```

Replace with:
```css
@media (max-width: 768px) {
  #mob-menu-btn { display: flex; align-items: center; }
  #sidebar {
    position: fixed; top: 0; left: 0; height: 100vh;
    width: var(--sidebar-w); z-index: 100;
    transform: translateX(calc(-1 * var(--sidebar-w)));
    transition: transform 0.22s ease;
  }
  #sidebar.mob-open { transform: translateX(0); }
  #mob-backdrop.mob-open { display: block; }
  .btn-text { display: none; }
  .grid-2, .grid-3, .grid-2-1, .grid-1-2 { grid-template-columns: 1fr; }
  #content { padding: 12px; }
  .metrics-grid { display: grid; grid-template-columns: 1fr 1fr; }
  .form-row { grid-template-columns: 1fr; }
  .modal { padding: 16px; }
}
```

- [ ] **Step 2: Verify**

```bash
grep -n 'metrics-grid\|form-row\|\.modal {' index.html | head -20
```

Expected: `metrics-grid` appears in CSS definition + new media query rule; `form-row` appears in CSS definition + new media query rule; `.modal {` shows padding in media query.

- [ ] **Step 3: Smoke test**

Resize browser to ≤768px. Navigate to Dashboard. Confirm:
- 4 metric cards (Weight, Blood Pressure, Glucose, Mood) display as 2×2 grid — two per row
- Open "Log Entry" modal — form pairs (Date/Time) stack vertically, inputs are full width
- Open the Insulin Log "+ Add" modal — same stacking behavior

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: 2x2 metric cards and stacked form rows on mobile"
```

---

### Task 3: Table Column Hiding

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `renderInsulinLog()` function (~line 2841) — adds `class="col-secondary"` to BG Before, Carbs, and Notes `<th>`/`<td>`
- Consumes: `renderVitalsPage()` function (~line 2732) — adds `class="col-secondary"` to Notes `<th>`/`<td>`
- Produces: `.col-secondary { display: none; }` CSS rule in media query

- [ ] **Step 1: Add `.col-secondary` rule to media query**

Find the responsive media query from Task 2. Add one line:

Find:
```css
  .modal { padding: 16px; }
}
```

Replace with:
```css
  .modal { padding: 16px; }
  .col-secondary { display: none; }
}
```

- [ ] **Step 2: Update `renderInsulinLog()` — add `col-secondary` to BG Before, Carbs, Notes**

Find the `<thead>` row in `renderInsulinLog` (~line 2882):
```js
    <thead><tr style="border-bottom:0.5px solid var(--border);">
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Date / Time</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Type</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Name</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Units</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">BG Before</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Carbs</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">BG After</th>
    </tr></thead>
```

Replace with:
```js
    <thead><tr style="border-bottom:0.5px solid var(--border);">
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Date / Time</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Type</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Name</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Units</th>
      <th class="col-secondary" style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">BG Before</th>
      <th class="col-secondary" style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">Carbs</th>
      <th style="padding:6px;font-size:11px;color:var(--text-muted);font-weight:500;text-align:left;">BG After</th>
    </tr></thead>
```

Then find the `<tr>` row template in `renderInsulinLog` (~line 2868):
```js
    return `<tr style="border-bottom:0.5px solid var(--border);">
      <td style="padding:8px 6px;font-size:12px;color:var(--text-secondary);white-space:nowrap;">${escHtml(dateLabel)}</td>
      <td style="padding:8px 6px;">${badge}</td>
      <td style="padding:8px 6px;font-size:12px;">${escHtml(e.name)}</td>
      <td style="padding:8px 6px;font-size:12px;font-family:var(--font-data);">${escHtml(String(e.units))}u</td>
      <td style="padding:8px 6px;font-size:12px;color:var(--text-muted);">${e.bg_before != null ? escHtml(String(e.bg_before)) : '—'}</td>
      <td style="padding:8px 6px;font-size:12px;color:var(--text-muted);">${e.carbs != null ? escHtml(String(e.carbs)) + 'g' : '—'}</td>
      <td style="padding:8px 6px;font-size:12px;">${bgAfter}</td>
    </tr>`;
```

Replace with:
```js
    return `<tr style="border-bottom:0.5px solid var(--border);">
      <td style="padding:8px 6px;font-size:12px;color:var(--text-secondary);white-space:nowrap;">${escHtml(dateLabel)}</td>
      <td style="padding:8px 6px;">${badge}</td>
      <td style="padding:8px 6px;font-size:12px;">${escHtml(e.name)}</td>
      <td style="padding:8px 6px;font-size:12px;font-family:var(--font-data);">${escHtml(String(e.units))}u</td>
      <td class="col-secondary" style="padding:8px 6px;font-size:12px;color:var(--text-muted);">${e.bg_before != null ? escHtml(String(e.bg_before)) : '—'}</td>
      <td class="col-secondary" style="padding:8px 6px;font-size:12px;color:var(--text-muted);">${e.carbs != null ? escHtml(String(e.carbs)) + 'g' : '—'}</td>
      <td style="padding:8px 6px;font-size:12px;">${bgAfter}</td>
    </tr>`;
```

- [ ] **Step 3: Update `renderVitalsPage()` — add `col-secondary` to Notes column**

Find the table header in `renderVitalsPage` (~line 2745):
```js
      <thead>
        <tr>
          <th>Date</th><th>Weight</th><th>Blood Pressure</th><th>Glucose</th><th>HR</th><th>Mood</th><th>Energy</th><th>Notes</th>
        </tr>
      </thead>
```

Replace with:
```js
      <thead>
        <tr>
          <th>Date</th><th>Weight</th><th>Blood Pressure</th><th>Glucose</th><th>HR</th><th>Mood</th><th>Energy</th><th class="col-secondary">Notes</th>
        </tr>
      </thead>
```

Find the `<tr>` row template in `renderVitalsPage` (~line 2756):
```js
          <tr>
            <td class="mono">${l.date}</td>
            <td class="mono">${l.weight ? l.weight+' lbs' : '—'}</td>
            <td class="mono">${l.bp || '—'}</td>
            <td class="mono">${l.glucose ? l.glucose+' mg/dL' : '—'}</td>
            <td class="mono">${l.hr ? l.hr+' bpm' : '—'}</td>
            <td class="mono">${l.mood ? l.mood+'/10' : '—'}</td>
            <td class="mono">${l.energy ? l.energy+'/10' : '—'}</td>
            <td style="color:var(--text-muted);font-size:12px;">${l.notes || ''}</td>
          </tr>
```

Replace with:
```js
          <tr>
            <td class="mono">${l.date}</td>
            <td class="mono">${l.weight ? l.weight+' lbs' : '—'}</td>
            <td class="mono">${l.bp || '—'}</td>
            <td class="mono">${l.glucose ? l.glucose+' mg/dL' : '—'}</td>
            <td class="mono">${l.hr ? l.hr+' bpm' : '—'}</td>
            <td class="mono">${l.mood ? l.mood+'/10' : '—'}</td>
            <td class="mono">${l.energy ? l.energy+'/10' : '—'}</td>
            <td class="col-secondary" style="color:var(--text-muted);font-size:12px;">${l.notes || ''}</td>
          </tr>
```

- [ ] **Step 4: Verify**

```bash
grep -n 'col-secondary' index.html
```

Expected: 7 occurrences — 1 in CSS media query, 2 in insulin `<th>`, 2 in insulin `<td>` template, 1 in vitals `<th>`, 1 in vitals `<td>` template.

- [ ] **Step 5: Smoke test**

Resize to ≤768px. Navigate to Health Log:
- Insulin table shows: Date/Time, Type, Name, Units, BG After — BG Before and Carbs columns hidden
- Vitals table shows: Date, Weight, BP, Glucose, HR, Mood, Energy — Notes column hidden

Resize to >768px — all columns reappear.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat: hide secondary table columns on mobile"
```

---

### Task 4: Compound Rows + Calculator Inline Grids + Gantt Label

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `.log-compound-row` HTML elements (~lines 797, 2652, 2658, 2659) — existing class retained, inline style removed and replaced by CSS
- Produces: `.log-compound-row` CSS class, `.calc-inputs-grid`, `.calc-freq-grid`, `.calc-stats-grid`, `.calc-peptide-grid` CSS classes, updated gantt label in media query

- [ ] **Step 1: Add CSS classes for all inline grids**

Find the `.gantt-label` CSS rule (~line 492):
```css
.gantt-label { width: 100px; font-size: 11px; color: var(--text-secondary); text-align: right; flex-shrink: 0; }
```

Insert the following block immediately after it (before the next CSS rule):
```css
.log-compound-row {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr auto;
  gap: 8px;
  align-items: end;
  margin-bottom: 8px;
}
.calc-inputs-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 14px; margin-bottom: 16px; }
.calc-freq-grid   { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 20px; }
.calc-stats-grid  { display: grid; grid-template-columns: repeat(3,1fr); gap: 10px; margin-top: 4px; }
.calc-peptide-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; max-width: 780px; }
```

- [ ] **Step 2: Add mobile overrides to media query**

Find the end of the media query block:
```css
  .col-secondary { display: none; }
}
```

Replace with:
```css
  .col-secondary { display: none; }
  .log-compound-row { grid-template-columns: 1fr 1fr; grid-template-rows: auto auto; }
  .log-compound-row > *:first-child { grid-column: 1 / -1; }
  .calc-inputs-grid { grid-template-columns: 1fr; }
  .calc-freq-grid   { grid-template-columns: 1fr; }
  .calc-stats-grid  { grid-template-columns: 1fr 1fr; }
  .calc-peptide-grid { grid-template-columns: 1fr; }
  .gantt-label { width: 70px; }
}
```

- [ ] **Step 3: Remove inline style from `log-compound-row` HTML (the template in page HTML)**

Find (~line 797):
```html
            <div class="log-compound-row" style="display:grid;grid-template-columns:2fr 1fr 1fr auto;gap:8px;align-items:end;margin-bottom:8px;">
```

Replace with:
```html
            <div class="log-compound-row">
```

- [ ] **Step 4: Replace inline styles on Calculator page with CSS classes**

Note: the spec referred to these as "Compounds page" grids but they are actually on the Calculator page (`#page-calculator`). The implementation targets the correct location. Also note: `addCompoundRow()` only clones the DOM node — it never sets inline styles — so removing the inline style from the HTML template in Step 3 is sufficient; no JS change needed.

Find (~line 1358) in the AAS calculator tab:
```html
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:14px;margin-bottom:16px;">
```
Replace with:
```html
        <div class="calc-inputs-grid">
```

Find (~line 1373):
```html
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:20px;">
```
Replace with:
```html
        <div class="calc-freq-grid">
```

Find (~line 1415):
```html
        <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:4px;">
```
Replace with:
```html
        <div class="calc-stats-grid">
```

Find (~line 1435):
```html
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;max-width:780px;">
```
Replace with:
```html
        <div class="calc-peptide-grid">
```

- [ ] **Step 5: Verify**

```bash
grep -n 'log-compound-row\|calc-inputs-grid\|calc-freq-grid\|calc-stats-grid\|calc-peptide-grid\|gantt-label' index.html
```

Expected:
- `log-compound-row` appears in CSS definition, mobile override, HTML template, and JS clone/remove lines — no occurrences with `style="display:grid"`
- `calc-inputs-grid`, `calc-freq-grid`, `calc-stats-grid`, `calc-peptide-grid` each appear twice (CSS + HTML)
- `gantt-label` appears in CSS definition + mobile override

- [ ] **Step 6: Smoke test**

Resize to ≤768px:
- **Log Entry page**: Add a compound row — compound name spans full width, dose and unit on one row beneath it
- **Calculator page** (AAS tab): three input fields (Compound, Weekly Dose, Concentration) stack to 1 column; steady-state stats show as 2 columns
- **Calculator page** (Peptide tab): two-column layout stacks to 1 column
- **Protocol Builder** timeline: gantt labels are 70px instead of 100px

Resize to >768px — all layouts restore to desktop column counts.

- [ ] **Step 7: Commit and push**

```bash
git add index.html
git commit -m "feat: responsive compound rows, calculator grids, gantt label on mobile"
git push
```
