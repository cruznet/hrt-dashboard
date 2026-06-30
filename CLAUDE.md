# HRT Dashboard — Claude Instructions

## AI Development Team

This project uses a structured AI engineering team model. Full org chart, role definitions, pipeline, and quality gates are in [docs/AI-TEAM.md](docs/AI-TEAM.md).

**When given a feature request, follow the full pipeline:** Product Manager → Solution Architect → Technical Lead → Database Architect → Frontend/Backend Engineers → Integration → QA → Documentation → Release.

**You are the Project Director (CTO).** The user is the Product Owner / CEO. Never skip a stage. Never ship without passing all quality gates.

---

## What this project is

A single-file Supabase-backed HRT tracking dashboard deployed on Cloudflare Workers.

- **One file:** `index.html` (~7,100 lines) — all HTML, CSS, and JS in one file. No build system, no npm, no bundler.
- **Deployed at:** hrt.cruznetllc.com (Cloudflare Workers)
- **Local dev:** `python3 server.py` → `http://localhost:3000`

---

## Files

| File | Purpose |
|---|---|
| `index.html` | The full dashboard — single source of truth for all HTML/CSS/JS |
| `landing.html` | Public marketing page — pre-signup funnel tracking lives here |
| `worker.js` | Cloudflare Worker entrypoint — `/api/healthkit` ingest + `/api/track` analytics ingest |
| `supabase-schema.sql` | Supabase DB schema — run in Supabase SQL editor to apply |
| `wrangler.jsonc` | Cloudflare Workers config |
| `server.py` | Local dev server — `python3 server.py` → `http://localhost:3000` |
| `healthkit-data.csv` | Apple Health export — parsed by the HealthKit page (not yet built) |
| `healthkit-sync.gs` | Google Apps Script — future automation to refresh CSV from Apple Health |
| `tests/protocol-logic.html` | Browser test suite for pure JS functions — open in browser to run |
| `tests/bloodwork-hevy-logic.html` | Browser test suite for bloodwork/Hevy logic — open in browser to run |
| `tests/smoke-test.js` | Playwright pre-deploy smoke test — logic suites + unauthenticated pages. See file header for run command. |
| `tests/PRE-DEPLOY-CHECKLIST.md` | Manual ~60-90s checklist for auth-gated paths the smoke test can't reach (OAuth can't be automated here) |
| `docs/ANALYTICS.md` | Funnel/retention SQL queries against `analytics_events` |
| `HEALTHKIT-TAB.md` | Spec for adding a HealthKit page to this dashboard (not yet implemented) |

---

## Stack

**Runtime:** Vanilla JS — no framework, no build system
**Charts:** Chart.js 4.4.0
**Backend:** Supabase JS v2 (`@supabase/supabase-js@2`)
**Auth:** Google OAuth — implicit flow via Supabase
**Workouts:** Hevy API (`https://api.hevyapp.com/v1`) — requires Hevy Pro API key
**Fonts:** DM Sans (UI) + JetBrains Mono (data values)
**Deploy:** Cloudflare Workers (static assets mode)

**Supabase project:** `lnxhksnvcewtpwkaghrh.supabase.co`
**Supabase tables:** `administration_log`, `daily_logs`, `lab_markers`, `analytics_events` (funnel/retention events — service-role write only, no client RLS access; see `docs/ANALYTICS.md`)

---

## Branch strategy & deployment

| Branch | Purpose |
|---|---|
| `main` | Active development — all commits land here |
| `cloudflare/workers-autoconfig` | Production — Cloudflare's bot manages this branch |

**Deploy workflow — do this every time before pushing:**
```bash
git pull origin cloudflare/workers-autoconfig --rebase
git push origin main
```

Cloudflare's bot force-pushes `cloudflare/workers-autoconfig` regularly. Always rebase before pushing to avoid rejection. Keep both branches in sync on each deploy.

---

## Pages

