# Protocol Dashboard Timing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the protocol dashboard's active-cycle card a reliable daily reference by fixing "due today" logic for all frequency types, adding per-compound next-dose countdowns, extending the upcoming window to 4 weeks, and showing a cycle-end banner in the final 3 weeks.

**Architecture:** Two new pure functions (`isDueToday`, `daysUntilNextDose`) are added at module scope in `index-v2.html` and then consumed by `renderCycleProgress`. The existing compound row HTML is restructured to include a timing line below each compound. No data model changes.

**Tech Stack:** Vanilla JS, single-file app (`index-v2.html`). Tests run as a standalone browser page (`tests/protocol-logic.html`) using a homegrown `assert()` harness.

## Global Constraints

- Single file: all production changes go in `index-v2.html` only — no new files, no build step, no npm
- Test file: `tests/protocol-logic.html` — inline function copies + `assert()` harness; open in browser to run
- No new localStorage keys, no Supabase calls, no UI controls — dashboard remains read-only
- XSS: all user-supplied strings rendered into innerHTML must go through `escHtml()` or the existing `.replace(/</g, '&lt;').replace(/>/g, '&gt;')` pattern
- Preserve existing behavior when `protocol.status !== 'active'` or `!protocol.startDate` — those branches return early and must not regress
- CSS: use only existing variables (`var(--green)`, `var(--amber)`, `var(--text-muted)`, `var(--text-secondary)`, `var(--primary-bright)`, `var(--font-data)`, `var(--border)`) — no hardcoded colors

---

### Task 1: `isDueToday(freq, startDate)` — pure function + tests

**Files:**
- Modify: `index-v2.html` — insert new function after line 3034 (the closing `}` of `pbCurrentCycleWeek`)
- Modify: `tests/protocol-logic.html` — add inline copy + assertions before the `// ── summary ──` comment (line 261)

**Interfaces:**
- Produces: `isDueToday(freq: string | string[], startDate: string) → boolean`
  - `freq`: named frequency string (`'ED'`, `'EOD'`, `'E3.5D'`, etc.) or array of weekday strings (`['Mon','Thu']`)
  - `startDate`: ISO date string (`'2026-06-01'`) or empty string
  - Returns `true` if today is a scheduled dose day; `false` otherwise
  - Array freqs work without `startDate`. `ED`/`PWO` always return `true`. All other named freqs return `false` when `startDate` is absent.

- [ ] **Step 1: Add `isDueToday` to `index-v2.html` after line 3034**

The current line 3034 is the closing `}` of `pbCurrentCycleWeek`. Insert the new function after it (before `function renderCycleProgress`). The full block to insert:

```js
function isDueToday(freq, startDate) {
  const todayDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][new Date().getDay()];
  if (Array.isArray(freq)) return freq.includes(todayDay);

  const f = (freq || '').toUpperCase().trim();
  if (f === 'ED' || f === 'PWO') return true;
  if (!startDate) return false;

  const start = new Date(startDate);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  start.setHours(0, 0, 0, 0);
  const daysSinceStart = Math.round((today - start) / 86400000);
  const startDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][start.getDay()];

  if (f === 'EOD')   return daysSinceStart % 2 === 0;
  if (f === 'E3D')   return daysSinceStart % 3 === 0;
  if (f === 'E4D')   return daysSinceStart % 4 === 0;
  if (f === 'E5D')   return daysSinceStart % 5 === 0;
  if (f === 'E3.5D' || f === '2X/WK') {
    const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    const si = days.indexOf(startDay);
    return todayDay === startDay || todayDay === days[(si + 3) % 7];
  }
  if (f === '3X/WK') {
    const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    const si = days.indexOf(startDay);
    return todayDay === startDay || todayDay === days[(si + 2) % 7] || todayDay === days[(si + 4) % 7];
  }
  if (f === 'WEEKLY')   return todayDay === startDay;
  if (f === 'BI-WKLY')  return todayDay === startDay && daysSinceStart % 14 === 0;
  if (f === 'MONTHLY')  return new Date().getDate() === start.getDate();
  return false;
}
```

- [ ] **Step 2: Add `isDueToday` copy + assertions to `tests/protocol-logic.html`**

