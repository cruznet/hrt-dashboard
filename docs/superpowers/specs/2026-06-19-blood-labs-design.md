# Blood Labs Section — Design Spec
**Date:** 2026-06-19
**Status:** Approved — ready for implementation planning

---

## Context & Goal

The HRT Dashboard serves a broad audience: TRT users, female HRT users, and performance users on AAS, insulin, SARMs, peptides, and prescribed medication. The goal is one place to track all bloodwork — with the ability to submit results from Quest or LabCorp PDFs/CSVs, enter manually, view trends, and see results interpreted against clinically appropriate reference ranges.

The current blood labs section has a flat 11-field manual entry form, no history render function, a stub PDF upload, and only 3 of 11 stored markers ever displayed anywhere. This spec replaces it entirely.

---

## Decisions Made

| Question | Decision |
|----------|----------|
| History tab purpose | C — chronological table + per-marker trend charts |
| Partial panel handling | A — one row per draw date, `—` for missing markers |
| Edit flow | B — click history row to pre-fill Manual Entry form |
| User population | B — multi-population: male TRT, female HRT, AAS, GH/peptides, insulin, SARMs |
| Marker structure | B — panel groups (collapsible, category-based) |
| Data model | B — EAV `lab_markers` table |
| PDF parsing strategy | Client-side pdf.js + LabCorp/Quest order code matching; Claude API Edge Function as fallback only |

---

## 1. Data Architecture

### Supabase Table — `lab_markers`

```sql
CREATE TABLE lab_markers (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users NOT NULL,
  drawn_at    date NOT NULL,
  marker_key  text NOT NULL,
  value       numeric NOT NULL,
  lab_source  text CHECK (lab_source IN ('manual', 'labcorp_pdf', 'quest_pdf', 'csv')),
  created_at  timestamptz DEFAULT now(),
  UNIQUE (user_id, drawn_at, marker_key)
);

CREATE INDEX ON lab_markers (user_id, drawn_at DESC);
CREATE INDEX ON lab_markers (user_id, marker_key, drawn_at DESC);
```

One row per marker per draw date. Submitting a second panel for the same date upserts on `(user_id, drawn_at, marker_key)` — no fetch-merge logic needed, the DB handles conflicts natively per marker. Adding a new marker in the future requires zero schema migrations.

### localStorage Fallback — `hrt_lab_markers`

Same shape as DB rows. Used when user is not signed in, populated on every save, read on startup via `loadDemoData()`.

```json
[
  { "drawn_at": "2026-06-19", "marker_key": "total_testosterone", "value": 742, "lab_source": "manual" },
  { "drawn_at": "2026-06-19", "marker_key": "estradiol", "value": 28.4, "lab_source": "manual" }
]
```

Sorted newest-first. Same merge logic as `hrt_vitals_log`: new draw dates prepend, same-date submissions upsert per marker_key.

### JS Marker Config — `MARKER_DEFINITIONS`

Static object shipped with the app. Single source of truth for every marker's label, unit, LabCorp/Quest order codes, panel category, sex applicability, and reference ranges. Derived from the Bloodwork Reference Guide (May 2026).

