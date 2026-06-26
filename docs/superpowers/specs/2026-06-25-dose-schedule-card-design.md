# Dose Schedule Card — Design Spec
_2026-06-25_

## Overview

Add a **Dose Schedule** card to the dashboard that fills the empty right-column slot in the weight chart row. The card shows today's full compound list with due/not-due status, plus a compact upcoming strip for any non-daily compounds. All-ED protocols show "All daily" instead of the upcoming strip. The weight chart moves to the right column.

No new data model changes. All data comes from `hrt_active_protocol_data` (localStorage).

---

## 1. Layout Change

The existing `<!-- Charts row -->` `grid-2` div currently holds only the weight card. After this change it holds two cards:

```
┌─────────────────────────┐  ┌─────────────────────────┐
│  DOSE SCHEDULE  (left)  │  │  WEIGHT & BODY COMP     │
│  Today's compounds      │  │  [line chart]  (right)  │
│  + upcoming non-daily   │  │                         │
└─────────────────────────┘  └─────────────────────────┘
```

The schedule card HTML is inserted **before** the weight card div inside the `grid-2` div. The weight card HTML is unchanged.

---

## 2. Card Content

### 2a. TODAY section (always shown)

Header: `TODAY · {DayOfWeek} {Month} {Date}` — e.g. "TODAY · Wed Jun 25"

For each compound (in protocol order):
- **Due today** → green dot `●` + compound name (truncated to 22 chars) + dose + unit
- **Not due today** → grey dot `○` + compound name (dimmed, `opacity:0.5`) + dose + unit

Dose shown is the **current phase's dose** (not phase[0] if a phased protocol — see §4).

If no active protocol: show empty state (icon + "No active protocol" + link to My Protocols).

### 2b. UPCOMING section (conditional)

Only rendered when **at least one compound has a non-daily, non-PWO frequency** (`freq` is not `'ED'` and not `'PWO'`, case-insensitive).

Section header: `UPCOMING`

For each of the next 6 days:
- Check which non-daily compounds are due on that day using `isDueOnDate`
- Skip days where zero non-daily compounds are due
- Render: `{DayAbbrev} {Date} · {abbrev1} · {abbrev2} ...`
  - Day abbrev: "Mon", "Tue", etc.
  - Compound abbrev: use `_abbrevCompound(name)` (existing helper)
  - Example: `Wed 25 · TE · NPP`
- Max 5 days shown (to bound card height)

If all compounds are ED/PWO: render instead a single muted line: `All compounds daily`

---

## 3. New Pure Function: `isDueOnDate(freq, startDate, targetDate)`

A generalised version of the existing `isDueToday` that accepts a `targetDate` (JS `Date` object) instead of always using `new Date()`. This is needed so the upcoming strip can check any date in the next 6 days.

**Signature:** `isDueOnDate(freq, startDate, targetDate) → boolean`

**Logic:** Identical to `isDueToday` except every reference to `new Date()` (without args) is replaced by `targetDate`. The `todayDay` variable becomes the day-of-week derived from `targetDate`.

`isDueToday` is left unchanged — it remains the production call site for the hero card and cycle progress. `renderDoseSchedule` uses `isDueOnDate` for both the "today" column and the upcoming strip (passing `new Date()` for today, future dates for the strip).

**Placement:** Defined immediately after `isDueToday` in `index-v2.html`.

**Tests:** 10 assertions in `tests/protocol-logic.html` (before `// ── summary ──`):
1. `ED` → true for any targetDate
2. `PWO` → true for any targetDate
3. `EOD` → day 0 of start true, day 1 false, day 2 true
4. `E3D` → day 0 true, day 1 false, day 3 true
5. `2X/WK` → start day true, start+3 days true, start+1 false
6. `WEEKLY` → start day-of-week true, next day false
7. Array `['Mon','Wed']` → true on Mon, false on Tue
8. Non-ED with `null` startDate → false
9. `E3.5D` → same as `2X/WK`
10. `E4D` → day 0 true, day 2 false, day 4 true

---

## 4. Helper: `currentPhaseDose(phases, startDate)`

Pure function. Returns the dose for the currently active phase of a phased compound.

```js
function currentPhaseDose(phases, startDate) {
  if (!Array.isArray(phases) || !phases.length) return null;
  const week = pbCurrentCycleWeek(startDate);
  const phase = phases.find(ph => week >= ph.startWeek && week <= (ph.endWeek || Infinity));
  return phase ? phase.dose : phases[phases.length - 1].dose;
}
```

Used by `renderDoseSchedule` when displaying each compound's current dose.
Non-phased compounds (detected by `!Array.isArray(c.phases)`) use `normalizeCompound(c).dose` directly.

---

## 5. Render Function: `renderDoseSchedule()`

