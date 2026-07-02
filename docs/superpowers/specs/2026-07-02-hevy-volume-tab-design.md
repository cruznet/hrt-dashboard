# Hevy Volume Tab — Design Spec

**Date:** 2026-07-02  
**Status:** Approved  

---

## Goal

Add a **Volume** tab to the Workouts page that shows training frequency and muscle-group volume trends over time. The key insight for an HRT user: whether protocol adjustments are translating to more consistent training and higher output.

---

## Placement

Fourth tab on the Workouts page, appended to the existing tab row:

```
Recent · PRs · E1RM Trends · Volume
```

No nav changes. No new page. All workout data stays in one place.

---

## Range Toggle

7d / 30d / 90d toggle using the existing `range-pill` / `range-pill-active` CSS pattern (same as Wellness page). Stored in a module-level variable `_hevyVolRange` (default 30). Changing the toggle re-renders the tab in place via `renderHevyVolume(workouts)`.

---

## KPI Cards

Three stat cards in a `grid-template-columns: repeat(3, 1fr)` row, rendered from workouts within the selected window:

| Card | Value | Color |
|---|---|---|
| Total Volume | Sum of all set weight×reps across all workouts in window (lbs) | `--primary-bright` |
| Sessions | Count of workouts in window | `--teal` |
| Avg Session | Total Volume ÷ Sessions | `--text-primary` |

Use existing card markup (`class="card"`, `padding:12px 14px`). Numeric values in `var(--font-data)`.

---

## Frequency Heatmap

One cell per calendar day in the selected window. Same cell-grid layout as the dose compliance heatmap (`renderCompliancePage`).

**Cell color logic:**
- No workout: `var(--bg-card-hover)` (dark, rest day)
- Workout present: teal, brightness scaled by session volume relative to the user's median session volume in the window:
  - Volume ≤ 50% of median: `rgba(34,211,238,0.35)` (light session)
  - Volume 50–100% of median: `rgba(34,211,238,0.65)` (normal session)
  - Volume > 100% of median: `rgba(34,211,238,1.0)` (heavy session)

Cell tooltip (title attribute): date + workout title + volume (e.g. `"2026-06-28 · Push A · 24,500 lbs"`).

Days with no Hevy data at all (before first sync) render as `var(--bg-card)` with no border treatment.

---

## Weekly Volume by Muscle Group (Stacked Bar Chart)

X-axis: ISO week labels (`"Jun 23"`, `"Jun 30"`, etc.) for each week that falls within the selected range.  
Y-axis: Total lbs lifted.  
Chart type: `bar` (stacked) via existing `makeChart()`.

**Four segments per bar** using the existing `hevyWorkoutTag()` categorization:

| Segment | Color |
|---|---|
| Push | `rgba(245,197,24,0.85)` (`--primary-bright`) |
| Pull | `rgba(34,211,238,0.85)` (`--teal`) |
| Legs | `rgba(192,132,252,0.85)` (`--purple`) |
| Other | `rgba(144,144,152,0.5)` (`--text-muted`) |

Chart options: `{ scales: { x: { stacked: true }, y: { stacked: true } } }`.

Canvas ID: `hevy-chart-vol-muscle`.

---

## Data Flow

All computation is pure JS over the cached `hrt_hevy_workouts` localStorage array — no new API calls, no new Supabase tables.

Key helper already in codebase:
- `hevyWorkoutVolume(w)` — total lbs for a workout
- `hevyWorkoutTag(title)` — returns `{ label: 'Push'|'Pull'|'Legs'|'Upper'|'Lower'|'Full'|'Cardio'|'Rest' }`
- `hevyParseMs(t)` — normalizes Hevy timestamps

New helpers needed:
- `hevyVolRange()` — returns `_hevyVolRange` (7 | 30 | 90)
- `hevySetVolRange(days)` — updates `_hevyVolRange`, refreshes active pill, calls `renderHevyVolume(hevyCache())`
- `hevyMuscleTag(workout)` — maps `hevyWorkoutTag` output to Push / Pull / Legs / Other (collapses Upper→Push, Lower→Legs, Full→Push, Cardio→Other)

---

## New Functions

| Function | Purpose |
|---|---|
| `renderHevyVolume(workouts)` | Top-level renderer for the Volume tab — KPIs, heatmap, chart |
| `hevyVolKpis(workouts, cutoff)` | Returns `{ totalVol, sessions, avgSession }` |
| `hevyFreqHeatmap(workouts, days)` | Returns HTML string for the day-cell grid |
| `hevyVolByWeek(workouts, cutoff)` | Returns `{ weeks[], push[], pull[], legs[], other[] }` for chart |
| `hevySetVolRange(days)` | Toggle handler — updates range, re-renders |

---

## Wiring

In `renderWorkoutsPage()`:
```js
if (_hevyTab === 'volume') { renderHevyVolume(workouts); return; }
```

Tab definition added to `hevyRenderTabs()`:
```js
{ key: 'volume', label: 'Volume' },
```

---

## Styling Rules

- All colors via CSS variables — no hardcoded hex except where chart rgba opacity is needed
- Card markup matches existing Workouts page cards
- Heatmap cells: `width:12px; height:12px; border-radius:2px` (matches compliance heatmap)
- Chart container: `<div style="margin-bottom:16px;"><canvas id="hevy-chart-vol-muscle"></canvas></div>`
- No new CSS classes — inline styles only, matching existing patterns

---

## Out of Scope

- Per-exercise volume breakdown (covered by E1RM Trends tab)
- Session duration (Hevy API provides `end_time` but it's sometimes null — unreliable)
- Syncing volume data to Supabase (localStorage is sufficient; Hevy is the source of truth)
