# Blood Labs Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the incomplete blood labs section with a full EAV-model implementation supporting 40+ markers, collapsible panel groups, PDF/CSV import via LabCorp/Quest order codes, profile-driven dashboard cards, a clickable history table with trend charts, and a dynamic reference ranges tab.

**Architecture:** A static `MARKER_DEFINITIONS` JS object (derived from the Bloodwork Reference Guide) is the single source of truth for all marker metadata. A new Supabase `lab_markers` table stores one row per `(user_id, drawn_at, marker_key)` — upsert on conflict handles same-date multi-panel submissions natively. All UI reads from `window._labMarkersCache` (keyed by date string) which is built from either Supabase or localStorage on startup.

**Tech Stack:** Vanilla JS + HTML in a single `index-v2.html` file. Supabase JS client (already loaded). Chart.js via `makeChart()` (already loaded). `pdf.js` loaded from CDN in Task 8. `Papa.parse` loaded from CDN in Task 9.

## Global Constraints

- All code lives in `index-v2.html` — no build step, no separate JS files.
- Use existing helpers: `lsGet(key, fallback)`, `makeChart(id, type, labels, datasets, opts)`, `showChart(id)`, `updateMetricCard(id, value, badge, badgeClass)`.
- localStorage keys: `hrt_lab_markers` (new EAV array), `hrt_user_profile` (new profile object). Do not rename `hrt_vitals_log`, `hrt_labs_log`, or any existing keys.
- Supabase table: `lab_markers`. Old `lab_results` table stays read-only until migration is confirmed.
- No external UI libraries. Match existing card/table/badge CSS classes.
- Every git commit message must describe the functional change, not "add code".
- Spec reference: `docs/superpowers/specs/2026-06-19-blood-labs-design.md`

---

## File Map

| Area | Action | Anchor in file |
|------|--------|---------------|
| `lab_markers` Supabase table | Create via SQL | Supabase dashboard |
| `MARKER_DEFINITIONS` constant | Add after `_COMPOUND_ABBREVS` (~line 3074) | After `const _COMPOUND_ABBREVS` block |
| `CODE_TO_MARKERS` lookup | Add after `MARKER_DEFINITIONS` | Immediately below MARKER_DEFINITIONS |
| `classifyValue(value, ranges, sex)` | Add after CODE_TO_MARKERS | Immediately below CODE_TO_MARKERS |
| `getProfile()` / `saveProfile(profile)` | Add after `lsGet` (~line 1675) | After `function lsGet` |
| Settings HTML — profile dropdowns | Modify `#page-settings` (~line 1575) | Before the Supabase card |
| Blood Labs HTML — all 4 tabs | Rewrite (~lines 908–1024) | `<!-- ── BLOOD LABS PAGE ── -->` |
| `submitLabEntry()` | Rewrite (~line 2416) | Replace existing function |
| `loadDemoData()` | Modify (~line 1760) | Replace `hrt_labs_log` call |
| `loadUserData()` | Modify (~line 1725) | Add `lab_markers` query |
| `renderLabDashboardCards(markers)` | Add new function | After `renderLabMetrics` |
| `renderLabHistory()` | Add new function | After `renderLabDashboardCards` |
| `loadLabDateForEdit(drawnAt)` | Add new function | After `renderLabHistory` |
| `renderReferenceRanges()` | Add new function | After `loadLabDateForEdit` |
| `parsePdf(file)` | Add new function | After `renderReferenceRanges` |
| `parseCsv(file)` | Add new function | After `parsePdf` |
| `showLabImportPreview(rows)` | Add new function | After `parseCsv` |
| `confirmLabImport(rows, source)` | Add new function | After `showLabImportPreview` |
| `migrateLabResults()` | Add new function | After `confirmLabImport` |
| DOMContentLoaded | Modify (~line 3737) | Add `renderReferenceRanges()` call |

---

## Task 1: Supabase `lab_markers` Table

**Files:**
- No JS changes — SQL only, run in Supabase SQL editor

**Interfaces:**
- Produces: `lab_markers` table with columns `(id, user_id, drawn_at, marker_key, value, lab_source, created_at)` and unique constraint `(user_id, drawn_at, marker_key)`

- [ ] **Step 1: Open Supabase SQL editor**

Navigate to your Supabase project → SQL Editor → New query.

- [ ] **Step 2: Run table creation SQL**

```sql
CREATE TABLE IF NOT EXISTS lab_markers (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users NOT NULL,
  drawn_at    date NOT NULL,
  marker_key  text NOT NULL,
  value       numeric NOT NULL,
  lab_source  text CHECK (lab_source IN ('manual', 'labcorp_pdf', 'quest_pdf', 'csv')),
  created_at  timestamptz DEFAULT now(),
  UNIQUE (user_id, drawn_at, marker_key)
);

CREATE INDEX IF NOT EXISTS lab_markers_user_date
  ON lab_markers (user_id, drawn_at DESC);

CREATE INDEX IF NOT EXISTS lab_markers_user_marker_date
  ON lab_markers (user_id, marker_key, drawn_at DESC);
```

Expected output: `Success. No rows returned.`

- [ ] **Step 3: Enable Row Level Security**

```sql
ALTER TABLE lab_markers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own lab markers"
  ON lab_markers
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

Expected output: `Success. No rows returned.`

- [ ] **Step 4: Verify table exists**

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'lab_markers'
ORDER BY ordinal_position;
```

Expected: 7 rows listing `id`, `user_id`, `drawn_at`, `marker_key`, `value`, `lab_source`, `created_at`.

- [ ] **Step 5: Commit note**

No file changes. Add a comment to the top of `index-v2.html` near the Supabase config section noting the new table:

```html
<!-- Supabase tables: administration_log, daily_metrics, lab_results (legacy), lab_markers -->
```

```bash
git add index-v2.html
git commit -m "docs: note lab_markers Supabase table in file header"
```

---

## Task 2: MARKER_DEFINITIONS + CODE_TO_MARKERS + classifyValue

**Files:**
- Modify: `index-v2.html` — add three constants after `const _COMPOUND_ABBREVS` block (~line 3074)

**Interfaces:**
- Produces:
  - `MARKER_DEFINITIONS` — object keyed by `marker_key`, each entry has `{ label, unit, labcorp_code, quest_code, category, sex[], ranges: { male|female: { optimal:[lo,hi], normal:[lo,hi], alert_above?, alert_below? } } }`
  - `CODE_TO_MARKERS` — `{ [labcorpOrQuestCode]: marker_key[] }`
  - `classifyValue(value, ranges, sex)` → `'green' | 'amber' | 'red' | 'muted'`

- [ ] **Step 1: Write console test before adding code**

Open `index-v2.html` in a browser. Open DevTools console. Run:

```js
// These should all throw ReferenceError — confirms nothing exists yet
try { MARKER_DEFINITIONS } catch(e) { console.log('MARKER_DEFINITIONS: not defined ✓'); }
try { classifyValue } catch(e) { console.log('classifyValue: not defined ✓'); }
```

Expected: both lines print "not defined ✓".

- [ ] **Step 2: Add MARKER_DEFINITIONS, CODE_TO_MARKERS, and classifyValue**

Find the line `const _COMPOUND_ABBREVS = {` (currently ~line 3016). Add the following block **immediately before** it:

