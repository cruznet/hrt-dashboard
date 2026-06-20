# Phased Protocol Builder — Design Spec
_2026-06-19_

## Overview

Upgrade the Protocol Builder in `index-v2.html` to support phased cycles: compounds with individual start/end weeks and multiple dose segments within a total cycle duration. Adds mid-cycle modification tracking, a live week-by-week timeline grid, and a Dashboard card showing current cycle position.

Also adds SLU-PP-332 to the COMPOUNDS library.

---

## Data Model

### Protocol shape (new)

```js
{
  id: 'uuid',
  name: 'Summer Cut 12wk',
  cycleLengthWeeks: 12,
  startDate: '2026-06-01',        // optional — enables "Week X of Y" on Dashboard
  status: 'planning' | 'active' | 'completed',
  compounds: [
    {
      name: 'Testosterone Enanthate',
      cat: 'AAS',
      unit: 'mg',
      freq: 'Weekly',
      phases: [
        { startWeek: 1, endWeek: 5,  dose: 400 },
        { startWeek: 6, endWeek: 6,  dose: 350 },
        { startWeek: 7, endWeek: 7,  dose: 300 },
        { startWeek: 8, endWeek: 12, dose: 250 }
      ]
    },
    {
      name: 'Anavar',
      cat: 'AAS',
      unit: 'mg',
      freq: 'ED',
      phases: [
        { startWeek: 9, endWeek: 12, dose: 50 }
      ]
    },
    {
      name: 'Humalog',
      cat: 'Insulin',
      unit: 'IU',
      freq: 'PWO',
      phases: [
        { startWeek: 1, endWeek: 10, dose: 10 }
      ]
    }
  ],
  modificationLog: [
    {
      week: 6,
      type: 'removal',        // 'addition' | 'removal' | 'dose_change' | 'cycle_extended' | 'cycle_shortened' | 'note'
      compound: 'Deca',
      note: 'High BP',
      ts: 1234567890
    }
  ]
}
```

### Unit and category

`unit` and `cat` are free strings — not locked to AAS or mg. Any compound from the full COMPOUNDS library is valid: AAS, Peptide, Insulin, SARM, Fat Loss, Support, Other. Units include mg, IU, mcg, etc. Picking a compound from the searchable dropdown pre-fills `cat`, `unit`, and `freq`; all three remain editable.

`freq` options fall into two categories:

**Named frequencies** (existing + PWO):
ED, EOD, E3.5D, 2X/WK, Weekly, PWO

**Custom weekday schedule** (new):
User picks specific days from a toggle row: `M T W T F S S`. Stored as a sorted array of day abbreviations:
```js
freq: ['Mon', 'Thu']          // every Monday and Thursday
freq: ['Mon', 'Wed', 'Fri']   // MWF
freq: ['Tue', 'Sat']          // twice weekly, specific days
```

In the compound phase UI, `freq` shows a dropdown with the named options plus a "Specific days…" option. Choosing "Specific days…" reveals the M T W T F S S day-picker inline.

`pbFreqToInjectionsPerWeek()` is extended to handle all cases:
- Array (custom days) → `freq.length`
- `'PWO'` → 7 (treat as daily for weekly total)
- Existing named strings → unchanged

When `startDate` is set and the protocol is active, the Dashboard cycle card can derive "due today" by checking if today's weekday is in `freq`. Example: today is Thursday, `freq: ['Mon', 'Thu']` → Test E is due today.

### dose_change log entries

`type: 'dose_change'` is written automatically when a phase is edited on a protocol with `status === 'active'`. It captures the compound name, old dose, and new dose. Editing phases on `planning` or `completed` protocols does not write log entries — only structural changes on live cycles are tracked.

### Backward compatibility

On first load, existing protocols in localStorage are auto-migrated by `normalizeProtocol()`. Detection: if a compound has no `phases` array, wrap its current `dose` into a single phase `{ startWeek: 1, endWeek: cycleLengthWeeks || 12, dose: compound.dose }`. `cycleLengthWeeks` defaults to 12 if absent. `status` defaults to `'planning'`. `modificationLog` defaults to `[]`. No data loss, no user action required. Mirrors the existing `normalizeCompound()` pattern.

---

## UI — Protocol Builder (page-builder)

### Cycle-level settings (top of page)

| Field | Type | Notes |
|---|---|---|
| Cycle name | text input | |
| Total weeks | number input | default 12; editing triggers phase validation |
| Start date | date input | optional; enables Dashboard cycle card |
| Status | segmented control | Planning / Active / Completed |

### Compound cards