Insert before the `// ── summary ──` comment at line 261. The test assertions use dates computed at runtime so they are always deterministic.

```js
// ── isDueToday ──
function isDueToday(freq, startDate) {
  const todayDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][new Date().getDay()];
  if (Array.isArray(freq)) return freq.includes(todayDay);
  const f = (freq || '').toUpperCase().trim();
  if (f === 'ED' || f === 'PWO') return true;
  if (!startDate) return false;
  const start = new Date(startDate);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  start.setHours(0, 0, 0, 0);
  const daysSinceStart = Math.round((today - start) / 86400000);
  const startDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][start.getDay()];
  if (f === 'EOD')   return daysSinceStart % 2 === 0;
  if (f === 'E3D')   return daysSinceStart % 3 === 0;
  if (f === 'E4D')   return daysSinceStart % 4 === 0;
  if (f === 'E5D')   return daysSinceStart % 5 === 0;
  if (f === 'E3.5D' || f === '2X/WK') {
    const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    const si = days.indexOf(startDay);
    return todayDay === startDay || todayDay === days[(si + 3) % 7];
  }
  if (f === '3X/WK') {
    const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    const si = days.indexOf(startDay);
    return todayDay === startDay || todayDay === days[(si + 2) % 7] || todayDay === days[(si + 4) % 7];
  }
  if (f === 'WEEKLY')   return todayDay === startDay;
  if (f === 'BI-WKLY')  return todayDay === startDay && daysSinceStart % 14 === 0;
  if (f === 'MONTHLY')  return new Date().getDate() === start.getDate();
  return false;
}

section('isDueToday');
(function() {
  const todayStr     = new Date().toISOString().split('T')[0];
  const yesterdayStr = new Date(Date.now() - 86400000).toISOString().split('T')[0];
  const todayDay     = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][new Date().getDay()];
  // Find a weekday that is NOT today for negative tests
  const otherDays    = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].filter(d => d !== todayDay);
  const notTodayDay  = otherDays[0];
  // A start date whose weekday === notTodayDay (go back in time until we find it)
  function startDateForWeekday(day) {
    const target = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].indexOf(day);
    for (let i = 1; i <= 7; i++) {
      const d = new Date(Date.now() - i * 86400000);
      if (d.getDay() === target) return d.toISOString().split('T')[0];
    }
  }
  const notTodayStart = startDateForWeekday(notTodayDay);

  assert('ED always true regardless of startDate',        isDueToday('ED', yesterdayStr), true);
  assert('PWO always true regardless of startDate',       isDueToday('PWO', yesterdayStr), true);
  assert('ED true even with no startDate',                isDueToday('ED', ''), true);
  assert('EOD startDate=today (0 days) → true',          isDueToday('EOD', todayStr), true);
  assert('EOD startDate=yesterday (1 day) → false',      isDueToday('EOD', yesterdayStr), false);
  assert('Weekly startDate=today (same weekday) → true', isDueToday('Weekly', todayStr), true);
  assert('Weekly startDate=other weekday → false',       isDueToday('Weekly', notTodayStart), false);
  assert('array includes todayDay → true',               isDueToday([todayDay], todayStr), true);
  assert('array excludes todayDay → false',              isDueToday([notTodayDay], todayStr), false);
  assert('named freq no startDate → false',              isDueToday('EOD', ''), false);
  assert('unknown freq → false',                         isDueToday('BIMONTHLY', todayStr), false);
})();
```

- [ ] **Step 3: Open `tests/protocol-logic.html` in a browser and verify all new assertions pass**

Open the file directly: `open tests/protocol-logic.html`

Expected: the new `isDueToday` section shows 11 green checkmarks. The existing 46 assertions must still all pass (total should now be 57).