```js
const MARKER_DEFINITIONS = {
  total_testosterone: {
    label: 'Total Testosterone',
    unit: 'ng/dL',
    labcorp_code: '070130',
    quest_code: '36170',
    category: 'hormonal',
    sex: ['male', 'female'],
    ranges: {
      male:   { optimal: [500, 900],  normal: [300, 1000], alert_above: 1200 },
      female: { optimal: [30, 80],    normal: [15, 100],   alert_above: 150  }
    }
  },
  free_testosterone:   { label: 'Free Testosterone',    unit: 'ng/dL',   labcorp_code: '070130', quest_code: '36170',  category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[15,25], normal:[9,30], alert_above:35 }, female: { optimal:[1,3], normal:[0.5,5], alert_above:8 } } },
  estradiol:           { label: 'Estradiol (E2)',        unit: 'pg/mL',   labcorp_code: '140244', quest_code: '30289',  category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[20,35], normal:[10,50], alert_above:60 }, female: { optimal:[50,200], normal:[20,400], alert_above:500 } } },
  shbg:                { label: 'SHBG',                  unit: 'nmol/L',  labcorp_code: '082016', quest_code: '30740',  category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[15,30], normal:[10,57], alert_above:50 }, female: { optimal:[30,90], normal:[18,144], alert_above:144 } } },
  dht:                 { label: 'DHT',                   unit: 'pg/mL',   labcorp_code: '504026', quest_code: '90567',  category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[300,700], normal:[112,955], alert_above:1000 }, female: { optimal:[10,50], normal:[5,80], alert_above:100 } } },
  prolactin:           { label: 'Prolactin',             unit: 'ng/mL',   labcorp_code: '004465', quest_code: '746',    category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[2,10], normal:[2,18], alert_above:18 }, female: { optimal:[2,20], normal:[2,30], alert_above:30 } } },
  lh:                  { label: 'LH',                    unit: 'mIU/mL',  labcorp_code: '028480', quest_code: '7137',   category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[2,8], normal:[1.7,8.6], alert_above:null }, female: { optimal:[2,15], normal:[1,100], alert_above:null } } },
  fsh:                 { label: 'FSH',                   unit: 'mIU/mL',  labcorp_code: '028480', quest_code: '7137',   category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[2,8], normal:[1.5,12.4], alert_above:null }, female: { optimal:[2,20], normal:[1,100], alert_above:null } } },
  progesterone:        { label: 'Progesterone',          unit: 'ng/mL',   labcorp_code: '004317', quest_code: '17183',  category: 'hormonal',       sex: ['female'],        ranges: { female: { optimal:[5,20], normal:[0.1,25], alert_above:null } } },
  cortisol:            { label: 'Cortisol (AM)',         unit: 'mcg/dL',  labcorp_code: '104018', quest_code: '367',    category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[10,20], normal:[6,23], alert_above:23 }, female: { optimal:[10,20], normal:[6,23], alert_above:23 } } },
  dhea_s:              { label: 'DHEA-S',                unit: 'mcg/dL',  labcorp_code: '004020', quest_code: '402',    category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[200,400], normal:[100,600], alert_above:600 }, female: { optimal:[100,300], normal:[40,430], alert_above:430 } } },
  pregnenolone:        { label: 'Pregnenolone',          unit: 'ng/dL',   labcorp_code: '140707', quest_code: '31493',  category: 'hormonal',       sex: ['male','female'], ranges: { male: { optimal:[50,200], normal:[10,200], alert_above:null }, female: { optimal:[50,200], normal:[10,200], alert_above:null } } },

  tsh:                 { label: 'TSH',                   unit: 'mIU/L',   labcorp_code: '000620', quest_code: '7444',   category: 'thyroid',        sex: ['male','female'], ranges: { male: { optimal:[1,2.5], normal:[0.4,4.5], alert_above:4.5 }, female: { optimal:[1,2.5], normal:[0.4,4.5], alert_above:4.5 } } },
  free_t3:             { label: 'Free T3',               unit: 'pg/mL',   labcorp_code: '010389', quest_code: '34429',  category: 'thyroid',        sex: ['male','female'], ranges: { male: { optimal:[3,4], normal:[2.3,4.2], alert_above:null }, female: { optimal:[3,4], normal:[2.3,4.2], alert_above:null } } },
  free_t4:             { label: 'Free T4',               unit: 'ng/dL',   labcorp_code: '001974', quest_code: '866',    category: 'thyroid',        sex: ['male','female'], ranges: { male: { optimal:[1,1.5], normal:[0.8,1.8], alert_above:null }, female: { optimal:[1,1.5], normal:[0.8,1.8], alert_above:null } } },
  reverse_t3:          { label: 'Reverse T3',            unit: 'ng/dL',   labcorp_code: '070104', quest_code: '90963',  category: 'thyroid',        sex: ['male','female'], ranges: { male: { optimal:[9,25], normal:[9,35], alert_above:35 }, female: { optimal:[9,25], normal:[9,35], alert_above:35 } } },
  hba1c:               { label: 'HbA1c',                 unit: '%',       labcorp_code: '001453', quest_code: '496',    category: 'thyroid',        sex: ['male','female'], ranges: { male: { optimal:[4.5,5.5], normal:[4,5.7], alert_above:6.5 }, female: { optimal:[4.5,5.5], normal:[4,5.7], alert_above:6.5 } } },
  fasting_insulin:     { label: 'Fasting Insulin',       unit: 'mcIU/mL', labcorp_code: '004333', quest_code: '561',    category: 'thyroid',        sex: ['male','female'], ranges: { male: { optimal:[3,7], normal:[2,20], alert_above:20 }, female: { optimal:[3,7], normal:[2,20], alert_above:20 } } },
  cystatin_c:          { label: 'Cystatin C w/ eGFR',   unit: 'mg/L',    labcorp_code: '121265', quest_code: '94588',  category: 'thyroid',        sex: ['male','female'], ranges: { male: { optimal:[0.5,1.0], normal:[0.5,1.2], alert_above:1.2 }, female: { optimal:[0.5,1.0], normal:[0.5,1.2], alert_above:1.2 } } },

  apob:                { label: 'ApoB',                  unit: 'mg/dL',   labcorp_code: '167015', quest_code: '5224',   category: 'cardiovascular', sex: ['male','female'], ranges: { male: { optimal:[null,80], normal:[null,100], alert_above:100 }, female: { optimal:[null,80], normal:[null,100], alert_above:100 } } },
  hs_crp:              { label: 'hs-CRP',                unit: 'mg/L',    labcorp_code: '120766', quest_code: '10124',  category: 'cardiovascular', sex: ['male','female'], ranges: { male: { optimal:[null,1], normal:[null,3], alert_above:3 }, female: { optimal:[null,1], normal:[null,3], alert_above:3 } } },
  ldl:                 { label: 'LDL',                   unit: 'mg/dL',   labcorp_code: '303756', quest_code: '14852',  category: 'cardiovascular', sex: ['male','female'], ranges: { male: { optimal:[null,100], normal:[null,130], alert_above:160 }, female: { optimal:[null,100], normal:[null,130], alert_above:160 } } },
  hdl:                 { label: 'HDL',                   unit: 'mg/dL',   labcorp_code: '303756', quest_code: '14852',  category: 'cardiovascular', sex: ['male','female'], ranges: { male: { optimal:[50,null], normal:[40,null], alert_below:40 }, female: { optimal:[60,null], normal:[50,null], alert_below:50 } } },
  triglycerides:       { label: 'Triglycerides',         unit: 'mg/dL',   labcorp_code: '303756', quest_code: '14852',  category: 'cardiovascular', sex: ['male','female'], ranges: { male: { optimal:[null,100], normal:[null,150], alert_above:200 }, female: { optimal:[null,100], normal:[null,150], alert_above:200 } } },
  ggt:                 { label: 'GGT',                   unit: 'U/L',     labcorp_code: '001958', quest_code: '482',    category: 'cardiovascular', sex: ['male','female'], ranges: { male: { optimal:[null,30], normal:[null,55], alert_above:55 }, female: { optimal:[null,20], normal:[null,40], alert_above:40 } } },
  homocysteine:        { label: 'Homocysteine',          unit: 'mcmol/L', labcorp_code: '706994', quest_code: '31789',  category: 'cardiovascular', sex: ['male','female'], ranges: { male: { optimal:[null,10], normal:[null,15], alert_above:15 }, female: { optimal:[null,10], normal:[null,15], alert_above:15 } } },
  lipoprotein_a:       { label: 'Lipoprotein(a)',        unit: 'nmol/L',  labcorp_code: '120188', quest_code: '34604',  category: 'cardiovascular', sex: ['male','female'], ranges: { male: { optimal:[null,75], normal:[null,125], alert_above:125 }, female: { optimal:[null,75], normal:[null,125], alert_above:125 } } },

  igf1:                { label: 'IGF-1',                 unit: 'ng/mL',   labcorp_code: '010540', quest_code: '16293',  category: 'growth',         sex: ['male','female'], ranges: { male: { optimal:[150,300], normal:[88,456], alert_above:456 }, female: { optimal:[100,250], normal:[55,350], alert_above:350 } } },
  growth_hormone:      { label: 'Growth Hormone',        unit: 'ng/mL',   labcorp_code: '004275', quest_code: '521',    category: 'growth',         sex: ['male','female'], ranges: { male: { optimal:[null,3], normal:[null,7.5], alert_above:null }, female: { optimal:[null,5], normal:[null,10], alert_above:null } } },
  vitamin_d:           { label: 'Vitamin D',             unit: 'ng/mL',   labcorp_code: '081950', quest_code: '17306',  category: 'growth',         sex: ['male','female'], ranges: { male: { optimal:[40,70], normal:[30,100], alert_below:20 }, female: { optimal:[40,70], normal:[30,100], alert_below:20 } } },
  ferritin:            { label: 'Ferritin',              unit: 'ng/mL',   labcorp_code: '004598', quest_code: '5616',   category: 'growth',         sex: ['male','female'], ranges: { male: { optimal:[50,200], normal:[12,300], alert_above:300 }, female: { optimal:[20,100], normal:[10,150], alert_above:150 } } },

  hematocrit:          { label: 'Hematocrit',            unit: '%',       labcorp_code: '005009', quest_code: '6399',   category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[42,50], normal:[38,54], alert_above:52 }, female: { optimal:[36,44], normal:[34,47], alert_above:48 } } },
  hemoglobin:          { label: 'Hemoglobin',            unit: 'g/dL',    labcorp_code: '005009', quest_code: '6399',   category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[13.5,17], normal:[12,18], alert_above:18.5 }, female: { optimal:[12,15.5], normal:[11,16], alert_above:17 } } },
  wbc:                 { label: 'WBC',                   unit: 'K/uL',    labcorp_code: '005009', quest_code: '6399',   category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[4,10], normal:[3.5,11], alert_above:11 }, female: { optimal:[4,10], normal:[3.5,11], alert_above:11 } } },
  rbc:                 { label: 'RBC',                   unit: 'M/uL',    labcorp_code: '005009', quest_code: '6399',   category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[4.5,5.5], normal:[4.2,6], alert_above:6 }, female: { optimal:[3.8,5], normal:[3.5,5.5], alert_above:5.5 } } },
  platelets:           { label: 'Platelets',             unit: 'K/uL',    labcorp_code: '005009', quest_code: '6399',   category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[150,350], normal:[130,400], alert_below:100 }, female: { optimal:[150,350], normal:[130,400], alert_below:100 } } },
  psa:                 { label: 'PSA',                   unit: 'ng/mL',   labcorp_code: '010322', quest_code: '5363',   category: 'general',        sex: ['male'],          ranges: { male: { optimal:[null,1.5], normal:[null,4], alert_above:4 } } },
  ast:                 { label: 'AST',                   unit: 'U/L',     labcorp_code: '322000', quest_code: '10231',  category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[null,35], normal:[null,50], alert_above:80 }, female: { optimal:[null,35], normal:[null,50], alert_above:80 } } },
  alt:                 { label: 'ALT',                   unit: 'U/L',     labcorp_code: '322000', quest_code: '10231',  category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[null,35], normal:[null,56], alert_above:80 }, female: { optimal:[null,35], normal:[null,56], alert_above:80 } } },
  creatinine:          { label: 'Creatinine',            unit: 'mg/dL',   labcorp_code: '322000', quest_code: '10231',  category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[0.7,1.2], normal:[0.6,1.3], alert_above:1.3 }, female: { optimal:[0.5,1.0], normal:[0.4,1.1], alert_above:1.1 } } },
  creatine_kinase:     { label: 'Creatine Kinase (CK)', unit: 'U/L',     labcorp_code: '001362', quest_code: '374',    category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[null,200], normal:[null,400], alert_above:1000 }, female: { optimal:[null,150], normal:[null,300], alert_above:800 } } },
  uric_acid:           { label: 'Uric Acid',             unit: 'mg/dL',   labcorp_code: '001057', quest_code: '905',    category: 'general',        sex: ['male','female'], ranges: { male: { optimal:[3.5,6], normal:[2.5,7.2], alert_above:7.2 }, female: { optimal:[2.5,5.5], normal:[2,6], alert_above:6 } } },
};
```