```js
// ── Lab Marker Definitions ──
// Single source of truth: labels, units, LabCorp/Quest codes, categories, reference ranges.
const MARKER_DEFINITIONS = {
  // HORMONAL
  total_testosterone: { label:'Total Testosterone', unit:'ng/dL',  labcorp_code:'070130', quest_code:'36170',  category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[500,900],  normal:[300,1000], alert_above:1200}, female:{optimal:[30,80],   normal:[15,100],  alert_above:150}  }},
  free_testosterone:  { label:'Free Testosterone',  unit:'ng/dL',  labcorp_code:'070130', quest_code:'36170',  category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[15,25],   normal:[9,30],    alert_above:35},   female:{optimal:[1,3],    normal:[0.5,5],   alert_above:8}    }},
  estradiol:          { label:'Estradiol (E2)',      unit:'pg/mL',  labcorp_code:'140244', quest_code:'30289',  category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[20,35],   normal:[10,50],   alert_above:60},   female:{optimal:[50,200], normal:[20,400],  alert_above:500}  }},
  shbg:               { label:'SHBG',               unit:'nmol/L', labcorp_code:'082016', quest_code:'30740',  category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[15,30],   normal:[10,57],   alert_above:50},   female:{optimal:[30,90],  normal:[18,144],  alert_above:144}  }},
  dht:                { label:'DHT',                unit:'pg/mL',  labcorp_code:'504026', quest_code:'90567',  category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[300,700], normal:[112,955], alert_above:1000},  female:{optimal:[10,50],  normal:[5,80],    alert_above:100}  }},
  prolactin:          { label:'Prolactin',           unit:'ng/mL',  labcorp_code:'004465', quest_code:'746',    category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[2,10],    normal:[2,18],    alert_above:18},   female:{optimal:[2,20],   normal:[2,30],    alert_above:30}   }},
  lh:                 { label:'LH',                 unit:'mIU/mL', labcorp_code:'028480', quest_code:'7137',   category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[2,8],     normal:[1.7,8.6], alert_above:null},  female:{optimal:[2,15],   normal:[1,100],   alert_above:null} }},
  fsh:                { label:'FSH',                unit:'mIU/mL', labcorp_code:'028480', quest_code:'7137',   category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[2,8],     normal:[1.5,12.4],alert_above:null},  female:{optimal:[2,20],   normal:[1,100],   alert_above:null} }},
  progesterone:       { label:'Progesterone',        unit:'ng/mL',  labcorp_code:'004317', quest_code:'17183',  category:'hormonal', sex:['female'],        ranges:{ female:{optimal:[5,20],  normal:[0.1,25],  alert_above:null} }},
  cortisol:           { label:'Cortisol (AM)',       unit:'mcg/dL', labcorp_code:'104018', quest_code:'367',    category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[10,20],   normal:[6,23],    alert_above:23},   female:{optimal:[10,20],  normal:[6,23],    alert_above:23}   }},
  dhea_s:             { label:'DHEA-S',              unit:'mcg/dL', labcorp_code:'004020', quest_code:'402',    category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[200,400], normal:[100,600], alert_above:600},   female:{optimal:[100,300],normal:[40,430],  alert_above:430}  }},
  pregnenolone:       { label:'Pregnenolone',        unit:'ng/dL',  labcorp_code:'140707', quest_code:'31493',  category:'hormonal', sex:['male','female'], ranges:{ male:{optimal:[50,200],  normal:[10,200],  alert_above:null},  female:{optimal:[50,200], normal:[10,200],  alert_above:null} }},
  // THYROID & METABOLISM
  tsh:                { label:'TSH',                unit:'mIU/L',  labcorp_code:'000620', quest_code:'7444',   category:'thyroid',  sex:['male','female'], ranges:{ male:{optimal:[1,2.5],   normal:[0.4,4.5], alert_above:4.5},   female:{optimal:[1,2.5],  normal:[0.4,4.5], alert_above:4.5}  }},
  free_t3:            { label:'Free T3',            unit:'pg/mL',  labcorp_code:'010389', quest_code:'34429',  category:'thyroid',  sex:['male','female'], ranges:{ male:{optimal:[3,4],     normal:[2.3,4.2], alert_above:null},  female:{optimal:[3,4],    normal:[2.3,4.2], alert_above:null} }},
  free_t4:            { label:'Free T4',            unit:'ng/dL',  labcorp_code:'001974', quest_code:'866',    category:'thyroid',  sex:['male','female'], ranges:{ male:{optimal:[1,1.5],   normal:[0.8,1.8], alert_above:null},  female:{optimal:[1,1.5],  normal:[0.8,1.8], alert_above:null} }},
  reverse_t3:         { label:'Reverse T3',         unit:'ng/dL',  labcorp_code:'070104', quest_code:'90963',  category:'thyroid',  sex:['male','female'], ranges:{ male:{optimal:[9,25],    normal:[9,35],    alert_above:35},    female:{optimal:[9,25],   normal:[9,35],    alert_above:35}   }},
  hba1c:              { label:'HbA1c',              unit:'%',      labcorp_code:'001453', quest_code:'496',    category:'thyroid',  sex:['male','female'], ranges:{ male:{optimal:[4.5,5.5], normal:[4,5.7],   alert_above:6.5},   female:{optimal:[4.5,5.5],normal:[4,5.7],   alert_above:6.5}  }},
  fasting_insulin:    { label:'Fasting Insulin',    unit:'mcIU/mL',labcorp_code:'004333', quest_code:'561',    category:'thyroid',  sex:['male','female'], ranges:{ male:{optimal:[3,7],     normal:[2,20],    alert_above:20},    female:{optimal:[3,7],    normal:[2,20],    alert_above:20}   }},
  cystatin_c:         { label:'Cystatin C / eGFR',  unit:'mg/L',   labcorp_code:'121265', quest_code:'94588',  category:'thyroid',  sex:['male','female'], ranges:{ male:{optimal:[0.5,1.0], normal:[0.5,1.2], alert_above:1.2},   female:{optimal:[0.5,1.0],normal:[0.5,1.2], alert_above:1.2}  }},
  // CARDIOVASCULAR & LIPID
  apob:               { label:'ApoB',               unit:'mg/dL',  labcorp_code:'167015', quest_code:'5224',   category:'cardiovascular', sex:['male','female'], ranges:{ male:{optimal:[null,80],  normal:[null,100], alert_above:100},  female:{optimal:[null,80], normal:[null,100], alert_above:100} }},
  hs_crp:             { label:'hs-CRP',             unit:'mg/L',   labcorp_code:'120766', quest_code:'10124',  category:'cardiovascular', sex:['male','female'], ranges:{ male:{optimal:[null,1],   normal:[null,3],   alert_above:3},    female:{optimal:[null,1],  normal:[null,3],   alert_above:3}   }},
  ldl:                { label:'LDL',                unit:'mg/dL',  labcorp_code:'303756', quest_code:'14852',  category:'cardiovascular', sex:['male','female'], ranges:{ male:{optimal:[null,100], normal:[null,130], alert_above:160},  female:{optimal:[null,100],normal:[null,130], alert_above:160} }},
  hdl:                { label:'HDL',                unit:'mg/dL',  labcorp_code:'303756', quest_code:'14852',  category:'cardiovascular', sex:['male','female'], ranges:{ male:{optimal:[50,null],  normal:[40,null],  alert_below:40},   female:{optimal:[60,null], normal:[50,null],  alert_below:50}  }},
  triglycerides:      { label:'Triglycerides',      unit:'mg/dL',  labcorp_code:'303756', quest_code:'14852',  category:'cardiovascular', sex:['male','female'], ranges:{ male:{optimal:[null,100], normal:[null,150], alert_above:200},  female:{optimal:[null,100],normal:[null,150], alert_above:200} }},
  ggt:                { label:'GGT',                unit:'U/L',    labcorp_code:'001958', quest_code:'482',    category:'cardiovascular', sex:['male','female'], ranges:{ male:{optimal:[null,30],  normal:[null,55],  alert_above:55},   female:{optimal:[null,20], normal:[null,40],  alert_above:40}  }},
  homocysteine:       { label:'Homocysteine',       unit:'mcmol/L',labcorp_code:'706994', quest_code:'31789',  category:'cardiovascular', sex:['male','female'], ranges:{ male:{optimal:[null,10],  normal:[null,15],  alert_above:15},   female:{optimal:[null,10], normal:[null,15],  alert_above:15}  }},
  lipoprotein_a:      { label:'Lipoprotein(a)',     unit:'nmol/L', labcorp_code:'120188', quest_code:'34604',  category:'cardiovascular', sex:['male','female'], ranges:{ male:{optimal:[null,75],  normal:[null,125], alert_above:125},  female:{optimal:[null,75], normal:[null,125], alert_above:125} }},
  // GROWTH & NUTRITIONAL
  igf1:               { label:'IGF-1',              unit:'ng/mL',  labcorp_code:'010540', quest_code:'16293',  category:'growth',   sex:['male','female'], ranges:{ male:{optimal:[150,300], normal:[88,456],  alert_above:456},   female:{optimal:[100,250],normal:[55,350],  alert_above:350}  }},
  growth_hormone:     { label:'Growth Hormone',     unit:'ng/mL',  labcorp_code:'004275', quest_code:'521',    category:'growth',   sex:['male','female'], ranges:{ male:{optimal:[null,3],  normal:[null,7.5],alert_above:null},  female:{optimal:[null,5], normal:[null,10], alert_above:null} }},
  vitamin_d:          { label:'Vitamin D',          unit:'ng/mL',  labcorp_code:'081950', quest_code:'17306',  category:'growth',   sex:['male','female'], ranges:{ male:{optimal:[40,70],   normal:[30,100],  alert_below:20},    female:{optimal:[40,70],  normal:[30,100],  alert_below:20}   }},
  ferritin:           { label:'Ferritin',           unit:'ng/mL',  labcorp_code:'004598', quest_code:'5616',   category:'growth',   sex:['male','female'], ranges:{ male:{optimal:[50,200],  normal:[12,300],  alert_above:300},   female:{optimal:[20,100], normal:[10,150],  alert_above:150}  }},
  // GENERAL HEALTH & SAFETY (CBC + CMP components + others)
  hematocrit:         { label:'Hematocrit',         unit:'%',      labcorp_code:'005009', quest_code:'6399',   category:'general',  sex:['male','female'], ranges:{ male:{optimal:[42,50],   normal:[38,54],   alert_above:52},    female:{optimal:[36,44],  normal:[34,47],   alert_above:48}   }},
  hemoglobin:         { label:'Hemoglobin',         unit:'g/dL',   labcorp_code:'005009', quest_code:'6399',   category:'general',  sex:['male','female'], ranges:{ male:{optimal:[13.5,17], normal:[12,18],   alert_above:18.5},  female:{optimal:[12,15.5],normal:[11,16],   alert_above:17}   }},
  wbc:                { label:'WBC',                unit:'K/uL',   labcorp_code:'005009', quest_code:'6399',   category:'general',  sex:['male','female'], ranges:{ male:{optimal:[4,10],    normal:[3.5,11],  alert_above:11},    female:{optimal:[4,10],   normal:[3.5,11],  alert_above:11}   }},
  rbc:                { label:'RBC',                unit:'M/uL',   labcorp_code:'005009', quest_code:'6399',   category:'general',  sex:['male','female'], ranges:{ male:{optimal:[4.5,5.5], normal:[4.2,6],   alert_above:6},     female:{optimal:[3.8,5],  normal:[3.5,5.5], alert_above:5.5}  }},
  platelets:          { label:'Platelets',          unit:'K/uL',   labcorp_code:'005009', quest_code:'6399',   category:'general',  sex:['male','female'], ranges:{ male:{optimal:[150,350], normal:[130,400], alert_below:100},   female:{optimal:[150,350],normal:[130,400], alert_below:100}  }},
  psa:                { label:'PSA',                unit:'ng/mL',  labcorp_code:'010322', quest_code:'5363',   category:'general',  sex:['male'],          ranges:{ male:{optimal:[null,1.5],normal:[null,4],  alert_above:4}     }},
  ast:                { label:'AST',                unit:'U/L',    labcorp_code:'322000', quest_code:'10231',  category:'general',  sex:['male','female'], ranges:{ male:{optimal:[null,35], normal:[null,50], alert_above:80},    female:{optimal:[null,35],normal:[null,50],  alert_above:80}   }},
  alt:                { label:'ALT',                unit:'U/L',    labcorp_code:'322000', quest_code:'10231',  category:'general',  sex:['male','female'], ranges:{ male:{optimal:[null,35], normal:[null,56], alert_above:80},    female:{optimal:[null,35],normal:[null,56],  alert_above:80}   }},
  creatinine:         { label:'Creatinine',         unit:'mg/dL',  labcorp_code:'322000', quest_code:'10231',  category:'general',  sex:['male','female'], ranges:{ male:{optimal:[0.7,1.2], normal:[0.6,1.3], alert_above:1.3},   female:{optimal:[0.5,1.0],normal:[0.4,1.1], alert_above:1.1}  }},
  creatine_kinase:    { label:'Creatine Kinase (CK)',unit:'U/L',   labcorp_code:'001362', quest_code:'374',    category:'general',  sex:['male','female'], ranges:{ male:{optimal:[null,200], normal:[null,400],alert_above:1000},  female:{optimal:[null,150],normal:[null,300],alert_above:800}  }},
  uric_acid:          { label:'Uric Acid',          unit:'mg/dL',  labcorp_code:'001057', quest_code:'905',    category:'general',  sex:['male','female'], ranges:{ male:{optimal:[3.5,6],   normal:[2.5,7.2], alert_above:7.2},   female:{optimal:[2.5,5.5],normal:[2,6],     alert_above:6}    }},
};

// Reverse lookup: lab order code → array of marker_keys it can produce
// Panel codes (CBC, CMP, Lipid) return multiple markers — parser checks sub-marker names within the panel block.
const CODE_TO_MARKERS = (() => {
  const map = {};
  for (const [key, def] of Object.entries(MARKER_DEFINITIONS)) {
    for (const code of [def.labcorp_code, def.quest_code].filter(Boolean)) {
      if (!map[code]) map[code] = [];
      if (!map[code].includes(key)) map[code].push(key);
    }
  }
  return map;
})();

// Classify a numeric value against a marker's ranges for a given sex.
// Returns 'green' (optimal), 'amber' (normal but not optimal), 'red' (alert), or 'muted' (no data).
function classifyValue(value, ranges, sex) {
  if (value == null || value === '') return 'muted';
  const r = ranges[sex] || ranges['male'] || ranges['female'];
  if (!r) return 'muted';
  const v = parseFloat(value);
  if (r.alert_above != null && v > r.alert_above) return 'red';
  if (r.alert_below != null && v < r.alert_below) return 'red';
  const [optLow, optHigh] = r.optimal || [null, null];
  const inOptimal = (optLow == null || v >= optLow) && (optHigh == null || v <= optHigh);
  if (inOptimal) return 'green';
  const [normLow, normHigh] = r.normal || [null, null];
  const inNormal = (normLow == null || v >= normLow) && (normHigh == null || v <= normHigh);
  if (inNormal) return 'amber';
  return 'red';
}
```

