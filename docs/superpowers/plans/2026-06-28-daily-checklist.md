# Daily Dose Checklist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static ●/○ bullet rows in the Dose Schedule dashboard card with interactive checkboxes that auto-write to Supabase `administration_log` when checked and delete on uncheck.

**Architecture:** Two new JS functions (`checkDose`, `uncheckDose`) handle localStorage + Supabase sync. The existing `renderDoseSchedule()` Today section is rewritten to render checkbox `<label>` rows for due-today compounds only, deriving checked state from `hrt_doses_taken` localStorage. No new files, no new localStorage keys — only `hrt_doses_taken` entries gain an optional `id` field.

**Tech Stack:** Vanilla JS, Supabase JS v2 (CDN global `window.supabase`), single-file `index.html`, no build system, no test runner.

## Global Constraints

- All changes confined to `index.html`
- No new files, no new CSS files, no new localStorage keys
- `escHtml()` wraps all user-supplied strings rendered into innerHTML
- Supabase writes are fire-and-forget — UI never blocks on sync failures
- The existing `markDoseTaken()`, `renderUpcoming()`, and `renderAdherenceBadge()` functions are not modified
- Compound names in inline JS event handlers must have single-quotes escaped with `.replace(/'/g, "\\'")`  — this is the existing project pattern (see `renderUpcoming` callers)
- Global `_supa` and `_supaUser` are the Supabase client and user objects
- Global `lsGet(key, fallback)` reads and JSON-parses localStorage
- `administration_log` Supabase table must have `compound_name text`, `dose numeric`, `unit text` columns — user must run the ALTER TABLE from Task 1 before deploying

---

### Task 1: Supabase schema note + `checkDose` / `uncheckDose` functions

**Files:**
- Modify: `index.html` (insert after line 4334, after closing `}` of `markDoseTaken`)

**Interfaces:**
- Consumes: `lsGet(key, fallback)` (global), `_supa` (global Supabase client), `_supaUser` (global user), `renderDoseSchedule()` (defined at line 2643 — Task 2 upgrades it, but it already exists)
- Produces: `checkDose(compound_name, dose, unit, date)` async function; `uncheckDose(compound_name, date)` async function — both globally available for Task 2's inline `onchange` handlers

- [ ] **Step 1: Note the Supabase schema requirement**

  The `administration_log` table must have `compound_name`, `dose`, and `unit` columns. Run this SQL in the Supabase dashboard (SQL Editor) **before** testing the feature. Do NOT add this SQL to `index.html`.

  ```sql
  alter table administration_log
    add column if not exists compound_name text,
    add column if not exists dose          numeric,
    add column if not exists unit          text;
  ```

  Confirm execution returns "Success" with no error. Continue only after this runs.

- [ ] **Step 2: Locate the insertion point**

  In `index.html`, find the end of `markDoseTaken` at approximately line 4334:

  ```js
  function markDoseTaken(label, date) {
    const taken = lsGet('hrt_doses_taken', []);
    // Avoid duplicates
    if (taken.some(t => t.date === date && t.label === label)) return;
    taken.push({ label, date, ts: new Date().toISOString() });
    localStorage.setItem('hrt_doses_taken', JSON.stringify(taken));
    renderUpcoming(); // re-render to show checkmark
    renderAdherenceBadge();
  }        ← insert after this closing brace
  ```

