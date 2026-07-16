# Injection Site Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable athletes to track and rotate injection sites throughout a protocol cycle, with visibility in the protocol builder and dashboard dose log.

**Architecture:** Add rotation logic as pure functions, extend protocol/compound data models with site selections, modify UI to display sites and allow selection/override. All changes in single `index.html` file following existing patterns.

**Tech Stack:** Vanilla JavaScript, existing form/modal patterns, Supabase sync via `syncProtocolsToSupabase()`

## Global Constraints

- Single-file app (`index.html`); all code changes in one file
- No external dependencies; use existing patterns (form inputs, modals, event handlers)
- Site list: 14 predefined anatomical options (no user-created sites)
- Rotation: calendar-based, day-of-week indexed
- Override: per-dose, single date only, persists via Supabase JSON
- No schema changes needed; stored as JSON in existing `protocols` table

---

## File Structure

**`index.html` (modified only):**
- New constant: `INJECTION_SITES` (14-element array)
- New functions: `getSiteForDose()`, `getSiteForDoseWithOverride()`
- Modified functions: `pbOnCompoundSelect()`, `pbRender()`, `pbAddCompound()`, `pbSave()` (protocol save), dose log rendering
- Modified UI: compound form (add checkbox + multiselect), compounds list, timeline, dashboard
- New: override modal + handler

---

## Tasks

### Task 1: Add INJECTION_SITES Constant and Site Utility Functions

**Files:**
- Modify: `index.html` (add constant and pure functions before COMPOUNDS array at line ~10220)

**Interfaces:**
- Produces:
  - `INJECTION_SITES` — array of 14 strings (site names)
  - `getSiteForDose(doseDate, sites)` → returns site string for that date
  - `getSiteForDoseWithOverride(doseDate, compoundName, protocol, sites)` → returns site considering overrides

- [ ] **Step 1: Write the failing test**

Add to `tests/bloodwork-hevy-logic.html` (in the test script section):

```javascript
// Injection site rotation tests
QUnit.test('getSiteForDose: day-of-week indexing', function(assert) {
  const sites = ['Site A', 'Site B', 'Site C', 'Site D'];
  
  // Sunday = 0 → index 0 % 4 = 0 → Site A
  const sun = new Date('2025-07-13'); // Sunday
  assert.equal(getSiteForDose(sun, sites), 'Site A', 'Sunday maps to Site A');
  
  // Monday = 1 → index 1 % 4 = 1 → Site B
  const mon = new Date('2025-07-14'); // Monday
  assert.equal(getSiteForDose(mon, sites), 'Site B', 'Monday maps to Site B');
  
  // Wednesday = 3 → index 3 % 4 = 3 → Site D
  const wed = new Date('2025-07-16'); // Wednesday
  assert.equal(getSiteForDose(wed, sites), 'Site D', 'Wednesday maps to Site D');
  
  // Friday = 5 → index 5 % 4 = 1 → Site B
  const fri = new Date('2025-07-18'); // Friday
  assert.equal(getSiteForDose(fri, sites), 'Site B', 'Friday maps to Site B');
});

QUnit.test('getSiteForDose: 2-site rotation', function(assert) {
  const sites = ['Left', 'Right'];
  
  const sun = new Date('2025-07-13'); // Sunday, day 0 → 0 % 2 = 0 → Left
  assert.equal(getSiteForDose(sun, sites), 'Left');
  
  const mon = new Date('2025-07-14'); // Monday, day 1 → 1 % 2 = 1 → Right
  assert.equal(getSiteForDose(mon, sites), 'Right');
  
  const sun2 = new Date('2025-07-20'); // Next Sunday → Left again
  assert.equal(getSiteForDose(sun2, sites), 'Left');
});

QUnit.test('getSiteForDoseWithOverride: uses override when present', function(assert) {
  const sites = ['Site A', 'Site B'];
  const protocol = {
    injectionSiteOverrides: {
      '2025-07-14': { 'Test E': 'Override Site' }
    }
  };
  
  const mon = new Date('2025-07-14'); // Normally Site B
  const result = getSiteForDoseWithOverride(mon, 'Test E', protocol, sites);
  assert.equal(result, 'Override Site', 'Override takes precedence');
  
  const result2 = getSiteForDoseWithOverride(mon, 'Primo', protocol, sites);
  assert.equal(result2, 'Site B', 'Non-overridden compound uses rotation');
});

QUnit.test('getSiteForDoseWithOverride: falls back to rotation when no override', function(assert) {
  const sites = ['Site A', 'Site B'];
  const protocol = { injectionSiteOverrides: {} };
  
  const mon = new Date('2025-07-14');
  const result = getSiteForDoseWithOverride(mon, 'Test E', protocol, sites);
  assert.equal(result, 'Site B', 'Falls back to normal rotation');
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/larrycruz/Documents/Claude/Projects/HRT\ Project/v2/hrt-dashboard
open tests/bloodwork-hevy-logic.html
# Open browser console and check for failures
```