- [ ] **Step 3: Reload browser, run console verification**

```js
// All should pass
console.assert(typeof MARKER_DEFINITIONS === 'object', 'MARKER_DEFINITIONS missing');
console.assert(Object.keys(MARKER_DEFINITIONS).length >= 40, 'Too few markers');
console.assert(classifyValue(800,  MARKER_DEFINITIONS.total_testosterone.ranges, 'male') === 'green', 'T 800 should be green');
console.assert(classifyValue(1300, MARKER_DEFINITIONS.total_testosterone.ranges, 'male') === 'red',   'T 1300 should be red');
console.assert(classifyValue(250,  MARKER_DEFINITIONS.total_testosterone.ranges, 'male') === 'red',   'T 250 should be red');
console.assert(classifyValue(35,   MARKER_DEFINITIONS.hdl.ranges, 'male') === 'red',   'HDL 35 should be red (alert_below:40)');
console.assert(classifyValue(55,   MARKER_DEFINITIONS.hdl.ranges, 'male') === 'green', 'HDL 55 should be green');
console.assert(CODE_TO_MARKERS['005009'].includes('hematocrit'), 'CBC code should map to hematocrit');
console.assert(CODE_TO_MARKERS['005009'].includes('hemoglobin'), 'CBC code should map to hemoglobin');
console.assert(CODE_TO_MARKERS['303756'].includes('ldl'),        'Lipid code should map to LDL');
console.assert(CODE_TO_MARKERS['303756'].includes('hdl'),        'Lipid code should map to HDL');
console.log('All Task 2 assertions passed ✓');
```

Expected: `All Task 2 assertions passed ✓`

- [ ] **Step 4: Commit**

```bash
git add index-v2.html
git commit -m "feat: add MARKER_DEFINITIONS, CODE_TO_MARKERS, and classifyValue"
```

---

## Task 3: Profile System

**Files:**
- Modify: `index-v2.html` — add profile functions near `lsGet`, add profile HTML to Settings page

**Interfaces:**
- Produces:
  - `getProfile()` → `{ sex: 'male'|'female', focus: 'trt'|'female_hrt'|'aas'|'gh_peptides'|'insulin'|'sarms' }`
  - `saveProfile(profile)` — persists to `hrt_user_profile` localStorage

- [ ] **Step 1: Add profile helper functions**

Find `function lsGet(key, fallback) {` (~line 1673). Add immediately after the closing `}` of `lsGet`:

```js
function getProfile() {
  return lsGet('hrt_user_profile', { sex: 'male', focus: 'trt' });
}
function saveProfile(profile) {
  localStorage.setItem('hrt_user_profile', JSON.stringify(profile));
}
```

- [ ] **Step 2: Add profile settings UI to the Settings page**

Find the Settings card that contains the `<div class="card-title">Mode</div>` block. Add a new card **above** the Mode card:

```html
        <div class="card" style="max-width:500px;margin-bottom:14px;">
          <div class="card-title">Profile</div>
          <div class="form-row">
            <div class="form-group">
              <label class="form-label">Biological Sex</label>
              <select class="form-input" id="profile-sex" onchange="saveProfile({...getProfile(), sex: this.value}); renderReferenceRanges(); renderLabDashboardCards(window._labMarkersCache || {});">
                <option value="male">Male</option>
                <option value="female">Female</option>
              </select>
            </div>
            <div class="form-group">
              <label class="form-label">Primary Focus</label>
              <select class="form-input" id="profile-focus" onchange="saveProfile({...getProfile(), focus: this.value}); renderLabDashboardCards(window._labMarkersCache || {});">
                <option value="trt">TRT / HRT</option>
                <option value="female_hrt">Female HRT</option>
                <option value="aas">AAS / Performance</option>
                <option value="gh_peptides">GH / Peptides</option>
                <option value="insulin">Insulin</option>
                <option value="sarms">SARMs</option>
              </select>
            </div>
          </div>
        </div>
```

- [ ] **Step 3: Wire profile selects to saved values on page load**

Find `window.addEventListener('DOMContentLoaded', () => {` (~line 3737). Add inside the callback:

```js
  // Restore profile select values
  const _p = getProfile();
  const _pSex = document.getElementById('profile-sex');
  const _pFocus = document.getElementById('profile-focus');
  if (_pSex) _pSex.value = _p.sex;
  if (_pFocus) _pFocus.value = _p.focus;
```

- [ ] **Step 4: Verify in browser**

1. Go to Settings page.
2. Change Biological Sex to "Female" — verify select updates.
3. Run in console: `getProfile()` — expected: `{ sex: 'female', focus: 'trt' }`.
4. Reload page — verify Settings selects restore to the saved values.

- [ ] **Step 5: Commit**

```bash
git add index-v2.html
git commit -m "feat: add profile system (sex + focus) to Settings"
```

---

## Task 4: Manual Entry Form Rewrite + submitLabEntry() EAV Rewrite

**Files:**
- Modify: `index-v2.html` — replace `labs-manual` tab HTML, rewrite `submitLabEntry()`

**Interfaces:**
- Consumes: `MARKER_DEFINITIONS`, `getProfile()`, `lsGet()`, `_supa`, `_supaUser`
- Produces:
  - `hrt_lab_markers` localStorage array updated on every save
  - `lab_markers` Supabase rows upserted when signed in
  - `window._labMarkersCache` updated in-memory after save

- [ ] **Step 1: Replace the labs-manual tab HTML**

Find `<div class="tab-panel" id="labs-manual">` (~line 942) through its closing `</div>` before the next `<div class="tab-panel"`. Replace the entire block:

```html
      <div class="tab-panel" id="labs-manual">
        <div class="card" style="max-width:620px;">
          <div class="card-title">Enter Lab Results Manually</div>
          <div id="lab-edit-banner" style="display:none;background:var(--amber);color:#000;padding:8px 12px;border-radius:6px;font-size:12px;font-weight:500;margin-bottom:12px;"></div>
          <div class="form-group">
            <label class="form-label">Lab Date</label>
            <input type="date" class="form-input" id="lab-date">
          </div>

          <!-- Hormonal Health -->
          <div class="lab-group">
            <div class="lab-group-header" onclick="toggleLabGroup('grp-hormonal')">
              <span>Hormonal Health</span>
              <span id="grp-hormonal-count" style="font-size:11px;color:var(--text-muted);"></span>
              <i class="ti ti-chevron-down" id="grp-hormonal-icon" style="margin-left:auto;"></i>
            </div>
            <div id="grp-hormonal" class="lab-group-body">
              <div class="form-row">
                <div class="form-group"><label class="form-label">Total Testosterone (ng/dL)</label><input type="number" class="form-input lab-field" data-key="total_testosterone" placeholder="742" step="0.1"></div>
                <div class="form-group"><label class="form-label">Free Testosterone (ng/dL)</label><input type="number" class="form-input lab-field" data-key="free_testosterone" placeholder="22.4" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Estradiol / E2 (pg/mL)</label><input type="number" class="form-input lab-field" data-key="estradiol" placeholder="28" step="0.1"></div>
                <div class="form-group"><label class="form-label">SHBG (nmol/L)</label><input type="number" class="form-input lab-field" data-key="shbg" placeholder="18" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">DHT (pg/mL)</label><input type="number" class="form-input lab-field" data-key="dht" placeholder="450" step="0.1"></div>
                <div class="form-group"><label class="form-label">Prolactin (ng/mL)</label><input type="number" class="form-input lab-field" data-key="prolactin" placeholder="8" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">LH (mIU/mL)</label><input type="number" class="form-input lab-field" data-key="lh" placeholder="0.2" step="0.1"></div>
                <div class="form-group"><label class="form-label">FSH (mIU/mL)</label><input type="number" class="form-input lab-field" data-key="fsh" placeholder="0.3" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Cortisol AM (mcg/dL)</label><input type="number" class="form-input lab-field" data-key="cortisol" placeholder="14" step="0.1"></div>
                <div class="form-group"><label class="form-label">DHEA-S (mcg/dL)</label><input type="number" class="form-input lab-field" data-key="dhea_s" placeholder="280" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Progesterone (ng/mL)</label><input type="number" class="form-input lab-field" data-key="progesterone" placeholder="1.2" step="0.01"></div>
                <div class="form-group"><label class="form-label">Pregnenolone (ng/dL)</label><input type="number" class="form-input lab-field" data-key="pregnenolone" placeholder="80" step="0.1"></div>
              </div>
            </div>
          </div>

          <!-- Thyroid & Metabolism -->
          <div class="lab-group">
            <div class="lab-group-header" onclick="toggleLabGroup('grp-thyroid')">
              <span>Thyroid &amp; Metabolism</span>
              <span id="grp-thyroid-count" style="font-size:11px;color:var(--text-muted);"></span>
              <i class="ti ti-chevron-down" id="grp-thyroid-icon" style="margin-left:auto;"></i>
            </div>
            <div id="grp-thyroid" class="lab-group-body" style="display:none;">
              <div class="form-row">
                <div class="form-group"><label class="form-label">TSH (mIU/L)</label><input type="number" class="form-input lab-field" data-key="tsh" placeholder="1.8" step="0.01"></div>
                <div class="form-group"><label class="form-label">Free T3 (pg/mL)</label><input type="number" class="form-input lab-field" data-key="free_t3" placeholder="3.2" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Free T4 (ng/dL)</label><input type="number" class="form-input lab-field" data-key="free_t4" placeholder="1.1" step="0.01"></div>
                <div class="form-group"><label class="form-label">Reverse T3 (ng/dL)</label><input type="number" class="form-input lab-field" data-key="reverse_t3" placeholder="18" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">HbA1c (%)</label><input type="number" class="form-input lab-field" data-key="hba1c" placeholder="5.4" step="0.1"></div>
                <div class="form-group"><label class="form-label">Fasting Insulin (mcIU/mL)</label><input type="number" class="form-input lab-field" data-key="fasting_insulin" placeholder="5" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Cystatin C (mg/L)</label><input type="number" class="form-input lab-field" data-key="cystatin_c" placeholder="0.8" step="0.01"></div>
                <div class="form-group"></div>
              </div>
            </div>
          </div>

          <!-- Cardiovascular & Lipid -->
          <div class="lab-group">
            <div class="lab-group-header" onclick="toggleLabGroup('grp-cardiovascular')">
              <span>Cardiovascular &amp; Lipid</span>
              <span id="grp-cardiovascular-count" style="font-size:11px;color:var(--text-muted);"></span>
              <i class="ti ti-chevron-down" id="grp-cardiovascular-icon" style="margin-left:auto;"></i>
            </div>
            <div id="grp-cardiovascular" class="lab-group-body" style="display:none;">
              <div class="form-row">
                <div class="form-group"><label class="form-label">LDL (mg/dL)</label><input type="number" class="form-input lab-field" data-key="ldl" placeholder="95" step="0.1"></div>
                <div class="form-group"><label class="form-label">HDL (mg/dL)</label><input type="number" class="form-input lab-field" data-key="hdl" placeholder="55" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Triglycerides (mg/dL)</label><input type="number" class="form-input lab-field" data-key="triglycerides" placeholder="90" step="0.1"></div>
                <div class="form-group"><label class="form-label">ApoB (mg/dL)</label><input type="number" class="form-input lab-field" data-key="apob" placeholder="75" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">hs-CRP (mg/L)</label><input type="number" class="form-input lab-field" data-key="hs_crp" placeholder="0.8" step="0.01"></div>
                <div class="form-group"><label class="form-label">GGT (U/L)</label><input type="number" class="form-input lab-field" data-key="ggt" placeholder="22" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Homocysteine (mcmol/L)</label><input type="number" class="form-input lab-field" data-key="homocysteine" placeholder="8" step="0.1"></div>
                <div class="form-group"><label class="form-label">Lipoprotein(a) (nmol/L)</label><input type="number" class="form-input lab-field" data-key="lipoprotein_a" placeholder="40" step="0.1"></div>
              </div>
            </div>
          </div>

          <!-- Growth & Nutritional -->
          <div class="lab-group">
            <div class="lab-group-header" onclick="toggleLabGroup('grp-growth')">
              <span>Growth &amp; Nutritional</span>
              <span id="grp-growth-count" style="font-size:11px;color:var(--text-muted);"></span>
              <i class="ti ti-chevron-down" id="grp-growth-icon" style="margin-left:auto;"></i>
            </div>
            <div id="grp-growth" class="lab-group-body" style="display:none;">
              <div class="form-row">
                <div class="form-group"><label class="form-label">IGF-1 (ng/mL)</label><input type="number" class="form-input lab-field" data-key="igf1" placeholder="220" step="0.1"></div>
                <div class="form-group"><label class="form-label">Growth Hormone (ng/mL)</label><input type="number" class="form-input lab-field" data-key="growth_hormone" placeholder="1.2" step="0.01"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Vitamin D (ng/mL)</label><input type="number" class="form-input lab-field" data-key="vitamin_d" placeholder="52" step="0.1"></div>
                <div class="form-group"><label class="form-label">Ferritin (ng/mL)</label><input type="number" class="form-input lab-field" data-key="ferritin" placeholder="110" step="0.1"></div>
              </div>
            </div>
          </div>

          <!-- General Health & Safety -->
          <div class="lab-group">
            <div class="lab-group-header" onclick="toggleLabGroup('grp-general')">
              <span>General Health &amp; Safety</span>
              <span id="grp-general-count" style="font-size:11px;color:var(--text-muted);"></span>
              <i class="ti ti-chevron-down" id="grp-general-icon" style="margin-left:auto;"></i>
            </div>
            <div id="grp-general" class="lab-group-body" style="display:none;">
              <div class="form-row">
                <div class="form-group"><label class="form-label">Hematocrit (%)</label><input type="number" class="form-input lab-field" data-key="hematocrit" placeholder="48.2" step="0.1"></div>
                <div class="form-group"><label class="form-label">Hemoglobin (g/dL)</label><input type="number" class="form-input lab-field" data-key="hemoglobin" placeholder="16.2" step="0.1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">WBC (K/uL)</label><input type="number" class="form-input lab-field" data-key="wbc" placeholder="6.2" step="0.1"></div>
                <div class="form-group"><label class="form-label">RBC (M/uL)</label><input type="number" class="form-input lab-field" data-key="rbc" placeholder="5.1" step="0.01"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Platelets (K/uL)</label><input type="number" class="form-input lab-field" data-key="platelets" placeholder="220" step="1"></div>
                <div class="form-group"><label class="form-label">PSA (ng/mL)</label><input type="number" class="form-input lab-field" data-key="psa" placeholder="0.8" step="0.01"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">AST (U/L)</label><input type="number" class="form-input lab-field" data-key="ast" placeholder="32" step="1"></div>
                <div class="form-group"><label class="form-label">ALT (U/L)</label><input type="number" class="form-input lab-field" data-key="alt" placeholder="28" step="1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Creatinine (mg/dL)</label><input type="number" class="form-input lab-field" data-key="creatinine" placeholder="0.95" step="0.01"></div>
                <div class="form-group"><label class="form-label">Creatine Kinase (U/L)</label><input type="number" class="form-input lab-field" data-key="creatine_kinase" placeholder="180" step="1"></div>
              </div>
              <div class="form-row">
                <div class="form-group"><label class="form-label">Uric Acid (mg/dL)</label><input type="number" class="form-input lab-field" data-key="uric_acid" placeholder="5.2" step="0.1"></div>
                <div class="form-group"></div>
              </div>
            </div>
          </div>

          <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:14px;">
            <button class="btn-secondary" onclick="clearLabForm()">Clear</button>
            <button class="btn-primary" onclick="submitLabEntry()">Save Labs</button>
          </div>
          <div id="lab-status" style="display:none;margin-top:8px;font-size:12px;text-align:right;"></div>
        </div>
      </div>
```

- [ ] **Step 2: Add CSS for lab group collapsibles**

Find the `<style>` block in the `<head>`. Add before `</style>`:

```css
.lab-group { border: 1px solid var(--border); border-radius:8px; margin-bottom:8px; overflow:hidden; }
.lab-group-header { display:flex; align-items:center; gap:8px; padding:10px 14px; cursor:pointer; font-size:13px; font-weight:500; background:var(--card-bg); user-select:none; }
.lab-group-header:hover { background:var(--hover); }
.lab-group-body { padding:14px; border-top:1px solid var(--border); }
```

- [ ] **Step 3: Add toggleLabGroup + clearLabForm helper functions**

Add after the `saveProfile` function (Task 3):

```js
function toggleLabGroup(id) {
  const body = document.getElementById(id);
  const icon = document.getElementById(id + '-icon');
  if (!body) return;
  const isOpen = body.style.display !== 'none';
  body.style.display = isOpen ? 'none' : 'block';
  if (icon) icon.style.transform = isOpen ? '' : 'rotate(180deg)';
}

function clearLabForm() {
  document.querySelectorAll('.lab-field').forEach(el => { el.value = ''; });
  document.querySelectorAll('[id$="-count"]').forEach(el => { el.textContent = ''; });
  const banner = document.getElementById('lab-edit-banner');
  if (banner) banner.style.display = 'none';
}

// Update the filled-field count chip on each group header
function updateLabGroupCounts() {
  ['hormonal','thyroid','cardiovascular','growth','general'].forEach(grp => {
    const body = document.getElementById('grp-' + grp);
    if (!body) return;
    const filled = body.querySelectorAll('.lab-field').length
      ? [...body.querySelectorAll('.lab-field')].filter(el => el.value.trim() !== '').length
      : 0;
    const el = document.getElementById('grp-' + grp + '-count');
    if (el) el.textContent = filled > 0 ? `${filled} filled` : '';
  });
}
// Update counts whenever any lab field changes
document.addEventListener('input', e => { if (e.target.classList.contains('lab-field')) updateLabGroupCounts(); });
```

- [ ] **Step 4: Rewrite submitLabEntry()**

Find `async function submitLabEntry() {` (~line 2416). Replace the entire function (from `async function submitLabEntry()` through its closing `}`) with:

```js
async function submitLabEntry() {
  const drawnAt = document.getElementById('lab-date').value;
  if (!drawnAt) {
    const s = document.getElementById('lab-status');
    s.textContent = 'Please select a lab date.'; s.style.color = 'var(--red)'; s.style.display = 'block';
    return;
  }

  // Collect filled fields
  const submitted = [];
  document.querySelectorAll('.lab-field').forEach(el => {
    const v = el.value.trim();
    if (v !== '') submitted.push({ marker_key: el.dataset.key, value: parseFloat(v) });
  });
  if (!submitted.length) {
    const s = document.getElementById('lab-status');
    s.textContent = 'No values entered.'; s.style.color = 'var(--amber)'; s.style.display = 'block';
    return;
  }

  // Persist to localStorage (always)
  const stored = lsGet('hrt_lab_markers', []);
  submitted.forEach(({ marker_key, value }) => {
    const idx = stored.findIndex(r => r.drawn_at === drawnAt && r.marker_key === marker_key);
    const row = { drawn_at: drawnAt, marker_key, value, lab_source: 'manual' };
    if (idx >= 0) stored[idx] = row; else stored.push(row);
  });
  stored.sort((a, b) => b.drawn_at.localeCompare(a.drawn_at));
  localStorage.setItem('hrt_lab_markers', JSON.stringify(stored));

  // Update in-memory cache
  if (!window._labMarkersCache) window._labMarkersCache = {};
  if (!window._labMarkersCache[drawnAt]) window._labMarkersCache[drawnAt] = [];
  submitted.forEach(({ marker_key, value }) => {
    const cache = window._labMarkersCache[drawnAt];
    const idx = cache.findIndex(r => r.marker_key === marker_key);
    const row = { marker_key, value, lab_source: 'manual' };
    if (idx >= 0) cache[idx] = row; else cache.push(row);
  });

  // Persist to Supabase (if signed in)
  if (_supa && _supaUser) {
    const rows = submitted.map(({ marker_key, value }) => ({
      user_id: _supaUser.id, drawn_at: drawnAt, marker_key, value, lab_source: 'manual'
    }));
    const { error } = await _supa.from('lab_markers').upsert(rows, { onConflict: 'user_id,drawn_at,marker_key' });
    if (error) console.error('[submitLabEntry] Supabase upsert failed:', error);
  }

  // Refresh dashboard + history
  renderLabDashboardCards(window._labMarkersCache);
  renderLabHistory();

  // Clear form + show success
  clearLabForm();
  document.getElementById('lab-date').value = new Date().toISOString().split('T')[0];
  const s = document.getElementById('lab-status');
  s.textContent = '✓ Labs saved.'; s.style.color = 'var(--green)'; s.style.display = 'block';
  setTimeout(() => { s.style.display = 'none'; }, 3000);
}
```