| ID | Name | Notes |
|---|---|---|
| `page-dashboard` | Dashboard | Hero protocol card, vitals metric cards, dose schedule, adherence badge |
| `page-log` | Health Log | Activity log — compound dose entries, notes |
| `page-vitals` | Vitals | Log weight, BP, glucose, mood (1–10), energy (1–10), insulin |
| `page-bloodwork` | Bloodwork | Panel log, KPI cards, trend charts, flag badges |
| `page-physique` | Physique | Body composition measurements, progress tracking |
| `page-workouts` | Workouts | Hevy API integration — week grouping, PR Tracker, E1RM Trends |
| `page-report` | Coach Report | Auto-generated text report — Copy + Print |
| `page-compliance` | Dose Compliance | Heatmap + bar charts for dose adherence (30/60/90 day) |
| `page-protocols` | My Protocols | CRUD for saved protocols, status badges, switch modal |
| `page-builder` | Protocol Builder | Tabbed: Builder · Timeline · Log. Phased compound scheduling. |
| `page-compounds` | Compounds | Reference table for 60+ compounds (AAS, SARMs, peptides, etc.) |
| `page-calculator` | Calculators | Tabs: AAS/Injectable PK simulation · Peptide reconstitution (blend mode) |
| `page-settings` | Settings | Profile (sex + focus), mode preference |

---

## localStorage keys

| Key | Contents |
|---|---|
| `hrt_protocols` | Array of saved protocol objects |
| `hrt_active_protocol` | ID of the active protocol |
| `hrt_active_protocol_data` | Full active protocol object |
| `hrt_vitals_log` | Array of `{date, weight, systolic, diastolic, glucose, mood, energy, notes}` |
| `hrt_doses_taken` | Array of dose acknowledgments `{label, date, ts}` |
| `hrt_bloodwork` | Array of bloodwork panels `{id, date, lab, markers, notes}` |
| `hrt_physique_measurements` | Array of physique entries `{date, measurements}` |
| `hrt_hevy_key` | Hevy API key (set by user in Workouts settings) |
| `hrt_hevy_data` | Cached Hevy workout array |
| `hrt_last_active` | ISO timestamp of last user interaction — used for inactivity timeout |
| `hrt_mode` | UI mode preference |
| `hrt_anon_id` | UUID generated on first visit — shared between `landing.html` and `index.html` (same origin). Used to join pre-signup funnel events to post-signup user behavior. |
| `hrt_first_log_tracked` | `"1"` once `first_log` has been fired. Guards `trackFirstLogIfNeeded()` from firing more than once. |
| `hrt_theme` | `"dark"` (default) or `"light"` — persists theme toggle selection. Applied via `data-theme` attribute on `<html>`. |

---

## Key functions

