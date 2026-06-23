# Protocol Dashboard — Timing & Today View Design Spec
_2026-06-22_

## Overview

Improve the protocol dashboard's active-cycle card to be a reliable daily driver. Three focused improvements:

1. **"Due today" for all frequency types** — fix broken today logic that currently only fires for specific-day arrays
2. **"Next dose in X days" per compound** — replace the `● today` dot with a per-compound timing line
3. **Upcoming window extended to 4 weeks + cycle-end banner** — more look-ahead, prompt to plan next cycle

No new data model changes. All logic derives from `startDate` and `freq`, which already exist on every active protocol.

---

## 1. "Due Today" Logic for All Frequency Types

### Current behavior

`● today` only appears when `Array.isArray(r.freq)` — i.e., specific-day schedules like `['Mon','Thu']`. All named frequencies (`ED`, `EOD`, `E3.5D`, `Weekly`, etc.) produce no today indicator.

### New behavior

A function `isDueToday(freq, startDate)` returns `true` if today is a scheduled dose day. It accepts both array and named frequencies, using `startDate` as the reference point for day-count-based schedules.

```js
function isDueToday(freq, startDate) {
  const start = new Date(startDate);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  start.setHours(0, 0, 0, 0);
  const daysSinceStart = Math.round((today - start) / 86400000);
  const todayDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][today.getDay()];
  const startDay  = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][start.getDay()];

  if (Array.isArray(freq)) return freq.includes(todayDay);

  const f = (freq || '').toUpperCase().trim();
  if (f === 'ED' || f === 'PWO')    return true;
  if (f === 'EOD')                  return daysSinceStart % 2 === 0;
  if (f === 'E3D')                  return daysSinceStart % 3 === 0;
  if (f === 'E4D')                  return daysSinceStart % 4 === 0;
  if (f === 'E5D')                  return daysSinceStart % 5 === 0;
  if (f === 'E3.5D' || f === '2X/WK') {
    // Approximated as same 2 weekdays as start: startDay and startDay+3 (wrapping)
    const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    const si = days.indexOf(startDay);
    const second = days[(si + 3) % 7];
    return todayDay === startDay || todayDay === second;
  }
  if (f === '3X/WK') {
    // Mon/Wed/Fri pattern anchored to start day
    const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    const si = days.indexOf(startDay);
    const d1 = startDay;
    const d2 = days[(si + 2) % 7];
    const d3 = days[(si + 4) % 7];
    return todayDay === d1 || todayDay === d2 || todayDay === d3;
  }
  if (f === 'WEEKLY')               return todayDay === startDay;
  if (f === 'BI-WKLY')              return todayDay === startDay && daysSinceStart % 14 === 0;
  if (f === 'MONTHLY')              return today.getDate() === start.getDate();
  return false;
}
```

### Edge case: no `startDate`

If the protocol has no `startDate`, `isDueToday` returns `false` for all day-count-based frequencies. Specific-day arrays (`['Mon','Thu']`) still work without a start date. No error is thrown.

---

## 2. "Next Dose in X Days" Per Compound

### Current behavior

A single `● today` dot appears inline with the compound name (specific-day schedules only). No information about upcoming doses.

### New behavior

Each compound row in the "Active this week" list adds a timing line below the dose/frequency:

| Condition | Display |
|---|---|
| Due today | `Due today` — green (`var(--green)`) |
| Due tomorrow | `Next dose tomorrow` — muted |
| Due in N days (2–6) | `Next dose in N days` — muted |
| ED / PWO | `Every day` — muted (no countdown needed) |
| No `startDate` and named freq | _(timing line omitted)_ |

### Computing "next dose in N days"

A function `daysUntilNextDose(freq, startDate)` returns `0` (due today), `1` (tomorrow), `2–6`, or `null` (ED/PWO/no startDate).