- [ ] **Step 5: Verify in browser**

1. Go to Blood Labs → Manual Entry tab.
2. Confirm five collapsible panel groups render. Open each group — fields should show.
3. Enter Total Testosterone = 742 and Estradiol = 28, set date to today, click Save Labs.
4. In console: `lsGet('hrt_lab_markers', [])` — expected: array with two entries for today.
5. Reload page — repeat console check — entries should persist.

- [ ] **Step 6: Commit**

```bash
git add index-v2.html
git commit -m "feat: rewrite manual lab entry form with collapsible panel groups and EAV persistence"
```

---

## Task 5: Profile-Driven Dashboard Lab Cards

**Files:**
- Modify: `index-v2.html` — add `renderLabDashboardCards()`, update `loadDemoData()` and `loadUserData()` call sites

**Interfaces:**
- Consumes: `window._labMarkersCache` `{ [drawn_at]: [{marker_key, value, lab_source}] }`, `getProfile()`, `MARKER_DEFINITIONS`, `classifyValue()`, `updateMetricCard()`
- Produces: dashboard metric cards updated for the 3 profile-relevant lab markers

- [ ] **Step 1: Add renderLabDashboardCards function**

Find `function renderLabMetrics(data) {` (~line 1968). Add the following **before** `renderLabMetrics`:

```js
// Profile-to-card mapping: which 3 marker_keys to show on the dashboard per focus type.
const PROFILE_DASHBOARD_CARDS = {
  trt:        ['total_testosterone', 'estradiol', 'hematocrit'],
  female_hrt: ['estradiol', 'progesterone', 'fsh'],
  aas:        ['total_testosterone', 'hematocrit', 'alt'],
  gh_peptides:['igf1', 'total_testosterone', 'estradiol'],
  insulin:    ['fasting_insulin', 'hba1c', 'total_testosterone'],
  sarms:      ['total_testosterone', 'lh', 'alt'],
};

// Dashboard card IDs that show lab data (3 slots: m-total-t, m-e2, m-hct)
const LAB_CARD_IDS = ['m-total-t', 'm-e2', 'm-hct'];

function renderLabDashboardCards(cache) {
  const profile = getProfile();
  const keys = PROFILE_DASHBOARD_CARDS[profile.focus] || PROFILE_DASHBOARD_CARDS.trt;

  // Find the most recent value for each key across all draw dates
  const allDates = Object.keys(cache || {}).sort((a, b) => b.localeCompare(a));

  keys.forEach((marker_key, i) => {
    const cardId = LAB_CARD_IDS[i];
    if (!cardId) return;
    const def = MARKER_DEFINITIONS[marker_key];
    if (!def) return;

    let latestValue = null;
    for (const date of allDates) {
      const row = (cache[date] || []).find(r => r.marker_key === marker_key);
      if (row != null) { latestValue = row.value; break; }
    }

    if (latestValue == null) {
      updateMetricCard(cardId, '—', 'No data', 'badge-muted');
      return;
    }

    const cls = classifyValue(latestValue, def.ranges, profile.sex);
    const badgeMap = { green: 'badge-green', amber: 'badge-amber', red: 'badge-red', muted: 'badge-muted' };
    const labelMap = { green: 'Optimal', amber: 'Monitor', red: 'Alert', muted: 'No data' };

    // Format value
    const display = Number.isInteger(latestValue) ? latestValue : parseFloat(latestValue).toFixed(1);

    // Update card label to match current profile marker
    const labelEl = document.querySelector(`#${cardId}`)?.closest('.metric-card')?.querySelector('.metric-label');
    if (labelEl) labelEl.textContent = def.label;

    updateMetricCard(cardId, display, labelMap[cls], badgeMap[cls]);

    // HCT-specific alert banner
    if (marker_key === 'hematocrit') {
      if (cls === 'red' || (cls === 'amber' && parseFloat(latestValue) > 52)) {
        showHctAlert(parseFloat(latestValue));
      } else {
        const el = document.getElementById('alert-hct');
        if (el) el.style.display = 'none';
      }
    }
  });
}
```

- [ ] **Step 2: Update loadDemoData() to use the new function**

Find `loadDemoData()`. Replace:
```js
  // Restore lab metric cards from localStorage so they survive page reloads without Supabase
  const savedLabs = lsGet('hrt_labs_log', []);
  if (savedLabs.length) renderLabMetrics(savedLabs);
```
With:
```js
  // Build _labMarkersCache from localStorage and refresh dashboard lab cards
  const storedMarkers = lsGet('hrt_lab_markers', []);
  window._labMarkersCache = {};
  storedMarkers.forEach(r => {
    if (!window._labMarkersCache[r.drawn_at]) window._labMarkersCache[r.drawn_at] = [];
    window._labMarkersCache[r.drawn_at].push(r);
  });
  renderLabDashboardCards(window._labMarkersCache);
```

- [ ] **Step 3: Verify in browser**

1. Go to Settings → set Focus to "AAS / Performance".
2. Go to Dashboard — the three lab metric cards should show labels: Total Testosterone, Hematocrit, ALT.
3. Change Focus to "GH / Peptides" — cards should relabel to IGF-1, Total Testosterone, Estradiol.
4. Enter a Total Testosterone value via Manual Entry (e.g. 742) — Dashboard should update immediately after save.

- [ ] **Step 4: Commit**

```bash
git add index-v2.html
git commit -m "feat: profile-driven dashboard lab cards via renderLabDashboardCards"
```

---

## Task 6: Lab History Table + Trend Charts + Click-to-Edit

**Files:**
- Modify: `index-v2.html` — rewrite `labs-history` tab HTML, add `renderLabHistory()` and `loadLabDateForEdit()`

**Interfaces:**
- Consumes: `window._labMarkersCache`, `getProfile()`, `MARKER_DEFINITIONS`, `classifyValue()`, `makeChart()`, `switchTab()`
- Produces: populated history table, trend charts for core markers, click-to-edit wiring

- [ ] **Step 1: Replace labs-history tab HTML**

Find `<div class="tab-panel active" id="labs-history">` through its closing `</div>` before `<div class="tab-panel" id="labs-upload">`. Replace:

```html
      <div class="tab-panel active" id="labs-history">
        <!-- Trend Charts -->
        <div class="card" style="margin-bottom:14px;">
          <div class="card-title">Trends</div>
          <div id="lab-trend-charts" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px;">
            <div style="color:var(--text-muted);font-size:12px;padding:20px;text-align:center;grid-column:1/-1;">No lab history yet. Enter results in Manual Entry to see trends.</div>
          </div>
        </div>
        <!-- History Table -->
        <div class="card">
          <div class="card-title">Draw History <span style="font-size:11px;color:var(--text-muted);font-weight:400;">— click a row to edit</span></div>
          <div id="labs-table-wrap" style="overflow-x:auto;">
            <div style="color:var(--text-muted);font-size:13px;text-align:center;padding:30px;">No lab results yet.</div>
          </div>
        </div>
      </div>
```

- [ ] **Step 2: Add renderLabHistory function**

Add after `renderLabDashboardCards` (added in Task 5):

```js
// Core markers shown in history table columns (all profiles show these)
const HISTORY_TABLE_MARKERS = [
  'total_testosterone','estradiol','hematocrit','shbg','prolactin','alt','ast','igf1','hdl','ldl'
];

function renderLabHistory() {
  const cache = window._labMarkersCache || {};
  const profile = getProfile();
  const dates = Object.keys(cache).sort((a, b) => b.localeCompare(a));

  // ── Trend charts ──
  const trendEl = document.getElementById('lab-trend-charts');
  if (trendEl) {
    const coreKeys = (PROFILE_DASHBOARD_CARDS[profile.focus] || PROFILE_DASHBOARD_CARDS.trt).slice(0, 4);
    if (dates.length < 2) {
      trendEl.innerHTML = '<div style="color:var(--text-muted);font-size:12px;padding:20px;text-align:center;grid-column:1/-1;">Need at least 2 draw dates to show trends.</div>';
    } else {
      trendEl.innerHTML = coreKeys.map(key => `
        <div>
          <div style="font-size:11px;font-weight:500;color:var(--text-muted);margin-bottom:6px;">${MARKER_DEFINITIONS[key]?.label || key}</div>
          <div class="chart-wrap" style="height:120px;"><canvas id="lab-trend-${key}"></canvas></div>
        </div>`).join('');
      const chronoDates = [...dates].reverse();
      const shortLabels = chronoDates.map(d => { const [,m,day] = d.split('-'); return `${+m}/${+day}`; });
      coreKeys.forEach(key => {
        const def = MARKER_DEFINITIONS[key];
        if (!def) return;
        const vals = chronoDates.map(d => {
          const row = (cache[d] || []).find(r => r.marker_key === key);
          return row ? row.value : null;
        });
        if (vals.every(v => v == null)) return;
        makeChart(`lab-trend-${key}`, 'line', shortLabels, [{
          data: vals,
          borderColor: 'var(--primary-bright)',
          backgroundColor: 'transparent',
          tension: 0.3,
          spanGaps: true,
          pointRadius: 3,
        }], { plugins: { legend: { display: false } }, scales: { x: { ticks: { font: { size: 9 } } }, y: { ticks: { font: { size: 9 } } } } });
      });
    }
  }

  // ── History table ──
  const wrap = document.getElementById('labs-table-wrap');
  if (!wrap) return;
  if (!dates.length) {
    wrap.innerHTML = '<div style="color:var(--text-muted);font-size:13px;text-align:center;padding:30px;">No lab results yet.</div>';
    return;
  }

  const cols = HISTORY_TABLE_MARKERS.filter(key => dates.some(d => (cache[d] || []).find(r => r.marker_key === key)));
  const badgeClass = { green: 'badge-green', amber: 'badge-amber', red: 'badge-red', muted: 'badge-muted' };

  const thead = `<tr><th>Date</th>${cols.map(key => `<th>${MARKER_DEFINITIONS[key]?.label || key}</th>`).join('')}</tr>`;
  const tbody = dates.map(date => {
    const cells = cols.map(key => {
      const row = (cache[date] || []).find(r => r.marker_key === key);
      if (!row) return '<td style="color:var(--text-muted);">—</td>';
      const def = MARKER_DEFINITIONS[key];
      const cls = def ? classifyValue(row.value, def.ranges, profile.sex) : 'muted';
      const display = Number.isInteger(row.value) ? row.value : parseFloat(row.value).toFixed(1);
      return `<td><span class="metric-badge ${badgeClass[cls]}">${display}</span></td>`;
    }).join('');
    return `<tr onclick="loadLabDateForEdit('${date}')" style="cursor:pointer;">${`<td class="mono">${date}</td>`}${cells}</tr>`;
  }).join('');

  wrap.innerHTML = `<table class="data-table"><thead>${thead}</thead><tbody>${tbody}</tbody></table>`;
}