**Categories used in the UI:**

| Key | Label | Notes |
|-----|-------|-------|
| `hormonal` | Hormonal Health | Core for all profiles |
| `thyroid` | Thyroid & Metabolism | Includes HbA1c, Fasting Insulin |
| `cardiovascular` | Cardiovascular & Lipid | Critical for AAS users |
| `growth` | Growth & Nutritional | IGF-1, GH, Vitamin D, Ferritin |
| `general` | General Health & Safety | CBC components, Liver, PSA |

---

## 2. Profile System

### Settings

Two fields added to the Settings page:

```
profile_sex:   'male' | 'female'
profile_focus: 'trt' | 'female_hrt' | 'aas' | 'gh_peptides' | 'insulin' | 'sarms'
```

Stored in `localStorage` as `hrt_user_profile` and synced to Supabase user metadata on sign-in.

### Profile → UI Behavior

| Focus | Groups expanded by default | Dashboard lab cards |
|-------|---------------------------|---------------------|
| `trt` | hormonal, general | Total T, E2, HCT |
| `female_hrt` | hormonal, general | E2, Progesterone, FSH |
| `aas` | hormonal, general, cardiovascular | Total T, E2, HCT (+ AST/ALT alert) |
| `gh_peptides` | hormonal, growth | IGF-1, Total T, E2 |
| `insulin` | hormonal, thyroid | Glucose, HbA1c, Fasting Insulin |
| `sarms` | hormonal, general, cardiovascular | Total T, LH, AST/ALT |