| Function | What it does |
|---|---|
| `nav(page)` | Page navigation — updates active state, triggers page-specific render |
| `localDate(d)` | Returns `"YYYY-MM-DD"` in device **local** timezone — never use `toISOString()` |
| `lsGet(key, fallback)` | localStorage read with JSON.parse + fallback |
| `initSupa()` | Creates Supabase client + wires OAuth callback detection |
| `supaSignIn()` / `supaSignOut()` | Google OAuth implicit flow |
| `loadUserData()` | On sign-in: fetches `administration_log`, `daily_logs`, merges with localStorage |
| `syncProtocolsToSupabase()` | Pushes `hrt_protocols` to Supabase |
| `renderVitalsToCards()` | Populates dashboard metric cards from `hrt_vitals_log` |
| `renderDoseSchedule()` | Builds today's dose checklist + upcoming schedule |
| `renderCycleProgress(proto)` | Renders hero protocol card with week strip and compound pills |
| `isDueOnDate(freq, startDate, targetDate)` | Pure function — is a dose due on a given date? |
| `isDueToday(freq, startDate)` | Thin wrapper around `isDueOnDate` for today |
| `daysUntilNextDose(freq, startDate)` | Countdown to next injection for any frequency |
| `normalizeCompound(c)` | Handles old combined `unit="mg E3.5D"` format — **do not rename** |
| `pbFreqToInjectionsPerWeek(freq)` | ED→7, EOD→3.5, E3.5D/2X/WK→2, Weekly→1, array→length |
| `checkDose(name, dose, unit, date)` | Marks dose taken — writes to localStorage + Supabase |
| `uncheckDose(name, date)` | Removes dose acknowledgment |
| `hevyParseMs(t)` | Normalizes Hevy timestamps — handles both Unix int and ISO string from API |
| `hevySync()` | Fetches workouts from Hevy API, caches to `hrt_hevy_data` |
| `hevyE1RM(weightKg, reps)` | Epley formula for estimated 1-rep max |
| `hevyBuildPRMap(workouts)` | Returns `Map<exerciseName, {weight, reps, date}>` of all-time PRs |
| `bwLoad()` / `bwSaveAll(panels)` | Bloodwork localStorage read/write |
| `bwRangeStatus(key, value)` | Returns `'ok' \| 'low' \| 'high' \| 'none'` for a bloodwork marker |
| `renderBloodworkPage()` | Full bloodwork page render |
| `renderPhysiquePage()` | Physique tracker render |
| `renderWorkoutsPage()` | Workouts page render — triggers Hevy tab setup |
| `renderCompliancePage()` | Renders dose compliance heatmap + charts |
| `reportCopy()` | Builds plain-text coach report from all data sources, copies to clipboard |
| `escHtml(s)` | XSS sanitization — use on all user-input before `innerHTML` |
| `makeChart(id, type, labels, datasets, opts)` | Destroys existing chart before re-creating |
| `track(eventName, props)` | Fire-and-forget funnel event to `POST /api/track`. Defined in both `landing.html` and `index.html`. Never throws; analytics must not break the page. |
| `trackFirstLogIfNeeded(logType)` | Fires `first_log` event exactly once per browser (guarded by `hrt_first_log_tracked` localStorage flag). Called from `checkDose`, `submitLog`, and `submitWeeklyCheckin`. |
| `setTheme(mode)` | Sets `data-theme` on `<html>`, persists to `hrt_theme`, and updates the topbar toggle icon. Mode is `"dark"` or `"light"`. |
| `initTheme()` | Reads `hrt_theme` from localStorage and calls `setTheme()`. Called once in `DOMContentLoaded`. Anti-FOUC inline script in `<head>` also applies theme before CSS renders. |

---

## Pre-deploy testing workflow

Before every deploy, two steps — both are required:

1. **Automated smoke test** (logic suites + unauthenticated pages):
   ```bash
   python3 server.py &          # or: already running
   cd ~/.claude/skills/playwright-skill
   node run.js /path/to/hrt-dashboard/tests/smoke-test.js
   ```
   Must exit 0. Fix any failures before proceeding.

2. **Manual checklist** (`tests/PRE-DEPLOY-CHECKLIST.md`) — takes ~60-90 seconds.
   Covers auth-gated paths (dashboard, dose logging, bloodwork, protocols, settings)
   that Google OAuth prevents from being automated.

---

## CSS design tokens

```css
:root {
  --bg-deep:        #08080E;
  --bg-base:        #0D0D15;
  --bg-card:        #14141E;
  --bg-card-hover:  #1C1C28;
  --bg-sidebar:     #0A0A12;

  --primary:        #C9920A;    /* gold — muted */
  --primary-bright: #F5C518;    /* gold — high-visibility, matches testosterone.tools */
  --primary-dim:    rgba(245,197,24,0.09);
  --primary-border: rgba(245,197,24,0.26);

  --teal:    #22D3EE;
  --green:   #22C55E;
  --red:     #F87171;
  --amber:   #FB923C;
  --purple:  #C084FC;

  --text-primary:   #FFFFFF;
  --text-secondary: #E8E8ED;
  --text-muted:     #909098;
  --text-label:     #C4C4CC;

  --border:     rgba(255,255,255,0.10);
  --border-mid: rgba(255,255,255,0.17);

  --font-data: 'JetBrains Mono', monospace;   /* all numeric/data values */
  --font-ui:   'DM Sans', system-ui, sans-serif;
  --radius:    8px;
  --radius-lg: 12px;
}
```