- [ ] **Step 3: Insert `checkDose` and `uncheckDose` after `markDoseTaken`**

  Insert the following block immediately after the closing `}` of `markDoseTaken` (a blank line between them is fine):

  ```js
  async function checkDose(compound_name, dose, unit, date) {
    const taken = lsGet('hrt_doses_taken', []);
    if (taken.some(t => t.label === compound_name && t.date === date)) return;
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
        const taken2 = lsGet('hrt_doses_taken', []);
        const idx = taken2.findIndex(t => t.label === compound_name && t.date === date);
        if (idx >= 0) { taken2[idx].id = data.id; localStorage.setItem('hrt_doses_taken', JSON.stringify(taken2)); }
      }
    }
  }

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

- [ ] **Step 4: Verify the functions are callable from the browser console**

  Open the app at `http://localhost:3000/index-v2.html` (or wherever it's served). Open DevTools console. Run:

  ```js
  typeof checkDose    // expected: "function"
  typeof uncheckDose  // expected: "function"
  ```

  Both must return `"function"`. If either returns `"undefined"`, the function wasn't inserted correctly — check for syntax errors in the block above.

- [ ] **Step 5: Verify `checkDose` writes to localStorage**

  Still in the browser console, with the dashboard open and an active protocol set:

  ```js
  // Note today's date string
  const d = new Date().toISOString().split('T')[0];

  // Call checkDose with a test compound
  await checkDose('TEST_COMPOUND', 100, 'mg', d);

  // Verify the entry was saved
  JSON.parse(localStorage.getItem('hrt_doses_taken'))
    .filter(t => t.label === 'TEST_COMPOUND');
  // Expected: [{ label: "TEST_COMPOUND", date: "YYYY-MM-DD", ts: "...", id: "uuid-or-null" }]
  ```

  If Supabase is connected and the ALTER TABLE was run, `id` should be a UUID string (not null). Open the Supabase Table Editor → `administration_log` and confirm a row exists with `compound_name = "TEST_COMPOUND"`.

- [ ] **Step 6: Verify `uncheckDose` removes the entry**

  In the browser console:

  ```js
  const d = new Date().toISOString().split('T')[0];
  await uncheckDose('TEST_COMPOUND', d);

  // Verify removed from localStorage
  JSON.parse(localStorage.getItem('hrt_doses_taken'))
    .filter(t => t.label === 'TEST_COMPOUND');
  // Expected: [] (empty array)
  ```

  Refresh the Supabase `administration_log` table — the TEST_COMPOUND row should be gone.

- [ ] **Step 7: Commit**

  ```bash
  git add index.html
  git commit -m "feat: add checkDose/uncheckDose functions for daily checklist"
  ```

---

### Task 2: Upgrade `renderDoseSchedule()` with interactive checkboxes

**Files:**
- Modify: `index.html` lines 2664–2670 (the `// TODAY section` block inside `renderDoseSchedule`)

**Interfaces:**
- Consumes: `checkDose(compound_name, dose, unit, date)` and `uncheckDose(compound_name, date)` from Task 1
- Consumes: existing locals already set up above line 2664: `today` (Date), `todayLabel` (string), `trunc` (function), `escHtml` (global function), `compounds` (array of `{ name, dose, unit, freq, dueToday }`)
- Produces: updated `renderDoseSchedule()` — no interface change, same function name

- [ ] **Step 1: Locate the Today section to replace**

  In `index.html`, find the Today section at approximately lines 2664–2670 inside `renderDoseSchedule()`:

  ```js
    // TODAY section
    let html = `<div style="font-size:11px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.05em;margin-bottom:6px;">Today · ${escHtml(todayLabel)}</div>`;
    for (const c of compounds) {
      const dot      = c.dueToday ? `<span style="color:var(--success);">●</span>` : `<span style="color:var(--text-muted);">○</span>`;
      const rowStyle = c.dueToday ? '' : 'opacity:0.5;';
      html += `<div style="display:flex;justify-content:space-between;gap:8px;${rowStyle}">${dot} <span style="flex:1;">${escHtml(trunc(c.name))}</span><span style="color:var(--text-muted);white-space:nowrap;">${escHtml(String(c.dose ?? ''))}${escHtml(c.unit)}</span></div>`;
    }
  ```

