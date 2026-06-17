# HealthKit Tab — Instructions for Claude in VS Code

## What to build

Add a new **HealthKit** tab to `index.html` that reads and visualizes the data from `healthkit-data.csv`.

---

## The data file

**File:** `healthkit-data.csv` (in this project folder)  
**31 days of data**, one row per day, with these columns:

| Column | Description |
|---|---|
| Date/Time | Date of the reading |
| Weight (lbs) | Daily body weight |
| Body Fat Percentage (%) | Body fat % |
| Lean Body Mass (lbs) | Lean mass |
| Heart Rate Variability (ms) | HRV — key HRT health marker |
| Resting Heart Rate (bpm) | Morning resting HR |
| Heart Rate [Min/Max/Avg] (bpm) | Daily HR range |
| Blood Oxygen Saturation (%) | SpO2 |
| Sleep Analysis [Total/Asleep/Deep/REM/Core/Awake] (hr) | Sleep breakdown |
| Step Count (steps) | Daily steps |
| Active Energy (kcal) | Calories burned active |
| Resting Energy (kcal) | Basal calories |
| Apple Exercise Time (min) | Workout minutes |
| Apple Stand Hour (hr) | Stand hours |
| Flights Climbed (count) | Stairs |
| Walking + Running Distance (mi) | Daily distance |
| Respiratory Rate (count/min) | Breathing rate |
| Walking Heart Rate Average (bpm) | HR while walking |
| Time in Daylight (min) | Sun exposure |

---

## How to add the tab

### Step 1 — Add the nav tab button

Find the nav tabs section in `index.html` and add:
```html
<button class="nav-tab" onclick="showPage('healthkit')">HealthKit</button>
```

### Step 2 — Add the page div

After the last `</div>` closing a `.page` div, add:
```html
<div id="page-healthkit" class="page">
  <div style="padding:24px 32px">
    <div id="healthkit-content">Loading HealthKit data...</div>
  </div>
</div>
```

### Step 3 — Load and parse the CSV

Add this JavaScript function. It fetches `healthkit-data.csv` relative to `index.html`:

```javascript
async function loadHealthKit() {
  const resp = await fetch('healthkit-data.csv');
  const text = await resp.text();
  const lines = text.trim().split('\n');
  const headers = lines[0].split(',');
  const rows = lines.slice(1).map(line => {
    const vals = line.split(',');
    const obj = {};
    headers.forEach((h, i) => obj[h.trim()] = vals[i]?.trim() || '');
    return obj;
  });
  return rows;
}
```

### Step 4 — Build the UI

Call `loadHealthKit()` when the HealthKit tab is opened and render:

**Top stats row** (latest values):
- Weight, Body Fat %, HRV, Resting HR, Sleep Total, Steps

**Charts** (use Chart.js, already loaded in index.html):
- Weight trend — line chart, last 30 days
- HRV trend — line chart (amber color, var(--accent))
- Sleep breakdown — stacked bar (Deep, REM, Core, Awake)
- Step count — bar chart

**Style rules:**
- Use existing CSS variables (--bg, --bg2, --bg3, --border, --accent, --text, --muted)
- Match the card style: `class="card"` with `background:var(--bg2);border:1px solid var(--border);border-radius:var(--radius);padding:20px`
- Accent color for highlights: `var(--accent)` (#f59e0b amber)
- Sleep deep = #8b5cf6 (purple), REM = #06b6d4 (cyan), Core = #3b82f6 (blue)

---

## Important notes

- `healthkit-data.csv` must be in the **same folder** as `index.html` so `fetch('healthkit-data.csv')` works locally
- When pushed to GitHub, Cloudflare Pages will serve both files — it will work at health.cruznetllc.com automatically
- Data is currently static (exported manually). Future automation via Google Drive → Apps Script can update it on a schedule.
- HRV is the most important HRT marker to highlight — low HRV correlates with protocol stress

---

## After building

Push both files to GitHub:
```bash
git add index.html healthkit-data.csv
git commit -m "Add HealthKit tab with 30 days of Apple Health data"
git push origin main
```
