# HRT Dashboard — Claude Instructions

## What this project is

Two single-file HTML dashboards coexisting in this directory:

- **`index.html`** — Google Sheets-based tracker (active dev, OLED Dark redesign on `v2` branch)
- **`index-v2.html`** — Supabase+localStorage rewrite (separate architecture)

Both are fully self-contained — no build system, no npm, no bundler.

---

## Files

| File | Purpose |
|---|---|
| `index.html` | Google Sheets-based HRT dashboard — active redesign (v1 theme, Google Sheets API + GIS OAuth) |
| `index-v2.html` | Supabase+localStorage rewrite — separate architecture, see § below |
| `supabase-schema.sql` | Supabase DB schema v2.1 — run in Supabase SQL editor |
| `server.py` | Local dev server — `python3 server.py` → `http://localhost:3000` |
| `healthkit-sync.gs` | Google Apps Script — syncs Apple Health data to Sheets, trigger fires at 7 AM |
| `healthkit-data.csv` | CSV fallback for HealthKit tab when Sheets tab is empty or not yet synced |
| `CLAUDE.md` | This file |

---

## Branch strategy

| Branch | Purpose |
|---|---|
| `main` | Stable — last known-good `index.html` state |
| `v2` | Active redesign — OLED Dark theme, SVG nav, dense layout |

---

## index.html — Google Sheets Dashboard

Single-file (~5200 lines). No build system, no npm. All HTML/CSS/JS in one file.

**Stack:** Vanilla JS · Chart.js 4.4.1 · Google Sheets API v4 (read via API key) · GIS OAuth (write) · Motion v11

### Auth — critical constraints

- OAuth flow: GIS `initTokenClient` + `requestAccessToken()` — **do not change to implicit grant or any other flow**
- **Do not add `redirect_uri` to the GIS token client config** — GIS token client does not use redirects
- **Do not send numeric values to oral compound columns in Sheets** — those columns validate TRUE/FALSE only

### Tabs

| Tab | ID | Notes |
|---|---|---|
| Overview | `page-log` | KPI stat cards + activity log |
| Compounds | `page-compounds` | Protocol Timelines / Injection Sites sub-nav |
| Blood Labs | `page-labs` | 6-key-marker snapshot strip + full lab history |
| Intelligence | `page-intelligence` | Collapsible sections; last 2 start collapsed |
| Fitness | `page-fitness` | |
| HealthKit | `page-healthkit` | Reads `healthkit-data.csv` as fallback |

### Key functions (index.html)

| Function | What it does |
|---|---|
| `switchPage(name, evt)` | Tab navigation with Motion v11 animation |
| `switchCompoundsView(view, btn)` | Toggles Protocol Timelines / Injection Sites sub-sections |
| `toggleIntelSection(id, btn)` | Collapses/expands Intelligence section bodies |
| `renderLabs()` | Populates `#labs-snapshot` 6-key-marker grid + full lab table |
| `renderStats()` | KPI cards with per-metric colored accent bars |

### Styling conventions (index.html)

Typography: **Fira Sans** (body/labels) + **Fira Code** (all data values). SVG icons only — no emoji.

```css
:root {
  --bg:#080808; --bg2:#0f0f12; --bg3:#161619; --border:#1f1f26;
  --text:#f0f0f4; --muted:#7a7a88; --accent:#fcd34d;
  --accent2:#ef4444; --accent3:#22c55e; --accent4:#fcd34d;
  --accent5:#8b5cf6; --accent6:#06b6d4;
  --warn:#f97316; --danger:#ef4444; --ok:#22c55e;
  --radius:8px;
  --grid-gap:12px; --card-padding:14px 16px;
  --header-height:52px; --sidebar-width:240px;
}
```

---

## index-v2.html — Supabase Dashboard

### Data storage

All user data is **localStorage-first**. Supabase is wired but optional — the app works fully offline.

| localStorage key | Contents |
|---|---|
| `hrt_protocols` | Array of saved protocol objects |
| `hrt_active_protocol` | ID of the active protocol |
| `hrt_active_protocol_data` | Full active protocol object |
| `hrt_vitals_log` | Array of vitals entries `{date, weight, systolic, diastolic, glucose, mood, energy, notes}` |
| `hrt_doses_taken` | Array of dose acknowledgments `{label, date, ts}` |
| `hrt_mode` | UI mode preference |