Reference ranges use `profile_sex` to select the correct range column from `MARKER_DEFINITIONS`.

---

## 3. UI Components

### 3.1 Manual Entry Form

Replaces the current flat 11-field form.

- Date field at top (always visible)
- Five collapsible panel groups (Hormonal, Thyroid & Metabolism, Cardiovascular & Lipid, Growth & Nutritional, General Health & Safety)
- Each group header shows a count of how many markers have been filled in that group
- Profile-driven groups expand by default on page load; others collapsed
- Empty fields are ignored on save — no `null` rows inserted into `lab_markers`
- Save button at bottom: iterates all filled fields, upserts one row per marker to `lab_markers` and `hrt_lab_markers` localStorage

### 3.2 History Tab

Two sections, stacked vertically.

**Trend Charts (top)**

Always-visible mini charts for the 4 core profile-relevant markers (driven by `profile_focus`). A collapsed "More trends" accordion below for secondary markers (Lipids, Thyroid, Liver, IGF-1). Each chart:
- X-axis: draw dates
- Y-axis: value, with colored reference band (green = optimal, amber = normal, red = alert)
- Null draw dates skipped (no gap interpolation)

**Draw History Table (bottom)**

- One row per `drawn_at` date, newest first
- Column groups match panel categories; each group shows its 2–3 most important markers
- Cells: colored value chip (green/amber/red based on ranges) or `—` for missing
- Clicking a row calls `loadLabDateForEdit(drawn_at)`:
  1. Reads all markers for that date from in-memory cache or localStorage
  2. Populates the Manual Entry form fields
  3. Switches to Manual Entry tab
  4. A banner shows "Editing [date] — Save to update"