Each compound in the protocol renders as a card showing:
- Name + category badge + unit + frequency
- Phases listed inline: `Weeks 1–5: 400mg · Weeks 6–6: 350mg · Weeks 8–12: 250mg`
- **+ Add Phase** — appends a new `{ startWeek, endWeek, dose }` row
- **Remove Compound** — opens a modal: "At which week?" + "Reason" textarea → writes a `type: 'removal'` entry to `modificationLog`

### Adding a compound

1. Searchable dropdown from the full COMPOUNDS library
2. Selecting a compound pre-fills `cat`, `unit`, `freq`
3. First phase defaults to `startWeek: 1, endWeek: cycleLengthWeeks`
4. User adjusts start/end weeks and dose, then adds more phases as needed

### Mid-cycle compound addition

Adding a compound to an already-active protocol works identically — set `startWeek` to the current week. A `type: 'addition'` entry is written to `modificationLog` automatically on save.

### Cycle length changes

**Extending** (e.g., 16wk → 20wk): shows a checkbox "Extend all currently running compounds to new end week." Checking it updates the `endWeek` of each compound's last phase to the new cycle length.

**Reducing** (e.g., 16wk → 10wk): warns if any compound phases extend past the new end. User confirms before saving. No auto-truncation — user decides whether to trim phases or leave them with a note.

Both events write to `modificationLog`:
```
type: 'cycle_extended'  — "Cycle extended 16wk → 20wk"
type: 'cycle_shortened' — "Cycle reduced 16wk → 10wk"
```

---

## UI — Timeline Tab (page-builder)

Auto-generated read-only grid derived entirely from the phases. No manual input.

```
           Wk1   Wk2  ...  Wk9   Wk10  Wk11  Wk12
Test E    400mg 400mg ... 250mg 250mg 250mg 250mg
Primo     200mg 200mg ... 300mg 300mg 300mg 300mg
HGH        6IU   6IU ...   6IU   6IU   6IU   6IU
Anavar      —     —   ...  50mg  50mg  50mg  50mg
Reta       3mg   3mg ...   6mg   6mg   6mg   6mg
```

- Active week cells: indigo background (`--primary`), dose + unit in white
- Inactive cells: `—` in `--text-muted`
- Scrolls horizontally for long cycles
- Regenerated on every Builder save — never manually edited

---

## UI — Log Tab (page-builder)

Chronological list of all modification events, newest first.

```
Wk 17  [added]     Tren Ace 50mg ED — "Coach: added for final 4 weeks"
Wk 16  [extended]  Cycle extended 16wk → 20wk
Wk 11  [dose ↓]    Test E — 300mg → 250mg — "Reducing for cruise"
Wk  6  [removed]   Deca — "High BP"
```

Event type icons:
- `added` → green `+`
- `removed` → red `×`
- `dose_change` → amber `↕`
- `cycle_extended` → indigo `→`
- `cycle_shortened` → amber `←`
- `note` → muted `✎`

**+ Add Note** button: freeform entry at any week, no structural change. Writes `type: 'note'` to `modificationLog`.

---

## Dashboard Cycle Card

Renders only when a protocol has `status === 'active'` and `startDate` is set. If neither condition is met, the existing upcoming doses section renders unchanged — no regression.

```
Summer Cut 12wk                    Week 9 of 12
████████████████████░░░░░░░░░░░░   75%

Active this week
  Testosterone Enanthate   250mg   Weekly
  Primo                    300mg   Weekly
  HGH                        6IU   ED
  Anavar                    50mg   ED
  Reta                       6mg   ED

Upcoming
  Test E drops to 200mg — Week 11 (2 weeks)
  Cycle ends — Week 12 (3 weeks)
```

Current week is calculated as `Math.floor((Date.now() - Date.parse(startDate)) / 604800000) + 1`, clamped to `[1, cycleLengthWeeks]`.

---

## Validation Rules

- Phase `startWeek` ≥ 1 and ≤ `cycleLengthWeeks`
- Phase `endWeek` ≥ `startWeek` and ≤ `cycleLengthWeeks`
- Phases for the same compound must not overlap
- Reducing `cycleLengthWeeks` warns if any phase `endWeek` exceeds the new value — user confirms before save

---

## SLU-PP-332 — COMPOUNDS Addition

```js
{
  name: 'SLU-PP-332',
  cat: 'Other',
  hl: '~4',
  unit: 'mg',
  freq: 'ED',
  ai: 'No',
  dht: 'No',
  note: 'ERRα/γ agonist — exercise mimetic, research compound'
}
```

---

## What is NOT in scope

- No HealthKit integration in v2
- No split into multiple files
- No build system or package.json
- No export of the timeline grid to CSV/PDF (future feature)
- No AI interpretation of cycle data (future feature)
