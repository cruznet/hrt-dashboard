# HealthKit Tab — Implementation Spec (v2 Supabase Dashboard)

## Goal

Add a `page-healthkit` page to `index.html` that visualizes Apple Health data from `healthkit-data.csv`.

This page does **not** exist yet. It is the next feature to implement.

---

## Data source

**File:** `healthkit-data.csv` (already in project root)
**Format:** One row per day. Columns include:

| Column | Use |
|---|---|
| `Date/Time` | X-axis for all charts |
| `Weight (lbs)` | Weight trend |
| `Body Fat Percentage (%)` | Body comp |
| `Lean Body Mass (lbs)` | Body comp |
| `Heart Rate Variability (ms)` | Key HRT health marker — highlight prominently |
| `Resting Heart Rate (bpm)` | Cardiovascular |
| `Sleep Analysis [Total] (hr)` | Sleep |
| `Sleep Analysis [Deep] (hr)` | Sleep breakdown |
| `Sleep Analysis [REM] (hr)` | Sleep breakdown |
| `Sleep Analysis [Core] (hr)` | Sleep breakdown |
| `Sleep Analysis [Awake] (hr)` | Sleep breakdown |
| `Step Count (steps)` | Activity |
| `Active Energy (kcal)` | Activity |
| `Walking + Running Distance (mi)` | Activity |

---

## Implementation

### 1 — Add nav entry (sidebar + bottom bar)

In the sidebar nav list, add:
```html
<div class="nav-item" onclick="nav('healthkit')">
  <i class="ti ti-heart-rate-monitor"></i>
  <span class="nav-text">HealthKit</span>
</div>
```

In the mobile bottom tab bar `More` menu (or as a 6th item if space allows).

Wire into `nav()` — add `'healthkit': 'HealthKit'` to the `PAGE_TITLES` map and call `renderHealthKitPage()` when navigating there.

### 2 — Add page section

After `page-compliance` and before `page-protocols`:
```html
<section class="page" id="page-healthkit">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;padding-bottom:12px;border-bottom:0.5px solid var(--border);">
    <div style="font-size:15px;font-weight:600;color:var(--text-primary);">HealthKit</div>
    <div id="hk-last-sync" style="font-size:12px;color:var(--text-muted);"></div>
  </div>
  <div id="hk-kpi-row" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin-bottom:16px;"></div>
  <div id="hk-charts"></div>
</section>
```

### 3 — CSV parser

```js
async function hkLoadCSV() {
  const resp = await fetch('healthkit-data.csv');
  const text = await resp.text();
  const lines = text.trim().split('\n');
  const headers = lines[0].split(',').map(h => h.trim());
  return lines.slice(1).map(line => {
    const vals = line.split(',');
    const row = {};
    headers.forEach((h, i) => row[h] = vals[i]?.trim() || '');
    return row;
  });
}
```

### 4 — Page render

```js
async function renderHealthKitPage() {
  const rows = await hkLoadCSV();
  if (!rows.length) return;
  const sorted = rows.sort((a, b) => a['Date/Time'].localeCompare(b['Date/Time']));
  const latest = sorted[sorted.length - 1];

  // KPI cards (latest values)
  hkRenderKpis(latest);

  // Charts
  hkRenderCharts(sorted);

  // Last sync label
  const el = document.getElementById('hk-last-sync');
  if (el) el.textContent = `Last entry: ${latest['Date/Time']}`;
}
```

### 5 — KPI cards

Show 6 stat cards from latest row using existing card markup pattern:

| Metric | Column | Color |
|---|---|---|
| HRV | `Heart Rate Variability (ms)` | `--teal` — most important HRT marker |
| Resting HR | `Resting Heart Rate (bpm)` | `--primary-bright` |
| Weight | `Weight (lbs)` | `--text-primary` |
| Body Fat | `Body Fat Percentage (%)` | `--amber` |
| Sleep | `Sleep Analysis [Total] (hr)` | `--purple` |
| Steps | `Step Count (steps)` | `--green` |

### 6 — Charts (use `makeChart()`)

| Chart | Type | Color |
|---|---|---|
| HRV trend (30 days) | Line | `--teal` |
| Weight trend (30 days) | Line | `--primary-bright` |
| Sleep breakdown (stacked bar) | Bar (stacked) | Deep=`--purple`, REM=`--teal`, Core=`--primary-bright`, Awake=`--red` |
| Step count (bar) | Bar | `--green` |

Use `makeChart()` — it handles canvas re-use correctly.

---

## Styling rules

- Use existing CSS variables only — no hardcoded colors
- Card markup: `class="card"` with `background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);padding:16px`
- Numeric values in `font-family: var(--font-data)`
- Chart containers: `<div style="margin-bottom:16px;"><canvas id="hk-chart-hrv"></canvas></div>`

---

## Future: automated CSV refresh

`healthkit-sync.gs` (Google Apps Script) is scaffolded for future use. It can push a refreshed CSV from Apple Health to the project on a schedule. Not required for initial implementation — static CSV is sufficient.

---

## Notes

- `healthkit-data.csv` is served as a static asset by Cloudflare Workers alongside `index.html`
- Parser uses `fetch('healthkit-data.csv')` — works both locally (`python3 server.py`) and in production
- HRV is the most clinically significant HRT marker — low HRV correlates with protocol stress. Make it the first and largest KPI.