```
renderDoseSchedule() → void
```

1. Reads `hrt_active_protocol_data` via `lsGet('hrt_active_protocol_data', null)`.
2. If null → renders empty state into `#dose-schedule-content`.
3. Normalizes each compound with `normalizeCompound(c)`.
4. Determines current week via `pbCurrentCycleWeek(protocol.startDate)`.
5. For each compound:
   - If phased (`Array.isArray(raw.phases)`): dose = `currentPhaseDose(raw.phases, startDate)`, unit/freq from `normalizeCompound`
   - Else: dose/unit/freq from `normalizeCompound`
   - `dueToday = isDueOnDate(c.freq, startDate, new Date())`
6. Builds TODAY HTML (§2a).
7. Checks if any compound has non-ED/non-PWO freq → builds UPCOMING strip (§2b) or "All daily" line.
8. Writes to `#dose-schedule-content`.
9. All user-supplied strings (`c.name`, `c.dose`, `c.unit`) passed through `escHtml()`.

**Call sites** — called wherever `renderCycleProgress` is called:
- `loadDemoData()` (~line 1725) — after `renderCycleProgress(p)`
- `loadProtocols()` (~line 2019) — after `renderCycleProgress(p)`
- `renderCycleProgress()` callers at lines ~3067, ~3260

Rather than modifying every call site, `renderDoseSchedule()` is called from **inside `renderCycleProgress(rawProtocol)`** at the end of that function, after all its existing rendering is complete. This ensures both always stay in sync with one call site to maintain.

---

## 6. HTML Structure

### Dose schedule card (new — inserted before weight card)

```html
<div class="card" style="min-height:212px;">
  <div class="card-title">Dose Schedule</div>
  <div id="dose-schedule-content" style="font-size:12px;line-height:1.6;">
    <!-- rendered by renderDoseSchedule() -->
  </div>
</div>
```

`id="dose-schedule-content"` is the single innerHTML target.

### Empty state (rendered into #dose-schedule-content when no protocol)

```html
<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;
            height:160px;gap:6px;text-align:center;">
  <i class="ti ti-calendar-off" style="font-size:28px;color:var(--text-muted);opacity:0.4;"></i>
  <div style="color:var(--text-muted);">No active protocol</div>
  <div style="font-size:11px;color:var(--text-muted);opacity:0.7;">
    <a href="#" onclick="nav('protocols');return false;"
       style="color:var(--primary-bright);">My Protocols →</a>
  </div>
</div>
```

---

## 7. Visual Style

- Green dot: `color:var(--success)` (existing CSS variable)
- Grey dot / dimmed row: `color:var(--text-muted);opacity:0.5`
- TODAY header: `font-size:11px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.05em;margin-bottom:6px;`
- Compound row: `display:flex;justify-content:space-between;gap:8px;`
- Dose/unit right-aligned in the row
- Compound name: truncated at 22 chars with `…` if longer
- UPCOMING header: same style as TODAY header, `margin-top:10px;`
- Upcoming day row: `color:var(--text-muted);font-size:11px;`
- "All daily" line: `color:var(--text-muted);font-size:11px;font-style:italic;margin-top:6px;`

---

## 8. Edge Cases

| Case | Behavior |
|---|---|
| No active protocol | Empty state with link to My Protocols |
| Protocol with no `startDate` | Non-ED compounds fall back to "not due" (isDueOnDate returns false for interval freqs without startDate) |
| Phased compound, no matching phase for current week | Use last phase's dose |
| Compound name > 22 chars | Truncate with `…` |
| All compounds ED/PWO | TODAY list shows all green, "All daily" replaces UPCOMING |
| 0 non-daily compounds due in next 6 days | UPCOMING section omitted (all-daily case handles it) |
| Compound with `freq` array (e.g. ['Mon','Wed','Fri']) | `isDueOnDate` handles array freq — includes day name check |

---

## 9. Scope and Constraints

- All changes confined to `index-v2.html` and `tests/protocol-logic.html`
- No new localStorage keys, no new CSS files
- `isDueOnDate` is pure — no `new Date()` internal calls, no DOM, no localStorage
- `currentPhaseDose` is pure — no side effects
- `renderDoseSchedule` called from inside `renderCycleProgress` (one call site addition)
- `escHtml` on all user-supplied strings written to innerHTML
- No changes to Vitals, Log Entry, Protocols, Builder, Calculator, or Compounds pages
- No changes to `isDueToday` (existing tested function — left intact)

---

## 10. What Is NOT in Scope

- No "mark as taken" / dose tracking
- No notification or reminder system
- No editing doses from the schedule card
- No different view for phased protocols that change week-to-week (shows current week only)
- No BP/glucose trends in this card