### 3.3 Reference Ranges Tab

Dynamic table generated from `MARKER_DEFINITIONS`, filtered by `profile_sex`. Replaces the current static male-only table.

- Same five category groups as Manual Entry
- Columns: Marker, Unit, Optimal, Normal, Monitor If
- Contextual notes for performance users on relevant markers (e.g. "On 19-nors: monitor Prolactin")

### 3.4 Upload Tab

Three sub-tabs: **PDF**, **CSV**, **Lab Code Reference**.

**PDF sub-tab**

1. Drag-and-drop or file picker (`.pdf`)
2. Client-side text extraction via `pdf.js`
3. Build reverse code lookup from `MARKER_DEFINITIONS`: `{ '070130': 'total_testosterone', '36170': 'total_testosterone', ... }`
4. Scan extracted text for known LabCorp or Quest order codes; capture adjacent numeric value
5. Fallback: fuzzy match on test name string if no code found
6. Render preview table: `Marker | Extracted Value | Confidence | Unit`
   - Code match → ✓ green
   - Name match → ~ amber (editable)
   - Unmatched → user fills manually (red row)
7. User edits any amber/red rows, clicks Confirm
8. Save all confirmed markers to `lab_markers` with `lab_source = 'labcorp_pdf'` or `'quest_pdf'`
9. Claude API Edge Function offered as fallback only if code matching yields fewer than 3 markers