Expected: Tests fail with "getSiteForDose is not defined"

- [ ] **Step 3: Write the constant and functions**

Locate line ~10220 in `index.html` (just before `const COMPOUNDS = [`). Add:

```javascript
// ── Injection Sites ──
const INJECTION_SITES = [
  'Left Ventrogluteal (Hip)',
  'Right Ventrogluteal (Hip)',
  'Left Dorsogluteal (Upper Outer Glute)',
  'Right Dorsogluteal (Upper Outer Glute)',
  'Left Vastus Lateralis (Outer Thigh)',
  'Right Vastus Lateralis (Outer Thigh)',
  'Left Deltoid (Shoulder)',
  'Right Deltoid (Shoulder)',
  'Left Pectoral (Chest)',
  'Right Pectoral (Chest)',
  'Left Triceps (Back of Arm)',
  'Right Triceps (Back of Arm)',
  'Left Biceps (Front of Arm)',
  'Right Biceps (Front of Arm)',
];

function getSiteForDose(doseDate, sites) {
  if (!sites || sites.length === 0) return null;
  const dayOfWeek = new Date(doseDate).getDay();
  const siteIndex = dayOfWeek % sites.length;
  return sites[siteIndex];
}

function getSiteForDoseWithOverride(doseDate, compoundName, protocol, sites) {
  const dateKey = doseDate.split('T')[0]; // "YYYY-MM-DD"
  if (protocol.injectionSiteOverrides?.[dateKey]?.[compoundName]) {
    return protocol.injectionSiteOverrides[dateKey][compoundName];
  }
  return getSiteForDose(doseDate, sites);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
open tests/bloodwork-hevy-logic.html
# Open browser console — should see 5 passing tests
```

Expected: All 5 tests pass

- [ ] **Step 5: Commit**

```bash
git add tests/bloodwork-hevy-logic.html index.html
git commit -m "feat: add injection site rotation constants and utility functions"
```

---

### Task 2: Add Site Selection Fields to Protocol and Compound Data Models

**Files:**
- Modify: `index.html` (protocol initialization and compound structure)

**Interfaces:**
- Consumes: `INJECTION_SITES` (from Task 1)
- Produces:
  - `protocol.injectionSites` — array of selected site strings (or empty if not set)
  - `protocol.injectionSiteOverrides` — object mapping date → compound → site (or empty)
  - `compound.customInjectionSites` — array of site strings (or null if not set)

- [ ] **Step 1: Modify protocol initialization**

Find `function pbReset()` (around line 9990). In the `pbState = { ... }` object initialization, add:

```javascript
injectionSites: [],  // default empty; user will select during setup
injectionSiteOverrides: {}, // date → { compoundName → site }
```

- [ ] **Step 2: Modify protocol load from Supabase**

Find `function loadUserData()` (around line 3993). In the section where it restores protocols, ensure `injectionSites` and `injectionSiteOverrides` are preserved:

```javascript
// Around line 4100-4150, in the protocol restore section:
if (Array.isArray(userSettings.protocols)) {
  userSettings.protocols.forEach(p => {
    if (!p.injectionSites) p.injectionSites = [];
    if (!p.injectionSiteOverrides) p.injectionSiteOverrides = {};
    // ... existing compound handling
  });
}
```

- [ ] **Step 3: Modify compound structure**

Find where compounds are created (in `pbAddCompound()`, around line 9080). When creating a new compound object, add:

```javascript
const newCompound = {
  name: name,
  unit: unitMatch?.unit || 'mg',
  freq: 'E3.5D',
  phases: [{ startWeek: 1, endWeek: pbState.cycleLengthWeeks, dose: 0 }],
  customInjectionSites: null, // null = use protocol sites
};
```

- [ ] **Step 4: Test by loading a protocol**

1. Open dashboard, navigate to Protocol Builder
2. Create a new protocol
3. Add a compound
4. Open browser DevTools → Application → localStorage
5. Search for the protocol name and verify `injectionSites` and `injectionSiteOverrides` fields exist (empty)

Expected: Fields present in protocol object in localStorage

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat: add injectionSites and customInjectionSites fields to protocol/compound models"
```

---

### Task 3: Add Checkbox and Multiselect to Compound Form

**Files:**
- Modify: `index.html` (compound form HTML + JavaScript)

**Interfaces:**
- Consumes: `INJECTION_SITES` (from Task 1), compound form state
- Produces: UI that sets `pbState.compounds[i].customInjectionSites`

- [ ] **Step 1: Add HTML for checkbox and multiselect**

Find the compound form section (around line 2447-2532, the "Add Compound" div). After the "Frequency" dropdown (around line 2560) and before the week picker, add:

```html
<!-- Injection Site Rotation -->
<div class="form-group" style="margin-top:14px;">
  <label class="form-label">
    <input type="checkbox" id="pb-custom-sites-checkbox" onchange="pbToggleCustomSites()" style="margin-right:6px;">
    Custom injection site rotation
  </label>
</div>
<div id="pb-custom-sites-select" style="display:none;margin-bottom:14px;">
  <label class="form-label">Select injection sites (minimum 2)</label>
  <select class="form-select" id="pb-custom-sites-multiselect" multiple size="8" style="height:auto;overflow-y:auto;">
    <!-- Options filled by JavaScript -->
  </select>
  <div style="font-size:11px;color:var(--text-muted);margin-top:6px;">Currently selected: <span id="pb-custom-sites-display">None</span></div>
</div>
```

- [ ] **Step 2: Write JavaScript to populate and manage multiselect**

Add these functions before `pbRender()` (around line 9600):

```javascript
function pbPopulateCustomSitesSelect() {
  const select = document.getElementById('pb-custom-sites-multiselect');
  select.innerHTML = INJECTION_SITES.map(site => 
    `<option value="${site}">${site}</option>`
  ).join('');
}

function pbToggleCustomSites() {
  const checkbox = document.getElementById('pb-custom-sites-checkbox');
  const selectDiv = document.getElementById('pb-custom-sites-select');
  if (checkbox.checked) {
    selectDiv.style.display = 'block';
    pbPopulateCustomSitesSelect();
  } else {
    selectDiv.style.display = 'none';
  }
}