### Key functions

| Function | What it does |
|---|---|
| `normalizeCompound(c)` | Handles old combined `unit="mg E3.5D"` vs new separate `unit`+`freq` fields |
| `pbFreqToInjectionsPerWeek(freq)` | ED→7, EOD→3.5, E3.5D/2X/WK→2, Weekly→1 |
| `renderVitalsToCards()` | Populates dashboard metric cards from vitals log |
| `renderUpcoming()` | Builds upcoming doses schedule with mark-taken buttons |
| `renderAdherenceBadge()` | Calculates adherence % over last 30 days |
| `markDoseTaken(label, date)` | Logs a dose acknowledgment to localStorage |

---

## Pages

### Dashboard (`page-dashboard`)
- Metric cards: weight, BP, glucose, mood/energy sparklines, log streak
- Vitals populated on load via `renderVitalsToCards()`
- Upcoming doses with dose acknowledgment (mark taken / log late)
- Adherence badge

### My Protocols (`page-protocols`)
- CRUD for protocols stored in `hrt_protocols`
- Protocol Builder: add compounds with dose/freq/unit, computes weekly totals

### Calculators (`page-calculators`)
Tabs: Dose Calculator · Peptide Calculator · Protocol Builder

- **Dose Calculator** — PK blood level simulation using half-life decay
- **Peptide Calculator** — single compound or blend mode; custom BAC water; draw volume output
- **Protocol Builder** — multi-compound protocols; weekly total = `perInjection × injectionsPerWeek`

### Vitals Log (`page-vitals`)
- Log weight, BP, glucose, mood (1–10), energy (1–10), notes
- Feeds dashboard metric cards and sparklines

### Compounds (`page-compounds`)
- Reference table for 60+ compounds: AAS, SARMs, peptides, insulins, fat loss, support meds
- Data lives in the `COMPOUNDS` array in `index-v2.html`

---

## Compound library

`COMPOUNDS` array — each entry shape:
```js
{
  name: 'Testosterone Cypionate',
  cat: 'AAS',           // AAS | SARM | Peptide | Insulin | Fat Loss | Support | Other
  hl: '8',              // half-life in days (string)
  unit: 'mg',
  freq: 'E3.5D',
  ai: 'Yes',            // aromatizes
  dht: 'Yes',           // DHT conversion
  note: '...'
}
```

Weekly total always computed as `perInjection × pbFreqToInjectionsPerWeek(freq)` — never from stored `weeklyDose`.

---

## Peptide calculator — blend mode

Draw fraction is calibrated to the **target peptide's mg**, not total vial mg:
```js
drawMl = (desiredMg / targetPeptideMg) * bacWater;
```

All other peptides in the blend scale by the same `drawMl / bacWater` fraction.

---

## Vitals → Dashboard feedback loop

`renderVitalsToCards()` runs on page load and after every vitals save. Delta indicators use `lowerIsBetter` flag:
- BP (systolic), glucose → lower = green
- Weight → neutral
- Mood/energy → higher = green (sparklines only)

---

## Dose acknowledgment

- `hrt_doses_taken` stores `{label, date, ts}` per confirmed dose
- `label` format: `"TC 100mg"` (abbreviated compound name + dose + unit)
- Missed dose detection: looks back 3 days for injection days without confirmation
- Adherence: confirmed/expected ratio over last 30 days

---

## Styling conventions

CSS variables defined at `:root`:
```css
--primary:        #6366F1   /* indigo */
--green:          #10B981
--amber:          #F59E0B
--red:            #EF4444
--bg:             #0F1117
--bg-card:        #1A1D27
--bg-deep:        #13151F
--border:         #2A2D3A
--text-primary:   #F1F5F9
--text-secondary: #94A3B8
--text-muted:     #64748B
--font-data:      'JetBrains Mono', monospace
```

All new UI must use these variables — no hardcoded colors.

---

## What to avoid

- Do not split into multiple files — keep everything in `index-v2.html`
- Do not add a build system or package.json
- Do not use `c.weeklyDose` for weekly totals — always compute from `perInjection × injectionsPerWeek`
- Do not add Google Sheets or HealthKit dependencies — v2 is Supabase + localStorage only
- Do not rename `normalizeCompound()` — it handles backward compat with v1 protocol data