- [ ] **Step 2: Replace the Today section with checkbox rows**

  Replace the entire block from `// TODAY section` through the closing `}` of the for-loop (lines 2664–2670) with:

  ```js
    // TODAY section
    const todayStr    = today.toISOString().split('T')[0];
    const takenToday  = lsGet('hrt_doses_taken', []).filter(t => t.date === todayStr);
    const dueCompounds = compounds.filter(c => c.dueToday);
    let html = `<div style="font-size:11px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.05em;margin-bottom:6px;">Today · ${escHtml(todayLabel)}</div>`;
    if (!dueCompounds.length) {
      html += `<div style="color:var(--text-muted);font-size:12px;font-style:italic;">No compounds due today</div>`;
    } else {
      for (const c of dueCompounds) {
        const isChecked = takenToday.some(t => t.label === c.name);
        const rowStyle  = isChecked ? 'text-decoration:line-through;opacity:0.6;' : '';
        const safeName  = c.name.replace(/'/g, "\\'");
        const safeUnit  = (c.unit || '').replace(/'/g, "\\'");
        html += `<label style="display:flex;align-items:center;gap:8px;cursor:pointer;${rowStyle}"><input type="checkbox" ${isChecked ? 'checked' : ''} style="accent-color:var(--primary-bright);width:16px;height:16px;flex-shrink:0;" onchange="this.checked?checkDose('${safeName}',${c.dose ?? 0},'${safeUnit}','${todayStr}'):uncheckDose('${safeName}','${todayStr}')"><span style="flex:1;">${escHtml(trunc(c.name))}</span><span style="color:var(--text-muted);white-space:nowrap;">${escHtml(String(c.dose ?? ''))}${escHtml(c.unit)}</span></label>`;
      }
    }
  ```

  The rest of `renderDoseSchedule()` (UPCOMING section, `el.innerHTML = html`) is unchanged.

- [ ] **Step 3: Verify in the browser — checkboxes appear**

  Open the app with an active protocol that has at least one compound due today. Navigate to the Dashboard. The Dose Schedule card should show:
  - One `<label>` row with a checkbox for each compound due today
  - No ●/○ bullets
  - Non-due compounds do NOT appear in the Today section
  - If all compounds are daily (all due today), all appear as unchecked checkboxes

  If the card shows "No active protocol", set one via My Protocols first.

- [ ] **Step 4: Verify checking a compound**

  Click a checkbox in the Dose Schedule card. The row should:
  - Immediately show as checked (checkbox filled)
  - Compound name gains strikethrough + reduced opacity
  - Card re-renders (no page reload needed)

  In the browser console:
  ```js
  JSON.parse(localStorage.getItem('hrt_doses_taken'))
  // Expected: array contains an entry for the compound you just checked,
  // with today's date and (after a moment) a non-null id if Supabase is connected
  ```

- [ ] **Step 5: Verify unchecking removes the strikethrough**

  Click the same checkbox again to uncheck. The row should:
  - Return to normal style (no strikethrough, full opacity)
  - `hrt_doses_taken` no longer contains that compound for today's date
  - The Supabase `administration_log` row should be deleted (verify in Supabase Table Editor)

- [ ] **Step 6: Verify state persists across page navigations**

  Check a compound. Navigate away (e.g., click "Log Entry" in the sidebar). Navigate back to Dashboard. The compound should still appear checked (state restored from `hrt_doses_taken`).

- [ ] **Step 7: Verify the Upcoming section is unchanged**

  The Upcoming section (non-daily compounds, next 6 days) should still appear below the Today checkboxes exactly as before — no change in content or style.

- [ ] **Step 8: Verify empty-state (if applicable)**

  If testing on a day when no compounds are due (e.g., an EOD compound on its off day), the Today section should show:
  ```
  No compounds due today
  ```
  in muted italic text. (If your protocol has all-daily compounds this state won't appear — that's correct.)

- [ ] **Step 9: Commit**

  ```bash
  git add index.html
  git commit -m "feat: upgrade Dose Schedule card with interactive daily dose checkboxes"
  ```