- [ ] **Step 4: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat: add isDueToday() — due-today logic for all protocol frequencies"
```

---

### Task 2: `daysUntilNextDose(freq, startDate)` — pure function + tests

**Files:**
- Modify: `index-v2.html` — insert after `isDueToday` (immediately before `function renderCycleProgress`)
- Modify: `tests/protocol-logic.html` — add inline copy + assertions after the `isDueToday` section added in Task 1

**Interfaces:**
- Consumes: nothing from Task 1 (pure function, no calls to `isDueToday`)
- Produces: `daysUntilNextDose(freq: string | string[], startDate: string) → number | null`
  - Returns `0` if today is a dose day, `1`–`6` for days until next dose, `null` for `ED`/`PWO` (no countdown needed) or when next dose is > 6 days away
  - Array freqs work without `startDate`. Named freqs (except `ED`/`PWO`) return `null` when `startDate` is absent.

- [ ] **Step 1: Add `daysUntilNextDose` to `index-v2.html` after `isDueToday`**

Insert directly after the closing `}` of `isDueToday`, still before `function renderCycleProgress`:

```js
function daysUntilNextDose(freq, startDate) {
  const f = Array.isArray(freq) ? '' : (freq || '').toUpperCase().trim();
  if (f === 'ED' || f === 'PWO') return null;

  for (let d = 0; d <= 6; d++) {
    const candidate = new Date();
    candidate.setHours(0, 0, 0, 0);
    candidate.setDate(candidate.getDate() + d);
    const cDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][candidate.getDay()];

    if (Array.isArray(freq)) {
      if (freq.includes(cDay)) return d;
      continue;
    }

    if (!startDate) continue;
    const start = new Date(startDate);
    start.setHours(0, 0, 0, 0);
    const daysSince = Math.round((candidate - start) / 86400000);
    const startDay  = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][start.getDay()];

    if (f === 'EOD'  && daysSince % 2 === 0) return d;
    if (f === 'E3D'  && daysSince % 3 === 0) return d;
    if (f === 'E4D'  && daysSince % 4 === 0) return d;
    if (f === 'E5D'  && daysSince % 5 === 0) return d;
    if (f === 'E3.5D' || f === '2X/WK') {
      const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      const si = days.indexOf(startDay);
      if (cDay === startDay || cDay === days[(si + 3) % 7]) return d;
      continue;
    }
    if (f === '3X/WK') {
      const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      const si = days.indexOf(startDay);
      if (cDay === startDay || cDay === days[(si+2)%7] || cDay === days[(si+4)%7]) return d;
      continue;
    }
    if (f === 'WEEKLY'  && cDay === startDay) return d;
    if (f === 'BI-WKLY' && cDay === startDay && daysSince % 14 === 0) return d;
    if (f === 'MONTHLY' && candidate.getDate() === start.getDate()) return d;
  }
  return null;
}
```

- [ ] **Step 2: Add `daysUntilNextDose` copy + assertions to `tests/protocol-logic.html`**

Insert after the `isDueToday` section (after the `})();` closing the IIFE):

```js
// ── daysUntilNextDose ──
function daysUntilNextDose(freq, startDate) {
  const f = Array.isArray(freq) ? '' : (freq || '').toUpperCase().trim();
  if (f === 'ED' || f === 'PWO') return null;
  for (let d = 0; d <= 6; d++) {
    const candidate = new Date();
    candidate.setHours(0, 0, 0, 0);
    candidate.setDate(candidate.getDate() + d);
    const cDay = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][candidate.getDay()];
    if (Array.isArray(freq)) { if (freq.includes(cDay)) return d; continue; }
    if (!startDate) continue;
    const start = new Date(startDate);
    start.setHours(0, 0, 0, 0);
    const daysSince = Math.round((candidate - start) / 86400000);
    const startDay  = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][start.getDay()];
    if (f === 'EOD'  && daysSince % 2 === 0) return d;
    if (f === 'E3D'  && daysSince % 3 === 0) return d;
    if (f === 'E4D'  && daysSince % 4 === 0) return d;
    if (f === 'E5D'  && daysSince % 5 === 0) return d;
    if (f === 'E3.5D' || f === '2X/WK') {
      const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      const si = days.indexOf(startDay);
      if (cDay === startDay || cDay === days[(si + 3) % 7]) return d; continue;
    }
    if (f === '3X/WK') {
      const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      const si = days.indexOf(startDay);
      if (cDay === startDay || cDay === days[(si+2)%7] || cDay === days[(si+4)%7]) return d; continue;
    }
    if (f === 'WEEKLY'  && cDay === startDay) return d;
    if (f === 'BI-WKLY' && cDay === startDay && daysSince % 14 === 0) return d;
    if (f === 'MONTHLY' && candidate.getDate() === start.getDate()) return d;
  }
  return null;
}

