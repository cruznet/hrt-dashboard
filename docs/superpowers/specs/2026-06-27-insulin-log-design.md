# Insulin Log — Design Spec
_2026-06-27_

## Overview

Add a per-injection insulin log to the app, and rename the Vitals page to **Health Log**. Each insulin entry captures dose info (type, name, units, timing) and glucose response (BG before, carbs consumed, BG after). Data is stored in localStorage and synced to a new Supabase `insulin_log` table. Designed for bodybuilders using short-acting, long-acting, or both.

---

## 1. Page Rename: Vitals → Health Log

Every reference to "Vitals" in the UI becomes "Health Log":
- Sidebar nav label: `Vitals` → `Health Log`
- Page title inside the section
- Any `nav('vitals')` call targets remain unchanged (`id="page-vitals"` stays as-is — internal IDs don't need renaming)

---

## 2. Page Layout

The Health Log page gains an **Insulin Log** section inserted between the existing glucose chart and the vitals history table:

```
┌─────────────────────────────────────────────┐
│  METRIC CARDS  (weight · glucose · mood)    │  ← existing, unchanged
├─────────────────────────────────────────────┤
│  GLUCOSE CHART                              │  ← existing, unchanged
├─────────────────────────────────────────────┤
│  INSULIN LOG                    [+ Add]     │  ← new
│  per-injection table                        │
├─────────────────────────────────────────────┤
│  VITALS HISTORY TABLE                       │  ← existing, unchanged
└─────────────────────────────────────────────┘
```

---

## 3. Add Injection Modal

Triggered by the **+ Add** button in the Insulin Log section header. Reuses the existing `.modal` / `.modal-overlay` pattern.

### Fields

| Field | Input | Notes |
|---|---|---|
| Date | `date` input | Defaults to today |
| Time | `time` input | Defaults to current time |
| Type | Select: Short-acting / Long-acting | Controls conditional fields |
| Insulin name | Select + free "Other" text | See lists below |
| Units | Number input | Step 0.5 |
| Timing | Select | Short-acting only (hidden for long-acting) |
| BG Before | Number input (mg/dL) | Optional |
| Carbs | Number input (g) | Short-acting only (hidden for long-acting) |
| BG After | Number input (mg/dL) | Optional |
| Notes | Textarea | Optional |

**Short-acting insulin names:** Humalog, NovoLog, Humulin R, Slin, Other

**Long-acting insulin names:** Lantus, Levemir, Tresiba, Basaglar, Other

**Timing options (short-acting):** Post-workout, Pre-meal, Fasted, Other

When **Type** changes to Long-acting: Timing, Carbs, BG Before, and BG After fields hide via `display:none`. They are not required and not saved if hidden.

When **Other** is selected for insulin name: a free-text input appears below the select.

### Validation
- Units required and > 0
- Date required
- All other fields optional

---

## 4. Insulin Log Table

Displayed in a card with header "Insulin Log" and an "+ Add" button. Shows the 30 most recent entries, newest first.

### Columns

| Column | Value |
|---|---|
| Date / Time | `Jun 27 · 14:30` |
| Type | `Short` / `Long` badge |
| Name | Insulin name |
| Units | `10u` |
| BG Before | `98 mg/dL` or `—` |
| Carbs | `80g` or `—` |
| BG After | Colored value or `—` |

### BG After color coding
- **Green** (`var(--green)`): 70–140 mg/dL — safe range
- **Amber** (`var(--amber)`): 141–180 mg/dL — elevated
- **Red** (`var(--red)`): < 70 or > 180 mg/dL — hypo/hyper warning

### Empty state
Icon + "No insulin entries yet" + "Track your first injection with + Add"

---

## 5. Data Model

### localStorage key: `hrt_insulin_log`

Array of entry objects, newest first:

```js
{
  id:        string,   // crypto.randomUUID()
  date:      string,   // "2026-06-27"
  time:      string,   // "14:30"
  type:      string,   // "short" | "long"
  name:      string,   // "Humalog", "Lantus", "Other: Slin", etc.
  units:     number,
  timing:    string,   // "post-workout" | "pre-meal" | "fasted" | "other" | ""
  bg_before: number|null,
  carbs:     number|null,
  bg_after:  number|null,
  notes:     string,
  created_at: string   // ISO timestamp
}
```

### Supabase table: `insulin_log`

```sql
create table if not exists insulin_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  date        date not null,
  time        text,
  type        text not null,
  name        text not null,
  units       numeric not null,
  timing      text,
  bg_before   numeric,
  carbs       numeric,
  bg_after    numeric,
  notes       text,
  created_at  timestamptz not null default now()
);

alter table insulin_log enable row level security;

create policy "Users manage own insulin log"
  on insulin_log for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index insulin_log_user_date on insulin_log(user_id, date desc);
```

---

## 6. Functions

### `saveInsulinEntry(entry)`

Saves a new entry to localStorage (`hrt_insulin_log`) and fire-and-forgets to Supabase:

```js
async function saveInsulinEntry(entry) {
  entry.id = crypto.randomUUID();
  entry.created_at = new Date().toISOString();
  const log = lsGet('hrt_insulin_log', []);
  log.unshift(entry);
  localStorage.setItem('hrt_insulin_log', JSON.stringify(log));
  renderInsulinLog();
  if (_supa && _supaUser) {
    const { error } = await _supa.from('insulin_log').insert({ ...entry, user_id: _supaUser.id });
    if (error) console.warn('[insulin] save failed:', error.message);
  }
}
```

### `renderInsulinLog()`

Reads `hrt_insulin_log` from localStorage, renders the table into `#insulin-log-content`. Shows empty state if no entries.

### `loadUserData()` addition

After the existing fetches, add:

```js
_supa.from('insulin_log')
  .select('*').eq('user_id', uid)
  .order('date', { ascending: false }).order('created_at', { ascending: false })
  .limit(90)
```

On success, map to localStorage format and call `renderInsulinLog()`.

---

## 7. HTML Structure

### Insulin Log card (inserted before vitals history table in `#page-vitals`)

```html
<div class="card">
  <div class="card-title" style="display:flex;justify-content:space-between;align-items:center;">
    Insulin Log
    <button class="btn-primary" style="font-size:12px;padding:5px 12px;"
      onclick="openInsulinModal()">+ Add</button>
  </div>
  <div id="insulin-log-content"></div>
</div>
```

### Insulin modal (added near other modals)

```html
<div class="modal-overlay" id="insulin-modal">
  <div class="modal">
    <div class="modal-title">
      Log Insulin Injection
      <span class="modal-close" onclick="closeModal('insulin-modal')">
        <i class="ti ti-x"></i>
      </span>
    </div>
    <!-- fields per Section 3 -->
  </div>
</div>
```

---

## 8. Scope and Constraints

- All changes confined to `index.html`
- No new CSS files; uses existing `.card`, `.modal`, `.modal-overlay`, `.btn-primary`, `.form-input` classes
- `escHtml()` wraps all user-supplied strings rendered to innerHTML
- `saveInsulinEntry` is fire-and-forget to Supabase — UI never blocks on sync
- Internal page ID `page-vitals` and `nav('vitals')` calls unchanged
- No editing or deleting entries in v1 (append-only log)
- No dashboard widget for insulin in this sprint

---

## 9. What Is NOT in Scope

- Editing or deleting existing insulin entries
- Dashboard widget / chart for insulin data
- Insulin sensitivity score or calculated metrics
- Alerts or notifications for BG values
- Export of insulin log data
- Integration with CGM devices