function loadLabDateForEdit(drawnAt) {
  const cache = window._labMarkersCache || {};
  const rows = cache[drawnAt] || [];

  // Clear form, populate from cache
  clearLabForm();
  document.getElementById('lab-date').value = drawnAt;
  rows.forEach(({ marker_key, value }) => {
    const el = document.querySelector(`.lab-field[data-key="${marker_key}"]`);
    if (el) el.value = value;
  });
  updateLabGroupCounts();

  // Open group(s) that have data
  ['hormonal','thyroid','cardiovascular','growth','general'].forEach(grp => {
    const body = document.getElementById('grp-' + grp);
    const icon = document.getElementById('grp-' + grp + '-icon');
    if (!body) return;
    const hasFilled = [...body.querySelectorAll('.lab-field')].some(el => el.value !== '');
    if (hasFilled) {
      body.style.display = 'block';
      if (icon) icon.style.transform = 'rotate(180deg)';
    }
  });

  // Show edit banner
  const banner = document.getElementById('lab-edit-banner');
  if (banner) { banner.textContent = `Editing draw date: ${drawnAt} — Save to update`; banner.style.display = 'block'; }

  // Switch to Manual Entry tab
  const btn = document.querySelector('.tab-btn[onclick*="labs-manual"]');
  if (btn) switchTab(btn, 'labs-manual');
}
```

- [ ] **Step 3: Call renderLabHistory from loadDemoData**

In `loadDemoData()`, after `renderLabDashboardCards(window._labMarkersCache)`, add:

```js
  renderLabHistory();
```

- [ ] **Step 4: Verify in browser**

1. Enter 2+ lab draws on different dates via Manual Entry.
2. Go to History tab — trend charts should appear for core markers; history table should show colored badge chips.
3. Click a date row — verify Manual Entry tab opens with correct values pre-filled and the edit banner shows.
4. Change one value, click Save — verify History table updates.

- [ ] **Step 5: Commit**

```bash
git add index-v2.html
git commit -m "feat: lab history table with trend charts and click-to-edit"
```

---

## Task 7: Dynamic Reference Ranges Tab

**Files:**
- Modify: `index-v2.html` — replace `labs-ranges` tab static HTML, add `renderReferenceRanges()`

**Interfaces:**
- Consumes: `MARKER_DEFINITIONS`, `getProfile()`
- Produces: populated reference ranges table matching user's profile sex

- [ ] **Step 1: Replace labs-ranges tab HTML with a container**

Find `<div class="tab-panel" id="labs-ranges">` through its closing `</div>` (before `</section>`). Replace:

```html
      <div class="tab-panel" id="labs-ranges">
        <div class="card" id="ref-ranges-wrap">
          <div style="color:var(--text-muted);font-size:12px;text-align:center;padding:20px;">Loading reference ranges…</div>
        </div>
      </div>
```

- [ ] **Step 2: Add renderReferenceRanges function**

Add after `loadLabDateForEdit`:

```js
const CATEGORY_LABELS = {
  hormonal: 'Hormonal Health',
  thyroid: 'Thyroid & Metabolism',
  cardiovascular: 'Cardiovascular & Lipid',
  growth: 'Growth & Nutritional',
  general: 'General Health & Safety',
};

function renderReferenceRanges() {
  const wrap = document.getElementById('ref-ranges-wrap');
  if (!wrap) return;
  const sex = getProfile().sex;

  const byCategory = {};
  for (const [key, def] of Object.entries(MARKER_DEFINITIONS)) {
    if (!def.sex.includes(sex)) continue;
    if (!byCategory[def.category]) byCategory[def.category] = [];
    byCategory[def.category].push({ key, def });
  }

  const fmtRange = (lo, hi) => {
    if (lo == null && hi == null) return '—';
    if (lo == null) return `< ${hi}`;
    if (hi == null) return `> ${lo}`;
    return `${lo} – ${hi}`;
  };

  const sections = Object.entries(CATEGORY_LABELS).map(([cat, catLabel]) => {
    const entries = byCategory[cat];
    if (!entries?.length) return '';
    const rows = entries.map(({ def }) => {
      const r = def.ranges[sex] || def.ranges.male || def.ranges.female;
      const alertCol = r.alert_above != null
        ? `> ${r.alert_above} ${def.unit}`
        : r.alert_below != null
          ? `< ${r.alert_below} ${def.unit}`
          : '—';
      return `<tr>
        <td>${def.label}</td>
        <td class="mono" style="color:var(--green);">${fmtRange(...(r.optimal||[null,null]))} ${def.unit}</td>
        <td class="mono">${fmtRange(...(r.normal||[null,null]))} ${def.unit}</td>
        <td class="mono" style="color:var(--red);">${alertCol}</td>
      </tr>`;
    }).join('');
    return `<div class="card-title" style="margin-top:16px;">${catLabel}</div>
      <table class="data-table"><thead><tr><th>Marker</th><th>Optimal</th><th>Normal</th><th>Alert If</th></tr></thead><tbody>${rows}</tbody></table>`;
  }).join('');

  wrap.innerHTML = `<div class="card-title">Reference Ranges — ${sex === 'male' ? 'Male' : 'Female'}</div>${sections}
    <div style="font-size:11px;color:var(--text-muted);margin-top:14px;line-height:1.6;">Source: Bloodwork Reference Guide v1.0 (May 2026). For informational use only — consult your provider for clinical decisions.</div>`;
}
```

- [ ] **Step 3: Call renderReferenceRanges on DOMContentLoaded and when profile sex changes**

In `DOMContentLoaded` callback, add:
```js
  renderReferenceRanges();
```

The `onchange` handler already added to the `#profile-sex` select in Task 3 calls `renderReferenceRanges()` — verify it's there.

- [ ] **Step 4: Verify in browser**

1. Go to Blood Labs → Reference Ranges — table should show all markers organized by category.
2. Go to Settings → change Biological Sex to Female → come back to Reference Ranges — table should update (female-specific ranges for FSH, Progesterone, etc.).
3. Confirm PSA is absent on Female profile (male-only marker).

- [ ] **Step 5: Commit**

```bash
git add index-v2.html
git commit -m "feat: dynamic reference ranges tab driven by MARKER_DEFINITIONS and user profile"
```

---

## Task 8: PDF Upload + Parsing

**Files:**
- Modify: `index-v2.html` — load pdf.js from CDN, replace `labs-upload` tab HTML, add `parsePdf()`, `showLabImportPreview()`, `confirmLabImport()`

**Interfaces:**
- Consumes: `CODE_TO_MARKERS`, `MARKER_DEFINITIONS`, `submitLabEntry()` save path (reused via `confirmLabImport`)
- Produces: preview table of extracted markers; on confirm, saves to `hrt_lab_markers` + Supabase

- [ ] **Step 1: Add pdf.js CDN script tag**

Find the closing `</head>` tag. Add before it:

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js" defer></script>
```

- [ ] **Step 2: Replace labs-upload tab HTML**

Find `<div class="tab-panel" id="labs-upload">` through its closing `</div>`. Replace:

```html
      <div class="tab-panel" id="labs-upload">
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;align-items:start;">
          <div class="card">
            <div class="card-title">Upload PDF Bloodwork</div>
            <div class="form-group">
              <label class="form-label">Draw Date (from the PDF)</label>
              <input type="date" class="form-input" id="import-date">
            </div>
            <div class="upload-zone" onclick="document.getElementById('pdf-input').click()">
              <div class="upload-icon"><i class="ti ti-file-type-pdf"></i></div>
              <div class="upload-text">Click to upload or drag &amp; drop</div>
              <div class="upload-sub">LabCorp or Quest PDF — order codes matched automatically</div>
              <input type="file" id="pdf-input" accept=".pdf" style="display:none;" onchange="handlePdfUpload(this)">
            </div>
            <div id="pdf-status" style="margin-top:12px;font-size:12px;display:none;"></div>
            <div style="margin-top:14px;font-size:11px;color:var(--text-muted);line-height:1.6;">
              <i class="ti ti-shield-check" style="color:var(--green);"></i> Parsed entirely in your browser. No PDF is uploaded to any server.
            </div>
          </div>
          <div class="card">
            <div class="card-title">Lab Code Reference</div>
            <div style="font-size:11px;color:var(--text-muted);margin-bottom:10px;">Use these codes when ordering labs to ensure automatic matching.</div>
            <div style="max-height:400px;overflow-y:auto;">
              <table class="data-table" id="lab-code-ref-table">
                <thead><tr><th>Marker</th><th>LabCorp</th><th>Quest</th></tr></thead>
                <tbody id="lab-code-ref-body"></tbody>
              </table>
            </div>
          </div>
        </div>
        <!-- Import preview (shown after parsing) -->
        <div class="card" id="lab-import-preview" style="display:none;margin-top:14px;">
          <div class="card-title">Review Extracted Values</div>
          <div style="font-size:12px;color:var(--text-muted);margin-bottom:10px;">Green = order code matched (high confidence). Amber = name matched (verify). Edit any value before confirming.</div>
          <div id="lab-import-table-wrap"></div>
          <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:12px;">
            <button class="btn-secondary" onclick="document.getElementById('lab-import-preview').style.display='none'">Cancel</button>
            <button class="btn-primary" id="lab-import-confirm-btn" onclick="">Confirm &amp; Save</button>
          </div>
        </div>
      </div>
```

- [ ] **Step 3: Populate lab code reference table on DOMContentLoaded**

In `DOMContentLoaded` callback, add:

```js
  // Populate lab code reference table
  const codeBody = document.getElementById('lab-code-ref-body');
  if (codeBody) {
    codeBody.innerHTML = Object.entries(MARKER_DEFINITIONS).map(([, def]) =>
      `<tr><td>${def.label}</td><td class="mono">${def.labcorp_code || '—'}</td><td class="mono">${def.quest_code || '—'}</td></tr>`
    ).join('');
  }
