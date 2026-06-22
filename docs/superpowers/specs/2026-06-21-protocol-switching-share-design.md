# Protocol Switching + Share — Design Spec
_2026-06-21_

## Overview

Two related features for the Protocol Builder in `index-v2.html`:

1. **Protocol Switching** — when the user activates a new protocol while one is already active, a close-out modal captures how the old cycle ended (Completed or Abandoned), writes a log entry, and updates the old protocol's status before switching.

2. **Protocol Share / Print** — a "Share" button on every protocol card opens a self-contained, print-optimized tab showing the full protocol: compounds, phase grid, and modification log. Works without Supabase.

---

## 1. Status Model

### New status value

`status` gains a 4th value: `'abandoned'`.

Full set: `'planning' | 'active' | 'completed' | 'abandoned'`

| Status | Meaning |
|---|---|
| `planning` | Not yet started |
| `active` | Currently running |
| `completed` | User finished the full planned cycle |
| `abandoned` | User cut it short (side effects, coach change, etc.) |

`completed` and `abandoned` are permanent terminal states — neither can be switched back to `active` via the UI.

### Protocol card badges

All four statuses render a badge on the protocol card in My Protocols. Styling:

- `planning` — muted blue
- `active` — green
- `completed` — indigo (`--primary`)
- `abandoned` — muted / dim (not bold red — it's history, not an error)

All use existing CSS variables. No hardcoded colors.

### Backward compatibility

Existing protocols in localStorage have no `abandoned` status — no migration needed. `normalizeProtocol()` already defaults `status` to `'planning'` for old entries.

---

## 2. Protocol Switching Flow

### Entry point

`setActiveProtocol(index)` is the single function that handles all protocol activation. It is updated to intercept active→active switches.

### Decision logic

```
current active protocol?
  No  → silent switch
  Yes → status === 'planning'? → silent switch
        status === 'active'?   → show close-out modal
```

"Silent switch" means the existing behavior: clear `hrt_active_protocol` / `hrt_active_protocol_data`, set new protocol, re-render.

### Pending switch state

A module-level variable holds the pending switch while the modal is open:

```js
let _pbPendingSwitch = null; // { newIndex }
```

Set before opening modal, cleared on Cancel or after switch completes.

### Close-out modal

Rendered into a dedicated `#pb-close-modal` div (hidden by default). Contents:

- Header: `"Before switching — how did [Protocol Name] end?"`
- Toggle: **Completed** | **Abandoned** (defaults to Completed)
- Week ended: number input, pre-filled with `pbCurrentCycleWeek(startDate)`; blank if no `startDate`
- Reason / notes: optional `<textarea>`
- Buttons: **Confirm & Switch** · **Skip — just switch** · **Cancel**

### On Confirm

1. Load all protocols from `lsGet('hrt_protocols', [])`
2. Find old active protocol (match by `saved_at === lsGet('hrt_active_protocol')`)
3. Update it:
   - `status` → `'completed'` or `'abandoned'` (from toggle)
   - Push to `modificationLog`:
     ```js
     {
       type: 'cycle_closed',
       week: weekEnded,       // from input; null if blank
       note: reason,          // from textarea; '' if blank
       ts: Date.now()
     }
     ```
4. Save updated array back to `hrt_protocols` via `lsSet()`
5. Clear `hrt_active_protocol` and `hrt_active_protocol_data`
6. Activate new protocol (existing logic)
7. Clear `_pbPendingSwitch`, close modal, re-render

### On Skip

Same as Confirm, but:
- `status` forced to `'abandoned'` regardless of toggle (toggle not shown yet — Skip is instant)
- Log entry auto-filled:
  ```js
  {
    type: 'cycle_closed',
    week: pbCurrentCycleWeek(startDate) || null,
    note: '',
    ts: Date.now()
  }
  ```
- No user input required

Rationale: the timestamp and auto-calculated week preserve the "when did this cycle end?" fact for coach review, even without a reason.

### On Cancel

`_pbPendingSwitch = null`, modal hidden. No state changes.

---

## 3. New Log Type: `cycle_closed`

`type: 'cycle_closed'` is added to the modification log type set alongside the existing types (`addition | removal | dose_change | cycle_extended | cycle_shortened | note`).

Added to `_pbLogIcons`:

```js
cycle_closed: { icon: '✓', color: 'var(--green)' }   // completed
```

For abandoned entries, the icon color renders as `var(--text-muted)` — determined at render time by checking the protocol's `status` field, or by reading a `closed_as` sub-field on the log entry.

Simplest approach: store `closed_as: 'completed' | 'abandoned'` on the log entry itself so `renderProtocolLog` doesn't need to reach outside the entry:

```js
{
  type: 'cycle_closed',
  closed_as: 'completed',   // or 'abandoned'
  week: 12,
  note: 'Finished full cycle',
  ts: 1234567890
}
```

`renderProtocolLog` uses `entry.closed_as` to pick the icon color for `cycle_closed` entries.

---

## 4. Protocol Share / Print

### Entry point

A **Share** button is added to every protocol card in the My Protocols list. Visible for all statuses — a completed or abandoned protocol is exactly what a coach needs to review.

### Function signature

```js
function printProtocol(index) { ... }
```

Called directly from the button's `onclick`. Loads the protocol from `hrt_protocols` by index, builds the print document, opens it.

### Print document contents

1. **Header** — Protocol name, status badge, total weeks, start date + date range (if set), date generated
2. **Compounds + Phases** — one row per compound: name, category, unit, frequency, phases listed inline (e.g., `Weeks 1–8: 400mg · Weeks 9–12: 250mg`)
3. **Week-by-week Timeline Grid** — derived from `buildWeekGrid(compounds, totalWeeks)`; same data as the Builder's Timeline tab. Dose cells show `Xunit`; inactive cells show `—`
4. **Modification Log** — all entries in chronological order (oldest first — forward-reading for a coach). Each entry: week, type label, compound (if applicable), note

### Implementation

`printProtocol(index)` opens a new tab via `window.open()` and writes a self-contained HTML document:

```js
const w = window.open('', '_blank');
w.document.write(`<!DOCTYPE html><html>...<style>...</style><body>...</body></html>`);
w.document.close();
```

- **White background, readable font** — no app chrome, no dark theme
- **Inline styles only** — the new tab is a separate document; app CSS variables don't apply
- **Print-ready layout** — `@media print` CSS included so browser's native "Print → Save as PDF" produces a clean output
- **Page title** set to the protocol name so "Save as PDF" produces a sensibly named file
- All user content rendered via `escHtml()` — XSS prevention applies even in the print view

### No Supabase dependency

The print view is generated entirely from localStorage data. Works fully offline.

---

## 5. Validation and Edge Cases

| Scenario | Behavior |
|---|---|
| First activation (no prior active protocol) | No modal — silent switch |
| Switching from `planning` → new `active` | Silent switch — no modal |
| Switching from `active` → new `active` | Close-out modal shown |
| `startDate` not set | Week field pre-filled blank; Skip entry writes `week: null` |
| Week ended input left blank on Confirm | `week: null` in log entry |
| Protocol has no `modificationLog` | `normalizeProtocol()` already defaults it to `[]` |
| Print view on a protocol with no phases | Shows compounds with no phase rows; log still renders |
| Print view on a protocol with no log entries | Log section shows "No modifications logged" |

---

## What is NOT in Scope

- No shareable URL / link generation (requires Supabase; deferred)
- No CSV or image export of the timeline grid
- No email sending from within the app
- No UI to manually change a `completed` or `abandoned` protocol back to `active`
- No multi-protocol comparison view