**CSV sub-tab**

1. File picker (`.csv`)
2. Client-side parse via `FileReader` + `Papa.parse`
3. Map column headers to `marker_key` via name reverse index
4. Same preview → confirm → save flow as PDF
5. `lab_source = 'csv'`

**Lab Code Reference sub-tab**

Static table from `MARKER_DEFINITIONS` showing LabCorp code, Quest code, and TAT for every marker. Printable. Replaces the need for users to leave the app to find order codes.

---

## 4. Data Flow

### Save (Manual Entry)

```
form submit
  → collect filled fields → [{marker_key, value}]
  → upsert to hrt_lab_markers localStorage (merge by drawn_at + marker_key)
  → if signed in: upsert to lab_markers Supabase (onConflict: user_id,drawn_at,marker_key)
  → refresh trend charts + dashboard cards
  → show success toast
```

### Load (Signed In)

```
loadUserData()
  → SELECT * FROM lab_markers WHERE user_id = ? ORDER BY drawn_at DESC LIMIT 500
  → group by drawn_at → window._labMarkersCache
  → renderLabHistory()   ← populates table + trend charts
  → renderLabDashboardCards()  ← updates dashboard metric cards per profile
```

### Load (Not Signed In)

```
loadDemoData()
  → lsGet('hrt_lab_markers')
  → renderLabHistory()
  → renderLabDashboardCards()
```

### Edit Existing Draw

```
click history row (drawn_at)
  → loadLabDateForEdit(drawn_at)
  → read window._labMarkersCache[drawn_at] or lsGet('hrt_lab_markers').filter(drawn_at)
  → populate Manual Entry form fields
  → switchTab to Manual Entry
  → show "Editing [date]" banner
  → on save: same upsert flow as above
```

---

## 5. Data Migration

Users with existing data in the old flat `lab_results` table get a one-time migration:

```js
async function migrateLabResults(userId) {
  const { data } = await _supa.from('lab_results').select('*').eq('user_id', userId);
  if (!data?.length) return;

  // Map old column names to new marker_keys
  const columnMap = {
    total_testosterone: 'total_testosterone',
    free_testosterone:  'free_testosterone',
    estradiol:          'estradiol',
    hematocrit:         'hematocrit',
    hemoglobin:         'hemoglobin',
    psa:                'psa',
    lh:                 'lh',
    ast:                'ast',
    alt:                'alt',
    shbg:               'shbg',
  };

  const rows = [];
  for (const labRow of data) {
    for (const [col, key] of Object.entries(columnMap)) {
      if (labRow[col] != null) {
        rows.push({ user_id: userId, drawn_at: labRow.drawn_at, marker_key: key, value: labRow[col], lab_source: 'manual' });
      }
    }
  }
  await _supa.from('lab_markers').upsert(rows, { onConflict: 'user_id,drawn_at,marker_key' });
}
```