```

- [ ] **Step 4: Add parsePdf, showLabImportPreview, confirmLabImport functions**

Add after `renderReferenceRanges`:

```js
async function handlePdfUpload(input) {
  const file = input.files[0];
  if (!file) return;
  const status = document.getElementById('pdf-status');
  status.style.display = 'block'; status.style.color = 'var(--amber)';
  status.textContent = '⏳ Parsing PDF…';
  try {
    const rows = await parsePdf(file);
    if (rows.length === 0) {
      status.style.color = 'var(--red)';
      status.textContent = '⚠ No markers found. Try uploading a CSV instead, or use Manual Entry.';
      return;
    }
    status.style.display = 'none';
    showLabImportPreview(rows, 'pdf');
  } catch(e) {
    console.error('[parsePdf] failed:', e);
    status.style.color = 'var(--red)';
    status.textContent = '⚠ Could not read this PDF. Try the CSV export from your lab portal, or use Manual Entry.';
  }
  input.value = '';
}

async function parsePdf(file) {
  // pdf.js extracts text page by page
  const pdfjsLib = window['pdfjs-dist/build/pdf'];
  if (!pdfjsLib) throw new Error('pdf.js not loaded');
  pdfjsLib.GlobalWorkerOptions.workerSrc =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';

  const buffer = await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({ data: buffer }).promise;
  let fullText = '';
  for (let i = 1; i <= pdf.numPages; i++) {
    const page = await pdf.getPage(i);
    const content = await page.getTextContent();
    fullText += content.items.map(item => item.str).join(' ') + '\n';
  }

  const results = [];
  const seen = new Set();

  // Strategy 1: match known order codes
  for (const [code, keys] of Object.entries(CODE_TO_MARKERS)) {
    // Find the code in the text (LabCorp/Quest codes appear as standalone numbers)
    const codeRegex = new RegExp(`\\b${code}\\b`);
    if (!codeRegex.test(fullText)) continue;

    // For each marker_key this code can produce, look for the marker's label nearby
    keys.forEach(marker_key => {
      if (seen.has(marker_key)) return;
      const def = MARKER_DEFINITIONS[marker_key];
      if (!def) return;
      // Look for a number near the marker label or code in the text
      const labelVariants = [def.label, marker_key.replace(/_/g,' ')];
      for (const lv of labelVariants) {
        // Find numeric value: first decimal or integer after the label within 120 chars
        const idx = fullText.toLowerCase().indexOf(lv.toLowerCase());
        if (idx === -1) continue;
        const snippet = fullText.slice(idx, idx + 120);
        const numMatch = snippet.match(/(\d+\.?\d*)/);
        if (numMatch) {
          results.push({ marker_key, value: parseFloat(numMatch[1]), confidence: 'high' });
          seen.add(marker_key);
          break;
        }
      }
    });
  }

  // Strategy 2: name-based fallback for unmatched markers
  for (const [marker_key, def] of Object.entries(MARKER_DEFINITIONS)) {
    if (seen.has(marker_key)) continue;
    const labelVariants = [def.label.toLowerCase(), marker_key.replace(/_/g,' ')];
    for (const lv of labelVariants) {
      const idx = fullText.toLowerCase().indexOf(lv);
      if (idx === -1) continue;
      const snippet = fullText.slice(idx, idx + 80);
      const numMatch = snippet.match(/(\d+\.?\d*)/);
      if (numMatch) {
        results.push({ marker_key, value: parseFloat(numMatch[1]), confidence: 'medium' });
        seen.add(marker_key);
        break;
      }
    }
  }

  return results;
}

function showLabImportPreview(rows, source) {
  const preview = document.getElementById('lab-import-preview');
  const wrap = document.getElementById('lab-import-table-wrap');
  if (!preview || !wrap) return;

  const confColor = { high: 'var(--green)', medium: 'var(--amber)' };
  const confIcon  = { high: '✓', medium: '~' };

  wrap.innerHTML = `<table class="data-table">
    <thead><tr><th>Confidence</th><th>Marker</th><th>Value</th><th>Unit</th></tr></thead>
    <tbody>
      ${rows.map((r, i) => {
        const def = MARKER_DEFINITIONS[r.marker_key] || {};
        return `<tr>
          <td style="color:${confColor[r.confidence] || 'var(--text-muted)'};">${confIcon[r.confidence] || '?'}</td>
          <td>${def.label || r.marker_key}</td>
          <td><input type="number" class="form-input" style="width:100px;padding:4px 8px;"
              id="import-val-${i}" value="${r.value}" step="0.01"></td>
          <td style="color:var(--text-muted);">${def.unit || ''}</td>
        </tr>`;
      }).join('')}
    </tbody>
  </table>`;

  // Wire confirm button with current rows + source
  const btn = document.getElementById('lab-import-confirm-btn');
  if (btn) btn.onclick = () => confirmLabImport(rows, source);

  preview.style.display = 'block';
  preview.scrollIntoView({ behavior: 'smooth' });
}

async function confirmLabImport(rows, source) {
  const drawnAt = document.getElementById('import-date').value;
  if (!drawnAt) { alert('Please set the draw date before confirming.'); return; }

  // Read edited values from the preview inputs
  const finalRows = rows.map((r, i) => {
    const el = document.getElementById(`import-val-${i}`);
    return { ...r, value: el ? parseFloat(el.value) : r.value };
  }).filter(r => !isNaN(r.value));

  // Persist to localStorage
  const stored = lsGet('hrt_lab_markers', []);
  finalRows.forEach(({ marker_key, value }) => {
    const idx = stored.findIndex(r => r.drawn_at === drawnAt && r.marker_key === marker_key);
    const row = { drawn_at: drawnAt, marker_key, value, lab_source: source === 'pdf' ? 'labcorp_pdf' : 'csv' };
    if (idx >= 0) stored[idx] = row; else stored.push(row);
  });
  stored.sort((a, b) => b.drawn_at.localeCompare(a.drawn_at));
  localStorage.setItem('hrt_lab_markers', JSON.stringify(stored));

  // Update in-memory cache
  if (!window._labMarkersCache) window._labMarkersCache = {};
  if (!window._labMarkersCache[drawnAt]) window._labMarkersCache[drawnAt] = [];
  finalRows.forEach(({ marker_key, value }) => {
    const cache = window._labMarkersCache[drawnAt];
    const idx = cache.findIndex(r => r.marker_key === marker_key);
    const row = { marker_key, value, lab_source: source === 'pdf' ? 'labcorp_pdf' : 'csv' };
    if (idx >= 0) cache[idx] = row; else cache.push(row);
  });

  // Supabase upsert
  if (_supa && _supaUser) {
    const supaRows = finalRows.map(({ marker_key, value }) => ({
      user_id: _supaUser.id, drawn_at: drawnAt, marker_key, value,
      lab_source: source === 'pdf' ? 'labcorp_pdf' : 'csv'
    }));
    const { error } = await _supa.from('lab_markers').upsert(supaRows, { onConflict: 'user_id,drawn_at,marker_key' });
    if (error) console.error('[confirmLabImport] Supabase upsert failed:', error);
  }

  renderLabDashboardCards(window._labMarkersCache);
  renderLabHistory();
  document.getElementById('lab-import-preview').style.display = 'none';
  alert(`✓ ${finalRows.length} markers saved for ${drawnAt}.`);
}
```

- [ ] **Step 5: Verify in browser**

1. Go to Blood Labs → Upload → PDF tab. Confirm lab code reference table is populated.
2. Set a draw date.
3. Upload a real LabCorp or Quest PDF. Verify the preview table appears with confidence indicators.
4. Edit any amber values, click Confirm & Save.
5. Go to History tab — verify saved markers appear.

- [ ] **Step 6: Commit**

```bash
git add index-v2.html
git commit -m "feat: PDF upload with client-side pdf.js order-code matching and preview confirmation"
```

---

## Task 9: CSV Parsing + Supabase Query Path + Data Migration

**Files:**
- Modify: `index-v2.html` — add CSV tab, add `parseCsv()`, update `loadUserData()`, add `migrateLabResults()`

**Interfaces:**
- Consumes: `MARKER_DEFINITIONS`, `showLabImportPreview()`, `confirmLabImport()`, `_supa`, `_supaUser`
- Produces: full Supabase read path building `_labMarkersCache`; one-time migration from `lab_results` to `lab_markers`

- [ ] **Step 1: Add Papa.parse CDN**

Find the pdf.js `<script>` tag added in Task 8. Add below it:

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/PapaParse/5.4.1/papaparse.min.js" defer></script>
```

- [ ] **Step 2: Add a CSV sub-tab to the Upload tab**

Find the Upload tab's `<div class="card">` that contains "Upload PDF Bloodwork". Above it, add a small tab bar, and wrap both the PDF card and a new CSV card:

Replace the entire `<div class="tab-panel" id="labs-upload">` outer wrapper content:

```html
      <div class="tab-panel" id="labs-upload">
        <div class="tab-bar" style="margin-bottom:12px;">
          <button class="tab-btn active" onclick="switchTab(this,'upload-pdf')">PDF</button>
          <button class="tab-btn" onclick="switchTab(this,'upload-csv')">CSV</button>
        </div>

        <div class="tab-panel active" id="upload-pdf">
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;align-items:start;">
            <div class="card">
              <div class="card-title">Upload PDF Bloodwork</div>
              <div class="form-group">
                <label class="form-label">Draw Date (from the PDF)</label>
                <input type="date" class="form-input" id="import-date">
              </div>
              <div class="upload-zone" onclick="document.getElementById('pdf-input').click()">
                <div class="upload-icon"><i class="ti ti-file-type-pdf"></i></div>
                <div class="upload-text">Click to upload or drag &amp; drop</div>
                <div class="upload-sub">LabCorp or Quest PDF — order codes matched automatically</div>
                <input type="file" id="pdf-input" accept=".pdf" style="display:none;" onchange="handlePdfUpload(this)">
              </div>
              <div id="pdf-status" style="margin-top:12px;font-size:12px;display:none;"></div>
              <div style="margin-top:14px;font-size:11px;color:var(--text-muted);line-height:1.6;">
                <i class="ti ti-shield-check" style="color:var(--green);"></i> Parsed entirely in your browser. No file is uploaded to any server.
              </div>
            </div>
            <div class="card">
              <div class="card-title">Lab Code Reference</div>
              <div style="font-size:11px;color:var(--text-muted);margin-bottom:10px;">Use these codes when ordering labs.</div>
              <div style="max-height:400px;overflow-y:auto;">
                <table class="data-table"><thead><tr><th>Marker</th><th>LabCorp</th><th>Quest</th></tr></thead>
                <tbody id="lab-code-ref-body"></tbody></table>
              </div>
            </div>
          </div>
        </div>

        <div class="tab-panel" id="upload-csv" style="display:none;">
          <div class="card" style="max-width:500px;">
            <div class="card-title">Upload CSV Results</div>
            <div class="form-group">
              <label class="form-label">Draw Date</label>
              <input type="date" class="form-input" id="import-date-csv">
            </div>
            <div class="upload-zone" onclick="document.getElementById('csv-input').click()">
              <div class="upload-icon"><i class="ti ti-file-spreadsheet"></i></div>
              <div class="upload-text">Click to upload CSV</div>
              <div class="upload-sub">Export from LabCorp Patient Portal or Quest MyQuest</div>
              <input type="file" id="csv-input" accept=".csv,.xlsx" style="display:none;" onchange="handleCsvUpload(this)">
            </div>
            <div id="csv-status" style="margin-top:12px;font-size:12px;display:none;"></div>
          </div>
        </div>

        <!-- Shared import preview -->
        <div class="card" id="lab-import-preview" style="display:none;margin-top:14px;">
          <div class="card-title">Review Extracted Values</div>
          <div style="font-size:12px;color:var(--text-muted);margin-bottom:10px;">Green = high confidence match. Amber = verify before saving. Edit any value.</div>
          <div id="lab-import-table-wrap"></div>
          <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:12px;">
            <button class="btn-secondary" onclick="document.getElementById('lab-import-preview').style.display='none'">Cancel</button>
            <button class="btn-primary" id="lab-import-confirm-btn">Confirm &amp; Save</button>
          </div>
        </div>
      </div>
```

