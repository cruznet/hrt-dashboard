# Mobile Layout — Design Spec
_2026-06-28_

## Overview

The dashboard currently has a single 768px breakpoint that collapses grid layouts but leaves the sidebar as a 52px icon bar and fails to reflow metric cards, form rows, inline grids, or table columns. This sprint makes the full app usable on phones by fixing all five problem areas.

All changes are CSS-only except for: (1) a hamburger button added to the topbar HTML, (2) two JS functions for sidebar open/close, and (3) table column `<th>`/`<td>` elements gaining a CSS class for column-hide targeting. No new files.

---

## 1. Navigation — Hamburger Overlay Sidebar

### Behavior

On mobile (≤768px), the sidebar is fully hidden off-screen via `transform: translateX(-200px)` and `opacity: 0`. A hamburger button (`☰`) appears at the far left of the topbar. Tapping it slides the sidebar in as a full-height overlay on top of content. A semi-transparent backdrop (`rgba(0,0,0,0.5)`) covers the content area behind the sidebar.

Tapping the backdrop closes the sidebar. Navigating to any page (clicking a nav item) also closes the sidebar.

### Topbar changes on mobile

- Hamburger icon (`<button id="mob-menu-btn">`) added as first child of `#topbar`
- Visible only on mobile (`display:none` on desktop, `display:flex` on mobile)
- "Log Entry" button text hidden on mobile — icon (`ti-plus`) only, via `.topbar-btn-ghost .btn-text { display:none }` at ≤768px
- Avatar stays on the right — no change needed

### HTML additions

```html
<!-- First child of #topbar -->
<button id="mob-menu-btn" onclick="toggleMobileMenu()" aria-label="Open menu">
  <i class="ti ti-menu-2"></i>
</button>

<!-- Backdrop — direct child of body, before #app -->
<div id="mob-backdrop" onclick="closeMobileMenu()"></div>
```

### JS additions

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

`closeMobileMenu()` is called at the top of the existing `nav(page)` function.

### CSS

```css
#mob-menu-btn {
  display: none;
  background: none; border: none; color: var(--text-primary);
  font-size: 20px; cursor: pointer; padding: 6px;
}
#mob-backdrop {
  display: none; position: fixed; inset: 0;
  background: rgba(0,0,0,0.5); z-index: 99;
}

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
  .topbar-btn-ghost .btn-text { display: none; }
}
```

Remove the existing `@media (max-width: 768px) { #sidebar { width: var(--sidebar-w-col); } }` rule.

---

## 2. Dashboard — Metric Cards 2×2

### Problem

`.metrics-grid` is a flex row — all 4 cards (Weight, Blood Pressure, Glucose, Mood) squeeze into one row on mobile, each ~70px wide and unreadable.

### Fix

```css
@media (max-width: 768px) {
  .metrics-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
  }
}
```

The existing `.grid-2`, `.grid-3`, `.grid-2-1`, `.grid-1-2` collapse to `1fr` already — no change needed there.

---

## 3. Forms — Stack `.form-row` + Reduce Modal Padding

### Problem

`.form-row { grid-template-columns: 1fr 1fr }` is not in the media query, so paired inputs (Date/Time, BG Before/After, Weight/Body Fat, etc.) stay side-by-side on mobile.

Modal inner padding is 28px — generous on desktop but wasteful on narrow screens.

### Fix

```css
@media (max-width: 768px) {
  .form-row { grid-template-columns: 1fr; }
  .modal { padding: 16px; }
}
```

Applies to: Log Entry modal, Insulin Log modal, Protocol Builder form, all other `.form-row` usages.

---

## 4. Tables — Hide Secondary Columns

Secondary columns are hidden via a CSS class `.col-secondary` added to the `<th>` and `<td>` of each column in the HTML. A single media query hides them all.

### Column mapping

| Table | Columns hidden (`col-secondary`) |
|---|---|
| Insulin Log | Carbs `<th>`/`<td>`, BG Before `<th>`/`<td>`, Notes `<th>`/`<td>` |
| Vitals / Daily Log | Notes `<th>`/`<td>` |
| Administration Log | Route `<th>`/`<td>`, Notes `<th>`/`<td>` |

### CSS

```css
@media (max-width: 768px) {
  .col-secondary { display: none; }
}
```

### Implementation note

The Insulin Log and Administration Log tables are rendered by JS (`renderInsulinLog`, the admin log renderer). The `<th>` and `<td>` elements in those renderers gain `class="col-secondary"` where applicable. The Vitals Daily Log table is also JS-rendered — same approach.

---

## 5. Page-Specific Inline Grid Fixes

### 5a. Log Entry — Compound Rows

The `.log-compound-row` element uses an inline style:
`grid-template-columns: 2fr 1fr 1fr auto`

This is applied in the JS that renders compound rows. Replace the inline style with a CSS class `log-compound-row` and define it in the stylesheet:

```css
.log-compound-row {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr auto;
  gap: 8px;
  align-items: center;
}
@media (max-width: 768px) {
  .log-compound-row {
    grid-template-columns: 1fr 1fr;
    grid-template-rows: auto auto;
  }
  .log-compound-row > *:first-child { grid-column: 1 / -1; } /* name spans full width */
}
```

### 5b. Compounds Page — Inline Grids

Three inline grid styles on the Compounds page:
- `grid-template-columns: 1fr 1fr 1fr` (filter row)
- `grid-template-columns: 1fr 1fr` (compound form fields)
- `grid-template-columns: repeat(3,1fr)` (compound cards)

Each gets a CSS class replacing the inline style:

| Class | Desktop | Mobile |
|---|---|---|
| `.cpd-filter-row` | `1fr 1fr 1fr` | `1fr` |
| `.cpd-form-row` | `1fr 1fr` | `1fr` |
| `.cpd-cards-grid` | `repeat(3,1fr)` | `1fr` |

### 5c. Protocol Builder — Gantt Label

`.gantt-label { width: 100px; flex-shrink: 0; }` — fixed width that squeezes the timeline on mobile.

```css
@media (max-width: 768px) {
  .gantt-label { width: 70px; font-size: 11px; }
}
```

---

## 6. Scope and Constraints

- All changes confined to `index.html`
- No new files, no new localStorage keys, no Supabase changes
- Breakpoint stays at 768px — no new breakpoints added
- `page-vitals`, `nav('vitals')`, and all internal IDs unchanged
- The 52px collapsed sidebar state (`.collapsed` class) is preserved for desktop use; on mobile the overlay pattern replaces it
- No changes to chart rendering logic — charts already fill their container width

---

## 7. What Is NOT in Scope

- Tablet-specific layouts (768px–1024px)
- Bottom tab bar navigation
- Horizontal scroll on tables
- Touch gestures (swipe to open/close sidebar)
- PWA / install-to-homescreen
- Font size scaling for accessibility