Runs automatically on first `loadUserData()` call after the update if `lab_results` rows exist and `lab_markers` has none. Old `lab_results` table kept read-only for 30 days then dropped.

---

## 6. Error Handling

| Scenario | Behavior |
|----------|----------|
| PDF text extraction fails | Show error: "Could not read this PDF. Try the CSV export from your lab portal or use Manual Entry." |
| Code matching yields < 3 markers | Offer Claude API Edge Function fallback with one-click |
| Supabase upsert fails | Save to localStorage anyway; show amber toast "Saved locally — will sync when connection restores" |
| Invalid numeric value in form | Inline validation: red border + "Must be a number" before save attempt |
| Migration fails | Log error, skip silently, allow manual re-entry — do not block app load |

---

## 7. Out of Scope (This Spec)

- Reminders / dose notifications — separate spec
- Micronutrient panel entry (Vitamins, Minerals) — can be added as a 6th panel group in a follow-up
- PDF parsing for non-Quest/LabCorp lab formats — handled by Claude API fallback
- Sharing lab results with a provider — future feature
- AI interpretation of results ("your E2 is trending up because...") — future feature

---

## 7b. Implementation Notes (Spec Self-Review Findings)

**Panel codes map to multiple markers.**
CBC (`005009`/`6399`), CMP (`322000`/`10231`), and Lipid Panel (`303756`/`14852`) are single order codes that return multiple distinct markers. The reverse code lookup for PDF parsing must map these to an *array* of marker_keys, not a single value:

```js
// Reverse lookup built at runtime from MARKER_DEFINITIONS
const CODE_TO_MARKERS = {
  '005009': ['hematocrit', 'hemoglobin', 'wbc', 'rbc', 'platelets'],
  '322000': ['ast', 'alt', 'creatinine'],
  '303756': ['ldl', 'hdl', 'triglycerides'],
  // single-marker codes map to a one-element array
  '070130': ['total_testosterone'],
  // ...
};
```

When the parser finds a panel code, it then searches the surrounding text block for each sub-marker by name to extract individual values.

**`alert_below` vs `alert_above`.**
Most markers use `alert_above` (flag if value exceeds threshold). A few use `alert_below` (flag if value drops below threshold): HDL, Vitamin D, Ferritin (low end). The range classification function must handle both:

```js
function classifyValue(value, ranges, sex) {
  const r = ranges[sex];
  if (!r || value == null) return 'muted';
  if (r.alert_above != null && value > r.alert_above) return 'red';
  if (r.alert_below != null && value < r.alert_below) return 'red';
  const [optLow, optHigh] = r.optimal;
  if ((optLow == null || value >= optLow) && (optHigh == null || value <= optHigh)) return 'green';
  return 'amber';
}
```

**`window._labMarkersCache` shape.**
Referenced in the data flow and edit path. Defined as:

```js
window._labMarkersCache = {
  '2026-06-19': [
    { marker_key: 'total_testosterone', value: 742, lab_source: 'manual' },
    { marker_key: 'estradiol',          value: 28.4, lab_source: 'manual' },
  ],
  '2026-03-15': [ ... ],
};
```

Keys are ISO date strings. Built during `loadUserData()` (Supabase) and `loadDemoData()` (localStorage). The history table and `loadLabDateForEdit()` both read from this cache — no secondary fetches.

---

## 8. Success Criteria

- User can upload a standard LabCorp or Quest PDF and have ≥ 90% of markers extracted correctly with no manual correction
- User can submit two separate panels for the same draw date without either clobbering the other
- Lab history table populates correctly for both signed-in (Supabase) and not-signed-in (localStorage) users
- Dashboard cards update to reflect the correct markers for the user's profile
- Reference ranges are profile-sex-appropriate for all markers
- Clicking a history row pre-fills the Manual Entry form with that draw's values
- All existing `lab_results` data is migrated correctly to `lab_markers` on first sign-in after update