section('daysUntilNextDose');
(function() {
  const todayStr     = new Date().toISOString().split('T')[0];
  const yesterdayStr = new Date(Date.now() - 86400000).toISOString().split('T')[0];
  const todayDay     = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][new Date().getDay()];

  assert('ED → null (every day, no countdown)',          daysUntilNextDose('ED', todayStr), null);
  assert('PWO → null',                                   daysUntilNextDose('PWO', todayStr), null);
  assert('EOD startDate=today → 0 (due today)',          daysUntilNextDose('EOD', todayStr), 0);
  assert('EOD startDate=yesterday → 1 (due tomorrow)',   daysUntilNextDose('EOD', yesterdayStr), 1);
  assert('Weekly startDate=today (same weekday) → 0',   daysUntilNextDose('Weekly', todayStr), 0);
  assert('array [todayDay] → 0',                        daysUntilNextDose([todayDay], todayStr), 0);
  assert('named freq no startDate → null',              daysUntilNextDose('EOD', ''), null);
})();
```

- [ ] **Step 3: Open `tests/protocol-logic.html` in a browser and verify all new assertions pass**

Open: `open tests/protocol-logic.html`

Expected: new `daysUntilNextDose` section shows 7 green checkmarks. Total assertion count should now be 64 (57 from before + 7 new).

- [ ] **Step 4: Commit**

```bash
git add index-v2.html tests/protocol-logic.html
git commit -m "feat: add daysUntilNextDose() — next-injection countdown for all frequencies"
```

---

### Task 3: Update `renderCycleProgress` — timing lines, 4-week upcoming, cycle-end banner

**Files:**
- Modify: `index-v2.html` — rewrite lines 3096–3143 of `renderCycleProgress`

**Interfaces:**
- Consumes: `isDueToday(freq, startDate)` from Task 1; `daysUntilNextDose(freq, startDate)` from Task 2

No new tests — `isDueToday` and `daysUntilNextDose` are already fully tested. Task 3 is a UI-only change to `renderCycleProgress`.

- [ ] **Step 1: Replace the "Active compounds this week" block in `renderCycleProgress`**

Find the block starting at `// Active compounds this week + "due today"` (line ~3096) through `cycleCard.innerHTML = ...` (line ~3143) and replace it entirely with:

```js
  // Active compounds this week + timing
  if (!protocol.compounds.length) return;
  const { rows } = buildWeekGrid(protocol.compounds, totalWeeks || currentWeek);
  const activeThisWeek = rows.filter(r => r.cells[currentWeek - 1] !== null);

  if (!activeThisWeek.length) { cycleCard.innerHTML = ''; return; }

  const activeHtml = activeThisWeek.map(r => {
    const dose      = r.cells[currentWeek - 1];
    const freqLabel = Array.isArray(r.freq) ? r.freq.join(', ') : r.freq;
    const dueToday  = isDueToday(r.freq, protocol.startDate);
    const daysUntil = daysUntilNextDose(r.freq, protocol.startDate);
    const f         = Array.isArray(r.freq) ? '' : (r.freq || '').toUpperCase().trim();
    const isEveryDay = f === 'ED' || f === 'PWO';
    const escapedName = String(r.name).replace(/</g, '&lt;').replace(/>/g, '&gt;');
    let timingLine = '';
    if (isEveryDay) {
      timingLine = `<div style="font-size:11px;color:var(--text-muted);">Every day</div>`;
    } else if (dueToday) {
      timingLine = `<div style="font-size:11px;color:var(--green);">Due today</div>`;
    } else if (daysUntil === 1) {
      timingLine = `<div style="font-size:11px;color:var(--text-muted);">Next dose tomorrow</div>`;
    } else if (daysUntil !== null) {
      timingLine = `<div style="font-size:11px;color:var(--text-muted);">Next dose in ${daysUntil} days</div>`;
    }
    return `<div style="margin-bottom:4px;">
      <div style="display:flex;justify-content:space-between;font-size:12px;padding:3px 0;">
        <span style="color:var(--text-secondary);">${escapedName}</span>
        <span style="font-family:var(--font-data);color:var(--primary-bright);">${dose}${r.unit}</span>
        <span style="color:var(--text-muted);">${freqLabel}</span>
      </div>
      ${timingLine}
    </div>`;
  }).join('');

  // Upcoming changes (next 4 weeks)
  const upcoming = [];
  protocol.compounds.forEach(c => {
    c.phases.forEach((ph, pi) => {
      const nextPh = c.phases[pi + 1];
      if (nextPh && nextPh.startWeek > currentWeek && nextPh.startWeek <= currentWeek + 4) {
        const diff = nextPh.startWeek - currentWeek;
        upcoming.push(`${c.name} → ${nextPh.dose}${c.unit} — Wk ${nextPh.startWeek} (${diff} wk${diff > 1 ? 's' : ''})`);
      }
      if (ph.startWeek > currentWeek && ph.startWeek <= currentWeek + 4 && pi === 0) {
        const diff = ph.startWeek - currentWeek;
        upcoming.push(`${c.name} starts ${ph.dose}${c.unit} — Wk ${ph.startWeek} (${diff} wk${diff > 1 ? 's' : ''})`);
      }
    });
  });

  // Cycle-end banner (last 3 weeks)
  const weeksLeft = totalWeeks - currentWeek;
  const cycleEndBanner = (totalWeeks > 0 && weeksLeft >= 0 && weeksLeft <= 3)
    ? `<div style="margin:8px 0;padding:6px 10px;background:rgba(251,191,36,0.1);border-radius:6px;font-size:11px;color:var(--amber);">
        Cycle ends ${weeksLeft === 0 ? 'this week' : 'in ' + weeksLeft + ' week' + (weeksLeft > 1 ? 's' : '')} — consider planning your next protocol
      </div>`
    : '';

  const upcomingHtml = upcoming.length
    ? `<div style="margin-top:10px;padding-top:8px;border-top:1px solid var(--border);">
        <div style="font-size:11px;color:var(--text-muted);margin-bottom:4px;text-transform:uppercase;letter-spacing:.05em;">Upcoming</div>
        ${upcoming.map(u => `<div style="font-size:11px;color:var(--text-secondary);">→ ${u}</div>`).join('')}
      </div>`
    : '';

  cycleCard.innerHTML = `
    <div style="font-size:11px;color:var(--text-muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em;">Active this week</div>
    ${activeHtml}
    ${cycleEndBanner}
    ${upcomingHtml}
  `;
```

- [ ] **Step 2: Verify the render visually**

Load `index-v2.html` in a browser (via a local server — e.g., `python3 -m http.server 3000` from the project root, then open `http://localhost:3000/index-v2.html`). Navigate to the Dashboard.

Check each scenario by temporarily editing the active protocol's `startDate` and `cycleLengthWeeks` in localStorage (browser DevTools → Application → Local Storage → `hrt_active_protocol_data`):

| Test scenario | Expected |
|---|---|
| Compound with `freq: 'ED'`, any startDate | Row shows "Every day" timing line |
| Compound with `freq: 'EOD'`, startDate = today | Row shows "Due today" in green |
| Compound with `freq: 'EOD'`, startDate = yesterday | Row shows "Next dose tomorrow" |
| Compound with `freq: ['Mon','Thu']`, today is Mon or Thu | Row shows "Due today" |
| `totalWeeks: 12`, `startDate` 10 weeks ago (currentWeek=11) | Amber banner: "Cycle ends in 1 week — consider planning your next protocol" |
| `totalWeeks: 12`, `startDate` 9 weeks ago (currentWeek=10) | Amber banner: "Cycle ends in 2 weeks…" |
| `totalWeeks: 16`, `startDate` 2 weeks ago (currentWeek=3) | No banner |
| Compound with phase change at currentWeek+3 | Change appears in Upcoming section |
| Compound with phase change at currentWeek+5 | Does NOT appear (beyond 4-week window) |

- [ ] **Step 3: Commit**

```bash
git add index-v2.html
git commit -m "feat: protocol dashboard — timing lines, 4-week upcoming, cycle-end banner"
```