All new UI must use these variables. No hardcoded colors.

---

## Mobile / iOS

The app is designed for native iOS home screen use:

- `viewport-fit=cover` + `apple-mobile-web-app-capable` + `black-translucent` status bar
- Bottom tab bar (5 items: Home, Doses, Workouts, Labs, More) with `backdrop-filter: blur(24px)` and `safe-area-inset-bottom` padding
- `touch-action: manipulation` on `*` eliminates 300ms tap delay
- `@media (hover: none) and (pointer: coarse)` — scale press feedback on buttons and cards
- All inputs `font-size: 16px` on mobile to prevent iOS auto-zoom on focus
- `overscroll-behavior: none` on body prevents pull-to-refresh

---

## Auth — critical constraints

- OAuth flow: Supabase Google OAuth **implicit grant** — do not add `redirect_uri`, do not switch to PKCE
- Inactivity timer: 8 hours via `localStorage` key `hrt_last_active` (not `setTimeout`) — survives device sleep
- On `visibilitychange` (device wake): checks inactivity AND checks if calendar day rolled over, calling `renderDoseSchedule()` if so

---

## Known sharp edges

- **Hevy timestamps** — `start_time` comes back as either a Unix integer or ISO string depending on endpoint. Always use `hevyParseMs(t)` — never `new Date(t * 1000)` directly.
- **Dates must use local timezone** — `toISOString()` returns UTC and has caused multi-bug incidents. Always use `localDate()`. This includes `hevyBuildPRMap` — use `localDate(new Date(ms))` not `.toISOString().slice(0,10)`.
- **Supabase `r.date` field is untrustworthy** — rows written before the timezone fix may have corrupted UTC dates. Always re-derive date from `r.created_at` using `localDate(new Date(r.created_at))`.
- **localStorage dose migration** — a one-time migration IIFE (`migrateDoseDates`) runs on first load only, guarded by `hrt_dose_migrate_v1` flag in localStorage.
- **XSS: never embed Hevy data in onclick strings** — exercise names come from the Hevy API. Use `data-*` attributes + `escHtml()` for any Hevy-sourced value going into HTML. See E1RM pill pattern: `data-ex="${escHtml(ex)}" onclick="hevySetE1RM(this.dataset.ex)"`.
- **Hevy `end_time` can be null** — in-progress or corrupt Hevy records have no `end_time`. Always guard duration math with `Math.max(0, hevyParseMs(end_time) - hevyParseMs(start_time))`.
- **`_resetInactivityTimer` is throttled** — writes localStorage at most once per minute. Do not remove the throttle; `mousemove` fires at 60fps.

---

## Compound library

`COMPOUNDS` array — each entry:
```js
{
  name: 'Testosterone Cypionate',
  cat: 'AAS',       // AAS | SARM | Peptide | Insulin | Fat Loss | Support | Other
  hl: '8',          // half-life in days (string)
  unit: 'mg',
  freq: 'E3.5D',
  ai: 'Yes',        // aromatizes
  dht: 'Yes',       // DHT conversion
  note: '...'
}
```

Weekly total always: `perInjection × pbFreqToInjectionsPerWeek(freq)` — never from stored `weeklyDose`.

---

## Peptide calculator — blend mode

Draw fraction is calibrated to the **target peptide's mg**, not total vial mg:
```js
drawMl = (desiredMg / targetPeptideMg) * bacWater;
```

---

## What to avoid

- **Do not split into multiple files** — keep everything in `index.html`
- **Do not add a build system or `package.json`**
- **Do not use `c.weeklyDose`** — always compute weekly total from `perInjection × injectionsPerWeek`
- **Do not rename `normalizeCompound()`** — backward compat with v1 localStorage data
- **Do not hardcode colors** — use CSS variables only
- **Do not use `toISOString()` for date strings** — always use `localDate()`
- **Do not trust `r.date` from Supabase** — re-derive from `r.created_at`
- **Always use `escHtml()`** on user-controlled strings before setting `innerHTML`
- **Do not add Google Sheets dependencies** — data comes from CSV or Supabase only