Note: `import-date` is now inside `upload-pdf`. Update `confirmLabImport` to read date from both `import-date` (PDF) and `import-date-csv` (CSV) by passing the date directly:

Update `confirmLabImport` signature: `async function confirmLabImport(rows, source, drawnAt)` and remove the `document.getElementById('import-date').value` line, using the passed `drawnAt` instead. Update the `showLabImportPreview` call sites and `btn.onclick` to pass `drawnAt`.

Updated `showLabImportPreview`:
```js
function showLabImportPreview(rows, source, drawnAt) {
  // ... (existing body unchanged except btn.onclick line below)
  if (btn) btn.onclick = () => confirmLabImport(rows, source, drawnAt);
  // ...
}
```

Updated `handlePdfUpload` call:
```js
    const drawnAt = document.getElementById('import-date').value;
    if (!drawnAt) { status.style.color='var(--red)'; status.textContent='Set draw date first.'; status.style.display='block'; return; }
    const rows = await parsePdf(file);
    // ...
    showLabImportPreview(rows, 'pdf', drawnAt);
```

- [ ] **Step 3: Add parseCsv and handleCsvUpload**

Add after `confirmLabImport`:

```js
function handleCsvUpload(input) {
  const file = input.files[0];
  if (!file) return;
  const drawnAt = document.getElementById('import-date-csv').value;
  const status = document.getElementById('csv-status');
  if (!drawnAt) {
    status.style.display='block'; status.style.color='var(--red)';
    status.textContent = 'Set draw date before uploading.'; return;
  }
  status.style.display='block'; status.style.color='var(--amber)'; status.textContent='⏳ Parsing CSV…';
  Papa.parse(file, {
    header: true,
    skipEmptyLines: true,
    complete(result) {
      try {
        const rows = parseCsv(result.data);
        if (!rows.length) {
          status.style.color='var(--red)'; status.textContent='⚠ No markers matched. Check CSV format.'; return;
        }
        status.style.display='none';
        showLabImportPreview(rows, 'csv', drawnAt);
      } catch(e) {
        status.style.color='var(--red)'; status.textContent='⚠ CSV parse error: ' + e.message;
      }
    },
    error(e) { status.style.color='var(--red)'; status.textContent='⚠ ' + e.message; }
  });
  input.value = '';
}

function parseCsv(rows) {
  // Build name-to-key reverse index from MARKER_DEFINITIONS
  const nameIndex = {};
  for (const [key, def] of Object.entries(MARKER_DEFINITIONS)) {
    nameIndex[def.label.toLowerCase()] = key;
    nameIndex[key.replace(/_/g,' ')] = key;
    // Common Quest/LabCorp CSV column name variants
    nameIndex[def.label.toLowerCase().replace(/[^a-z0-9]/g,'')] = key;
  }

  const results = [];
  const seen = new Set();

  rows.forEach(row => {
    // Quest CSV: "Test Name", "Result" columns; LabCorp CSV: "Test", "Value"
    const testName = (row['Test Name'] || row['Test'] || row['COMPONENT'] || '').toLowerCase().trim();
    const rawValue = row['Result'] || row['Value'] || row['YOUR VALUE'] || '';
    if (!testName || !rawValue) return;

    const numVal = parseFloat(rawValue.replace(/[^0-9.-]/g, ''));
    if (isNaN(numVal)) return;

    // Try exact match, then normalized match
    const key = nameIndex[testName] || nameIndex[testName.replace(/[^a-z0-9]/g,'')];
    if (key && !seen.has(key)) {
      results.push({ marker_key: key, value: numVal, confidence: 'high' });
      seen.add(key);
    }
  });

  return results;
}
```

- [ ] **Step 4: Update loadUserData() to query lab_markers and build _labMarkersCache**

Find `async function loadUserData()` (~line 1725). Inside the `try` block, find the `Promise.all` call. Add `lab_markers` query:

```js
    const [logsRes, metricsRes, labsRes, markersRes] = await Promise.all([
      _supa.from('administration_log').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(50),
      _supa.from('daily_metrics').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(90),
      _supa.from('lab_results').select('id,drawn_at,total_testosterone,free_testosterone,estradiol,hematocrit,hemoglobin,psa,lh,ast,alt,shbg').eq('user_id', uid).order('drawn_at', { ascending: false }).limit(12),
      _supa.from('lab_markers').select('drawn_at,marker_key,value,lab_source').eq('user_id', uid).order('drawn_at', { ascending: false }).limit(500)
    ]);
    if (markersRes.error) console.error('[loadUserData] lab_markers query failed:', markersRes.error);
```

Then after `if (labsRes.data?.length) renderLabMetrics(labsRes.data);`, add:

```js
    // Build _labMarkersCache from lab_markers rows
    window._labMarkersCache = {};
    (markersRes.data || []).forEach(r => {
      if (!window._labMarkersCache[r.drawn_at]) window._labMarkersCache[r.drawn_at] = [];
      window._labMarkersCache[r.drawn_at].push({ marker_key: r.marker_key, value: r.value, lab_source: r.lab_source });
    });
    renderLabDashboardCards(window._labMarkersCache);
    renderLabHistory();
    // Run migration if lab_results has data but lab_markers is empty
    if ((labsRes.data?.length) && !(markersRes.data?.length)) {
      migrateLabResults(uid, labsRes.data);
    }
```

- [ ] **Step 5: Add migrateLabResults function**

Add after `confirmLabImport`:

```js
async function migrateLabResults(userId, legacyRows) {
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
  for (const legacy of legacyRows) {
    for (const [col, key] of Object.entries(columnMap)) {
      if (legacy[col] != null) {
        rows.push({ user_id: userId, drawn_at: legacy.drawn_at, marker_key: key, value: parseFloat(legacy[col]), lab_source: 'manual' });
      }
    }
  }
  if (!rows.length) return;
  const { error } = await _supa.from('lab_markers').upsert(rows, { onConflict: 'user_id,drawn_at,marker_key' });
  if (error) { console.error('[migrateLabResults] failed:', error); return; }
  console.log(`[migrateLabResults] migrated ${rows.length} rows from lab_results → lab_markers`);
  // Reload to pick up migrated data
  await loadUserData();
}
```

- [ ] **Step 6: Verify end-to-end (signed in)**

1. Sign in with a Supabase account.
2. If you have existing `lab_results` rows: open DevTools Network tab — verify a `lab_markers` upsert fires on first load (migration).
3. Enter new labs via Manual Entry — verify rows appear in Supabase `lab_markers` table.
4. Reload page — verify History tab and dashboard cards still show correct data from Supabase.
5. Upload a CSV — set draw date, upload, confirm preview, save — verify in Supabase.

- [ ] **Step 7: Final commit**

```bash
git add index-v2.html
git commit -m "feat: CSV import, Supabase lab_markers query path, and legacy lab_results migration"
```

---

## Plan Self-Review

**Spec coverage check:**

| Spec requirement | Covered by task |
|-----------------|----------------|
| EAV `lab_markers` Supabase table | Task 1 |
| `MARKER_DEFINITIONS` with 40+ markers | Task 2 |
| `classifyValue()` with alert_below support | Task 2 |
| `CODE_TO_MARKERS` reverse lookup | Task 2 |
| Profile system (sex + focus) in Settings | Task 3 |
| Collapsible panel groups in Manual Entry | Task 4 |
| `submitLabEntry()` EAV persistence | Task 4 |
| localStorage `hrt_lab_markers` fallback | Task 4, 9 |
| Profile-driven dashboard lab cards | Task 5 |
| History table (one row per date, `—` for missing) | Task 6 |
| Trend charts for core markers | Task 6 |
| Click-to-edit flow | Task 6 |
| Dynamic Reference Ranges tab | Task 7 |
| PDF upload + order code matching | Task 8 |
| Preview table with confidence indicators | Task 8 |
| CSV upload + name matching | Task 9 |
| `loadUserData()` Supabase query path | Task 9 |
| `_labMarkersCache` structure | Task 6 (consumed), Task 9 (built) |
| One-time migration from `lab_results` | Task 9 |
| HCT alert banner hide/show | Task 5 (`renderLabDashboardCards` handles it) |
| Error handling for PDF/Supabase failures | Task 8, 9 |

**No gaps found.**

**Type/name consistency check:**
- `window._labMarkersCache` — defined in Task 9 (`loadUserData`), read in Tasks 5, 6. ✓
- `showLabImportPreview(rows, source, drawnAt)` — updated signature propagated to both PDF and CSV callers. ✓
- `confirmLabImport(rows, source, drawnAt)` — updated signature, all callers pass `drawnAt`. ✓
- `renderLabDashboardCards(cache)` — called with `window._labMarkersCache` in Tasks 4, 5, 8, 9. ✓
- `clearLabForm()` — defined in Task 4, called in Task 6. ✓
- `updateLabGroupCounts()` — defined in Task 4, called in Task 6. ✓
- `PROFILE_DASHBOARD_CARDS` — defined in Task 5, referenced in Task 6. ✓
