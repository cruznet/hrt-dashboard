# Mood & Energy Trend Charts — Design Spec
_2026-06-25_

## Overview

Add two trend charts to the dashboard — Mood and Energy — showing values over the current cycle window. The weight chart is updated to use the same window so all three charts are temporally aligned and directly comparable. A shared helper extracts the cycle-windowed data slice used by all three charts.

No new data model changes. All data comes from existing sources: `hrt_active_protocol_data` (localStorage) for cycle context, `hrt_vitals_log` (localStorage) for chart values.

---

## 1. Chart Specs

| Chart | Title | Canvas ID | Empty ID | Color | Y-axis |
|---|---|---|---|---|---|
| Mood | Mood Trend | `chart-mood` | `chart-mood-empty` | `var(--purple)` | 1–10 |
| Energy | Energy Trend | `chart-energy` | `chart-energy-empty` | `var(--amber)` | 1–10 |

Both charts:
- Type: `line`
- Height: `180px` (same as weight chart)
- Dataset label: `"Mood (1–10)"` / `"Energy (1–10)"`
- `tension: 0.4`, `fill: true`, `pointRadius: 3`
- Background fill: `rgba` of the line color at 8% opacity — `rgba(168,85,247,0.08)` for mood, `rgba(245,158,11,0.08)` for energy
- Point color: lighter tint — `#C084FC` for mood, `#FCD34D` for energy
- Use existing `makeChart(id, 'line', labels, datasets)` — no new Chart.js options needed

---

## 2. Data Window (shared by all three charts)

A new pure helper function `getCycleChartData(logs, fieldKey)` replaces the inline slice logic currently in the weight chart. It is used by all three charts.

```
getCycleChartData(logs, fieldKey, protocol) → { entries, labels }
```

**Inputs:**
- `logs` — `hrt_vitals_log` array, newest-first
- `fieldKey` — `'weight'`, `'mood'`, or `'energy'`
- `protocol` — parsed `hrt_active_protocol_data` object, or `null`

**Logic:**
1. Filter `logs` to entries where `entry[fieldKey]` is truthy and `parseFloat(entry[fieldKey]) > 0`.
2. If `protocol && protocol.startDate && protocol.cycleLengthWeeks > 0`, filter to entries where `entry.date >= protocol.startDate`. Set `usingCycle = true`.
3. Else take up to 30 entries (`.slice(0, 30)`). Set `usingCycle = false`.
4. Reverse to oldest-first for charting.
5. Build labels (see below).
6. Return `{ entries, labels }`.

**Labels:**
- If `usingCycle`: for each entry, compute `weekNum = Math.ceil((daysSinceStart + 1) / 7)` using `protocol.startDate` and the entry's `date`. Label: `"Wk ${weekNum}"`.
- Else: `new Date(entry.date + 'T00:00:00').toLocaleDateString('en-US', { month:'short', day:'numeric' })` — same format as current weight chart.

**Date parsing:** Always use local-time parse: `const [y,m,d] = dateStr.split('-').map(Number); new Date(y, m-1, d)` — never `new Date(dateString)` for date-only strings (timezone bug prevention).

---

## 3. Layout

New `grid-2` row added directly below the existing weight chart row in the dashboard HTML (`page-dashboard` section):

```
┌─────────────────────────────────────────┐
│  Weight & Body Comp  (existing row)     │
└─────────────────────────────────────────┘
┌──────────────────────┐ ┌──────────────────────┐
│  Mood Trend          │ │  Energy Trend         │
│  [purple line chart] │ │  [amber line chart]   │
└──────────────────────┘ └──────────────────────┘
```

Each new card follows the exact same HTML structure as the weight chart card:

```html
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
```

Energy card: same structure, `id="chart-energy"`, `id="chart-energy-empty"`, icon `ti-bolt`, text "No energy data yet".

---

## 4. Render Function

New function `renderMoodEnergyCharts()`:

1. Reads `hrt_vitals_log` via `lsGet('hrt_vitals_log', [])`.
2. Calls `getCycleChartData(logs, 'mood')` and `getCycleChartData(logs, 'energy')`.
3. For each: if `entries.length >= 1`, call `showChart(id)` and `makeChart(id, 'line', labels, [dataset])`. If no entries, leave the empty state visible (no action needed — canvas hidden by default).

**Updated weight chart:** The inline slice logic in `renderVitalsToCards` (currently `weightLogs.slice(0, 30).reverse()`) is replaced with a call to `getCycleChartData(logs, 'weight', protocol)`. Labels are built the same way as mood/energy. The caller reads `hrt_active_protocol_data` once and passes it to all three chart calls.

**Call sites:** `renderMoodEnergyCharts()` is called from:
- `renderVitalsToCards()` — at the end, after the weight chart block
- `renderRealCharts()` — alongside the existing weight/BP/glucose chart calls (Supabase authenticated path)

---

## 5. Edge Cases

| Case | Behavior |
|---|---|
| No entries for a field | Empty state shown, canvas hidden (default state — no action needed) |
| Fewer entries than window | Show all available entries, no padding |
| No active protocol / no `startDate` | Fall back to 30 entries, x-axis uses date labels |
| `cycleLengthWeeks` = 0 or missing | Treated as no cycle — fall back to 30 entries |
| Single entry | Chart renders a single point (Chart.js native behavior) |

---

## 6. Scope and Constraints

- All changes confined to `index-v2.html`
- No new localStorage keys
- No new CSS files — use existing variables and classes
- `getCycleChartData(logs, fieldKey, protocol)` is a pure function — no localStorage access, no DOM access; the caller reads `hrt_active_protocol_data` once and passes the parsed object as `protocol`
- Date parsing always uses local-time construction to prevent timezone off-by-one bugs
- No changes to Vitals, Log Entry, Protocols, Builder, Calculator, or Compounds pages
- No Y-axis min/max forced — Chart.js auto-scales (mood/energy are already bounded 1–10 by the log entry sliders, so auto-scale is fine)

---

## 7. What Is NOT in Scope

- No "zoom" or date range picker
- No export or share for charts
- No annotation of cycle events on the chart (e.g., "started Anavar Wk 9")
- No chart for BP or glucose trend (those exist on the Vitals page already)
- No changes to the Vitals page charts
