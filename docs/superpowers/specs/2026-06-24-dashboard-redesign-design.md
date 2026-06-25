# Dashboard Redesign — Design Spec
_2026-06-24_

## Overview

Redesign the dashboard to optimize for two daily use cases: "what do I need to do today" and "where am I in my cycle." The current layout splits protocol and upcoming info across two side-by-side cards and has a sparse 3-card vitals row after blood labs removal. The new layout promotes a single full-width hero protocol card and a compact 4-card vitals row.

No new data model changes. All data comes from existing sources: `hrt_active_protocol_data` (localStorage), `hrt_vitals_log` (localStorage).

---

## 1. Hero Protocol Card

Replaces the current side-by-side "Active Protocol" + "Upcoming" two-column layout. Spans full width at the top of the dashboard.

### When no active protocol

```
No active protocol. Build one →   (links to nav('builder'))
```

Single line, no card chrome needed — or a minimal card with this prompt.

### When protocol is active (`status === 'active'`)

#### Header row
- Left: **protocol name** in `card-title` style + status badge (same badge style as My Protocols page)
- Right: **"Week X of Y · Z%"** in `var(--primary-bright)` / `var(--font-data)`

#### Progress bar
Existing `cycle-bar` progress bar, unchanged.

#### Week timeline strip
A horizontal row of small squares — one per week of the cycle.

- **Past weeks** (< currentWeek): filled `var(--primary)` at 30% opacity
- **Current week**: filled `var(--primary)`, labeled "Wk N" below the strip
- **Future weeks** (> currentWeek): outlined border only, fill transparent
- Square size: 14×14px, gap: 3px
- Strip scrolls horizontally (CSS `overflow-x: auto`) for cycles longer than fits the card width (~16+ weeks on mobile)
- Hidden entirely when `!protocol.startDate` (can't compute current week without a start date)

#### Steady-state bar
Existing `ss-bar` + `ss-label`, unchanged, shown below the timeline strip.

#### Today's injections
Label: **"TODAY'S INJECTIONS"** in `var(--green)`, 10px uppercase.

Compound rows using the existing `renderCycleProgress` compound row format:
- Name / dose / frequency on one line
- Timing line below: "Due today" (green) / "Next dose tomorrow" / "Next dose in N days" / "Every day"

Compounds are already filtered to those active in the current week by `buildWeekGrid`.

#### Upcoming changes
Existing upcoming section — dose changes and new compound starts within the next 4 weeks. Same format, same data source.

#### Cycle-end banner
Existing amber banner when `totalWeeks - currentWeek <= 3`. Unchanged.

### When protocol exists but `status !== 'active'` or no `startDate`

Show the protocol name + status badge. Hide the timeline strip and today's injections. Show cycle progress bar at 0% with "—" labels (existing guard behavior).

---

## 2. Compact Vitals Row

Four equal-width cards in a single `display:flex; gap` row, replacing the current 3-card `metrics-grid`.

| Card | Label | ID | Data source | Unit | Delta |
|---|---|---|---|---|---|
| Weight | Weight | `m-weight` | `hrt_vitals_log[].weight` | lbs | ↑/↓ vs previous entry |
| Blood Pressure | Blood Pressure | `m-bp` | `hrt_vitals_log[].bp` | mmHg | none |
| Glucose | Glucose | `m-glucose` | `hrt_vitals_log[].glucose` | mg/dL | ↑/↓ vs previous entry |
| Mood | Mood | `m-mood` | `hrt_vitals_log[].mood` | /10 | ↑/↓ vs previous entry |

The Mood card is new. `mood` is already logged (slider, 1–10) and stored in `hrt_vitals_log`. `renderVitalsToCards` is updated to populate `m-mood` alongside the existing three cards.

All four cards use the existing `metric-card` + `updateMetricCard()` pattern. No new CSS needed.

The existing `metrics-grid` CSS class is replaced with a flex row. The `mc-*` color classes stay:
- Weight: `mc-amber`
- Blood Pressure: `mc-red`
- Glucose: `mc-purple`
- Mood: `mc-teal`

---

## 3. Weight Chart

Unchanged. Stays below the vitals row.

---

## 4. What Is Removed

| Element | Reason |
|---|---|
| Right-column "Upcoming" card | Upcoming doses absorbed into hero card |
| "Last Entry" summary in right card | Redundant with vitals cards |
| Mood 7d sparkline | Replaced by Mood metric card |
| Energy 7d sparkline | Dropped — mood is sufficient |
| Log streak counter | Dropped — not core to either use case |
| `adherence-badge` span | No longer has a container |
| `grid-2-1` layout wrapper | Replaced by full-width hero card + flex vitals row |

---

## 5. Layout Structure (after redesign)

```
┌─────────────────────────────────────────┐
│  Hero Protocol Card (full width)        │
│  · Name + badge          Wk 7/12 · 58% │
│  · Progress bar                         │
│  · Week strip: ■■■■■■●○○○○○            │
│  · Steady state                         │
│  · Today's injections                   │
│  · Upcoming changes                     │
└─────────────────────────────────────────┘
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│Weight│ │  BP  │ │Gluc. │ │ Mood │   ← vitals row
└──────┘ └──────┘ └──────┘ └──────┘
┌─────────────────────────────────────────┐
│  Weight & Body Comp chart               │
└─────────────────────────────────────────┘
```

---

## 6. Scope and Constraints

- All changes confined to `index-v2.html`
- No new localStorage keys
- No Supabase calls
- No new CSS files — use existing variables and classes throughout
- `renderCycleProgress(rawProtocol)` is updated in-place (or split into a helper for the strip)
- `renderVitalsToCards()` updated to add `m-mood` population
- The `#metrics-grid` element's CSS class changes from grid to flex row
- Existing IDs (`m-weight`, `m-bp`, `m-glucose`, `cycle-bar`, `ss-bar`, `ss-label`, `cycle-label`, `cycle-pct`, `cycle-active-compounds`) are preserved so all existing render functions continue to work
- New IDs added: `m-mood`, `m-mood-badge`, `m-mood-delta`, `cycle-week-strip`

---

## 7. What Is NOT in Scope

- No "mark injection as done" / quick-log from dashboard
- No push notifications or reminders
- No AI summary or coaching text
- No changes to Vitals, Log Entry, Protocols, Builder, Calculator, or Compounds pages
- No energy sparkline (dropped entirely)
- No log streak (dropped entirely)