```js
function daysUntilNextDose(freq, startDate) {
  const f = (freq || '').toUpperCase().trim();
  if (f === 'ED' || f === 'PWO') return null; // "every day" — no countdown needed

  for (let d = 0; d <= 6; d++) {
    const candidate = new Date();
    candidate.setHours(0, 0, 0, 0);
    candidate.setDate(candidate.getDate() + d);
    const candidateDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][candidate.getDay()];

    if (Array.isArray(freq)) {
      if (freq.includes(candidateDay)) return d;
      continue;
    }

    const start = new Date(startDate);
    start.setHours(0, 0, 0, 0);
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const startDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][start.getDay()];
    const daysSince = Math.round((candidate - start) / 86400000);

    if (f === 'EOD'  && daysSince % 2 === 0) return d;
    if (f === 'E3D'  && daysSince % 3 === 0) return d;
    if (f === 'E4D'  && daysSince % 4 === 0) return d;
    if (f === 'E5D'  && daysSince % 5 === 0) return d;
    if ((f === 'E3.5D' || f === '2X/WK')) {
      const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      const si = days.indexOf(startDay);
      const second = days[(si + 3) % 7];
      if (candidateDay === startDay || candidateDay === second) return d;
    }
    if (f === '3X/WK') {
      const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      const si = days.indexOf(startDay);
      if (candidateDay === startDay || candidateDay === days[(si+2)%7] || candidateDay === days[(si+4)%7]) return d;
    }
    if (f === 'WEEKLY'  && candidateDay === startDay) return d;
    if (f === 'BI-WKLY' && candidateDay === startDay && daysSince % 14 === 0) return d;
    if (f === 'MONTHLY' && candidate.getDate() === start.getDate()) return d;
  }
  return null;
}
```

### Compound row layout (updated)

```
Testosterone E        250mg        E3.5D
Due today                                      ← green if due, muted otherwise
```

The timing line is a `<div>` beneath the existing row, font-size 11px, no extra card or border.

---

## 3. Upcoming Window Extended to 4 Weeks + Cycle-End Banner

### Upcoming window

Change the look-ahead from `currentWeek + 2` to `currentWeek + 4`. Same format, same data source (phase transitions and new compound starts from `buildWeekGrid`).

### Cycle-end banner

When `(totalWeeks - currentWeek) <= 3` and the protocol is active:

```
Cycle ends in N week(s) — consider planning your next protocol
```

- Rendered as a thin banner between the "Active this week" section and the "Upcoming" section
- Color: `var(--amber)` text on a subtle amber-tinted background (`rgba` of `--amber`, low opacity)
- N = `totalWeeks - currentWeek` (1, 2, or 3)
- Only shown when `totalWeeks` is set (not when cycle has no defined end)

---

## 4. Scope and Constraints

- All changes confined to `renderCycleProgress()` in `index-v2.html`
- Two new pure functions added at module scope: `isDueToday(freq, startDate)` and `daysUntilNextDose(freq, startDate)`
- No changes to data model, localStorage keys, or any other function
- No new UI controls — dashboard remains read-only
- Existing behavior when `status !== 'active'` or no `startDate` is unchanged

---

## 5. Test Coverage

New assertions in `tests/protocol-logic.html`:

- `isDueToday('ED', anyDate)` → `true`
- `isDueToday('EOD', yesterday)` → `true` (1 day since start → odd → false; 0 days → even → true)
- `isDueToday('Weekly', startDateWithSameWeekday)` → `true`
- `isDueToday('Weekly', startDateWithDifferentWeekday)` → `false`
- `isDueToday(['Mon','Thu'], ...)` → `true` if today is Mon or Thu
- `daysUntilNextDose('ED', ...)` → `null`
- `daysUntilNextDose('EOD', yesterday)` → `0` (due today)
- `daysUntilNextDose('Weekly', startDateWithSameWeekday)` → `0`
- `daysUntilNextDose('Weekly', startDateWithDifferentWeekday)` → days until that weekday

---

## What Is NOT in Scope

- No "log injection" or "mark as done" button on the dashboard
- No push/browser notifications or reminders
- No changes to the Protocol Builder or My Protocols pages
- No changes to the Vitals, Labs, or Log Entry pages