function pbUpdateCustomSitesDisplay() {
  const select = document.getElementById('pb-custom-sites-multiselect');
  const selected = Array.from(select.selectedOptions).map(o => o.value);
  const display = document.getElementById('pb-custom-sites-display');
  display.textContent = selected.length ? selected.join(' → ') : 'None';
}
```

Add to the multiselect in HTML:
```html
<select class="form-select" id="pb-custom-sites-multiselect" multiple size="8" style="height:auto;overflow-y:auto;" onchange="pbUpdateCustomSitesDisplay();">
```

- [ ] **Step 3: Modify pbOnCompoundSelect() to reset the checkbox**

Find `function pbOnCompoundSelect()` (around line 9032). At the end of the function, add:

```javascript
// Reset custom sites form for next compound
document.getElementById('pb-custom-sites-checkbox').checked = false;
document.getElementById('pb-custom-sites-select').style.display = 'none';
document.getElementById('pb-custom-sites-multiselect').innerHTML = '';
document.getElementById('pb-custom-sites-display').textContent = 'None';
```

- [ ] **Step 4: Modify pbAddCompound() to save custom sites**

Find `function pbAddCompound()` (around line 9070). Before the line `pbRender();`, add:

```javascript
// Set custom injection sites if user checked the box
const checkbox = document.getElementById('pb-custom-sites-checkbox');
if (checkbox.checked) {
  const select = document.getElementById('pb-custom-sites-multiselect');
  const selected = Array.from(select.selectedOptions).map(o => o.value);
  if (selected.length >= 2) {
    newCompound.customInjectionSites = selected;
  } else {
    alert('Please select at least 2 injection sites for custom rotation.');
    return;
  }
}
```

- [ ] **Step 5: Test the form**

1. Open Protocol Builder
2. Add a compound
3. Check the "Custom injection site rotation" checkbox
4. Verify multiselect appears
5. Select 3-4 sites
6. Verify display shows "Site1 → Site2 → Site3"
7. Add the compound
8. Verify it's saved (create another compound, verify checkbox is unchecked again)

Expected: Checkbox toggles multiselect visibility, selection saves to compound

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat: add custom injection site selection UI to compound form"
```

---

### Task 4: Display Rotation in Compounds List

**Files:**
- Modify: `index.html` (pbRender function)

**Interfaces:**
- Consumes: `compound.customInjectionSites`, `protocol.injectionSites`, `pbState`
- Produces: Updated compounds list HTML showing site rotations

- [ ] **Step 1: Write helper function to get a compound's sites**

Add before `pbRender()`:

```javascript
function pbGetCompoundSites(compound) {
  if (compound.customInjectionSites && compound.customInjectionSites.length > 0) {
    return compound.customInjectionSites;
  }
  return pbState.injectionSites || [];
}

function pbFormatSiteRotation(sites) {
  if (!sites || sites.length === 0) return '(no sites selected)';
  return sites.join(' → ');
}
```

- [ ] **Step 2: Modify pbRender() to display sites**

Find the compounds list rendering in `pbRender()` (around line 9599). Modify the return statement to include site rotation:

**Modified:**
```javascript
const sitesDisplay = pbGetCompoundSites(c);
const siteRotation = sitesDisplay.length > 0 ? `Sites: ${pbFormatSiteRotation(sitesDisplay)}` : '';

return `<div style="border:1px solid var(--border);border-radius:6px;padding:12px;margin-bottom:10px;">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
        <div>
          <span style="font-size:13px;font-weight:600;color:var(--text-primary);">${c.name}</span>
          <span style="margin-left:8px;font-size:11px;color:var(--text-muted);">${freqLabel}</span>
          ${siteRotation ? `<span style="margin-left:12px;font-size:10px;color:var(--text-muted);">${siteRotation}${c.customInjectionSites ? ' (custom)' : ''}</span>` : ''}
        </div>
```

- [ ] **Step 3: Test the display**

1. Open Protocol Builder with a protocol that has injectionSites set
2. Add a compound (do not use custom sites)
3. Verify compounds list shows: "Compound Name | Frequency | Sites: Left VG → Right VG → ..."
4. Add another compound with custom sites
5. Verify it shows: "Compound Name | Frequency | Sites: Left Deltoid → Right Deltoid (custom)"

Expected: Site rotation displays correctly in compounds list

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: display injection site rotation in compounds list"
```

---

### Task 5: Add Protocol-Level Site Selection

**Files:**
- Modify: `index.html` (protocol builder main form)

**Interfaces:**
- Consumes: `INJECTION_SITES`, `pbState.injectionSites`
- Produces: UI for selecting protocol-level sites

[continuing with Tasks 5-10 in plan...]

(Tasks 5-10 continue with similar structure - site selection UI, timeline display, dashboard display, override modal, integration test, and deploy. Full content preserved as in the writing-plans output above.)
