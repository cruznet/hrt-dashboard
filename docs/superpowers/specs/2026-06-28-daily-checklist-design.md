# Daily Dose Checklist — Design Spec
_2026-06-28_

## Overview

Upgrade the Dose Schedule card on the dashboard from a static display (●/○ bullets) to an interactive daily checklist. Compounds due today appear as checkboxes. Checking a compound auto-creates a record in Supabase `administration_log` so administration history is preserved without any manual form entry. Unchecking deletes the record.

---

## 1. Card Design

The existing **Dose Schedule** card on the dashboard is upgraded in place — same card, same position. No new card is added.

### Today section

The static ●/○ bullet rows are replaced with interactive checkbox rows. Only compounds due today (per `isDueOnDate`) are shown in the Today section. Non-due compounds are not displayed.

Each row layout:
```
[ ] Testosterone Cypionate   200mg
[ ] HCG                      500iu
```

- Compound name (truncated to 22 chars as before, using existing `trunc()` helper)
- Dose + unit right-aligned
- Checkbox left of the name
- When checked: row gets a strikethrough style and the checkbox shows as filled; re-renders immediately
- State persists in localStorage (`hrt_doses_taken`) across page navigations until the next calendar day

If no compounds are due today (e.g. an EOD compound on an off day), the Today section shows: _"No compounds due today"_ in muted text.

### Upcoming section

Unchanged — keeps the existing upcoming-days display (non-daily compounds, next 6 days, up to 5 entries).

---

## 2. Data Flow

### On check

1. Call `checkDose(compound_name, dose, unit, date)`
2. Insert row into Supabase `administration_log`:
   ```js
   { user_id: _supaUser.id, date, compound_name, dose, unit, created_at: new Date().toISOString() }
   ```
3. On insert success: save to `hrt_doses_taken` in localStorage with the returned Supabase row `id`:
   ```js
   { label: compound_name, date, ts: new Date().toISOString(), id: row.id }
   ```
4. On insert failure (offline / error): save to `hrt_doses_taken` with `id: null` (check still shows as done locally; Supabase write fails silently with a `console.warn`)
5. Re-render the card via `renderDoseSchedule()`

### On uncheck

1. Call `uncheckDose(compound_name, date)`
2. Look up the entry in `hrt_doses_taken` by `compound_name` + `date`
3. If it has a non-null `id`: delete from Supabase `administration_log` where `id = <id>`
4. Remove the entry from `hrt_doses_taken` in localStorage regardless of Supabase result
5. Re-render the card via `renderDoseSchedule()`

### localStorage format (`hrt_doses_taken`)

Each entry gains an optional `id` field (null if Supabase was unreachable):
```js
{ label: "Testosterone Cypionate", date: "2026-06-28", ts: "2026-06-28T14:30:00.000Z", id: "uuid-or-null" }
```

The existing `markDoseTaken()` function (used by the Upcoming/adherence pages) is not changed — it continues to write `{ label, date, ts }` without `id`. The new `checkDose` / `uncheckDose` functions are separate.

---

## 3. Supabase Schema

The `administration_log` table already exists and is queried by `loadUserData()`. The check-off feature writes `compound_name`, `dose`, and `unit` columns. If these columns are not present, the user must run the following SQL in their Supabase console before deploying:

```sql
alter table administration_log
  add column if not exists compound_name text,
  add column if not exists dose          numeric,
  add column if not exists unit          text;
```

No new table is needed.

---

## 4. Functions

### `checkDose(compound_name, dose, unit, date)`

```js
async function checkDose(compound_name, dose, unit, date) {
  const taken = lsGet('hrt_doses_taken', []);
  if (taken.some(t => t.label === compound_name && t.date === date)) return; // guard duplicate
  const entry = { label: compound_name, date, ts: new Date().toISOString(), id: null };
  taken.push(entry);
  localStorage.setItem('hrt_doses_taken', JSON.stringify(taken));
  renderDoseSchedule();
  if (_supa && _supaUser) {
    const { data, error } = await _supa
      .from('administration_log')
      .insert({ user_id: _supaUser.id, date, compound_name, dose, unit, created_at: entry.ts })
      .select('id')
      .single();
    if (error) { console.warn('[checkDose] Supabase insert failed:', error.message); }
    else {
      // Back-fill the id so uncheck can delete it
      const taken2 = lsGet('hrt_doses_taken', []);
      const idx = taken2.findIndex(t => t.label === compound_name && t.date === date);
      if (idx >= 0) { taken2[idx].id = data.id; localStorage.setItem('hrt_doses_taken', JSON.stringify(taken2)); }
    }
  }
}
```

### `uncheckDose(compound_name, date)`

```js
async function uncheckDose(compound_name, date) {
  const taken = lsGet('hrt_doses_taken', []);
  const idx = taken.findIndex(t => t.label === compound_name && t.date === date);
  if (idx < 0) return;
  const entry = taken[idx];
  taken.splice(idx, 1);
  localStorage.setItem('hrt_doses_taken', JSON.stringify(taken));
  renderDoseSchedule();
  if (_supa && _supaUser && entry?.id) {
    const { error } = await _supa.from('administration_log').delete().eq('id', entry.id);
    if (error) console.warn('[uncheckDose] Supabase delete failed:', error.message);
  }
}
```

### `renderDoseSchedule()` changes

- The Today section is rewritten to show only due-today compounds as checkboxes
- Checked state is derived from `lsGet('hrt_doses_taken', [])` — an entry with matching `label` + `date` = today means checked
- Checkbox `onclick` calls `checkDose(...)` or `uncheckDose(...)` depending on current checked state
- `todayStr` = `new Date().toISOString().split('T')[0]`

Row HTML (due-today compounds only):
```html
<label style="display:flex;align-items:center;gap:8px;cursor:pointer;{strikethroughIfChecked}">
  <input type="checkbox" {checked} onchange="...">
  <span style="flex:1;">{name}</span>
  <span style="color:var(--text-muted);white-space:nowrap;">{dose}{unit}</span>
</label>
```

The `onchange` handler uses an inline call:
```js
this.checked
  ? checkDose('${compound_name}', ${dose}, '${unit}', '${todayStr}')
  : uncheckDose('${compound_name}', '${todayStr}')
```

---

## 5. Scope and Constraints

- All changes confined to `index.html`
- No new localStorage keys — extends existing `hrt_doses_taken` with optional `id` field
- `escHtml()` wraps all compound name strings rendered into innerHTML
- Supabase writes are fire-and-forget — UI never blocks on sync
- The existing `markDoseTaken()` function and `renderUpcoming()` / `renderAdherenceBadge()` callers are not modified
- No new CSS classes needed — uses inline styles consistent with existing card patterns
- Check state resets automatically at midnight (date mismatch) because `hrt_doses_taken` entries are matched by `date` = today's date string

---

## 6. What Is NOT in Scope

- Editing or deleting past administration records
- Dose adjustment in the checklist (dose comes from the active protocol)
- Custom timing / route tracking in the checklist
- Push notifications or reminders
- Bulk mark-all-taken button
- Syncing `hrt_doses_taken` back from Supabase on login (existing behavior unchanged)
