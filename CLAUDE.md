# HRT Log Dashboard — Claude Instructions

## What this project is

A single-file HTML dashboard (`index.html`) for tracking HRT (Hormone Replacement Therapy) data. It reads from and writes to a Google Sheet and deploys automatically to Cloudflare Pages via GitHub.

**Live URL:** https://health.cruznetllc.com  
**GitHub repo:** https://github.com/cruznet/hrt-dashboard  
**Auto-deploy:** Every push to `main` deploys to Cloudflare Pages in ~30 seconds.

---

## The only file that matters

Everything — HTML, CSS, JavaScript — lives in **`index.html`**. There are no build steps, no npm, no bundler. Edit the file, commit, push. That's it.

---

## Credentials (already in the file, do not change)

```
SHEETS_API_KEY   = AIzaSyBtDRuMPJmpfozjauPcjNYqtkWgb8BIoZo
SHEETS_CLIENT_ID = 671234379522-7i667etomk82dcoegnuhosu2lf0njtv2.apps.googleusercontent.com
SHEET_ID         = 1-1zGJo-1SudZ37LZKzqgs-7pCcvLU2haSNjOYUuF19Q
```

The Google Sheet has yearly tabs (e.g. `2024`, `2025`, `2026`). Row 1 is headers, data starts at row 2.

---

## Google OAuth — how it works

Authentication uses Google Identity Services (GIS) token client — **not** the deprecated implicit grant flow. The pattern is:

```javascript
_gisClient = window.google.accounts.oauth2.initTokenClient({
  client_id: SHEETS_CLIENT_ID,
  scope: 'https://www.googleapis.com/auth/spreadsheets',
  callback: function(resp) {
    sheetsToken = resp.access_token;
    saveToken(sheetsToken, parseInt(resp.expires_in || '3600'));
    updateLogAuthUI();
  },
});
_gisClient.requestAccessToken(); // NOT requestToken()
```

**Do not change this to implicit grant or any other flow.** It took multiple debugging sessions to land on this.

---

## Key functions to know

| Function | What it does |
|---|---|
| `bootWithSheets()` | Loads all sheet data on page load |
| `syncFromSheets()` | Manual re-sync from Google Sheets |
| `oauthSignIn()` | Triggers Google sign-in popup |
| `clearToken()` | Signs out, clears saved token |
| `updateLogAuthUI()` | Shows/hides sign-in form based on auth state |
| `openLogPanel()` | Opens the log entry modal |
| `renderLogForm()` | Builds the compound input form |
| `showLandingIfNeeded()` | Shows landing page if no token and not dismissed |
| `dismissLanding()` | Hides landing page, sets localStorage flag |

---

## Dashboard tabs

- **Overview** — stats, compound heatmap timeline, day detail panel
- **Blood Labs** — bloodwork panel (reads from sheet)
- **Fitness** — Hevy workout data
- **Log** — write new entries to the sheet

---

## Log form behavior

The log form (`renderLogForm()`) is smart:
- Only shows compounds used in the **last 30 days** (not all columns)
- **Orals** (anastrozole, exemestane, enclomiphene, clomid, etc.) render as toggle switches that emit `TRUE` or `''`
- **Injectables and peptides** render as number steppers (step 0.05)
- Oral columns in the sheet expect `TRUE`/`FALSE` — never send a number to them

---

## Styling conventions

CSS variables are defined at `:root`. The theme is:
- Background: `#000000` (pure black)
- Accent: `#f59e0b` (amber gold)
- Text: `#ffffff`
- Muted: `#666666`
- Border: `#222222`

All new UI should use these variables, not hardcoded colors.

---

## Landing page

The landing page (`#landing-page`) is a fullscreen overlay shown to unauthenticated users who haven't dismissed it. It uses `localStorage` key `hrt_landing_dismissed` to remember dismissal. It disappears automatically when the user signs in.

---

## Deployment workflow

1. Edit `index.html`
2. `git add index.html`
3. `git commit -m "your message"`
4. `git push origin main`
5. Visit https://health.cruznetllc.com in ~30 seconds

No zip uploads. No Cloudflare UI. Just push.

---

## What to avoid

- Do not split into multiple files — keep everything in `index.html`
- Do not add a build system or package.json
- Do not change the OAuth method — `initTokenClient` + `requestAccessToken` is the correct pattern
- Do not send numeric values to oral compound columns in the sheet (they validate TRUE/FALSE only)
- Do not add `redirect_uri` to the GIS token client config — it doesn't use redirects

---

## Skill: Extract Design Language (`/extract-design`)

Extract the full design system (colors, fonts, spacing, tokens) from any website URL.

### How to run

```bash
# In VS Code terminal
npx designlang <url> --screenshots
```

Examples:
```bash
npx designlang https://testosterone.tools --screenshots
npx designlang https://health.cruznetllc.com --screenshots --dark
npx designlang https://example.com --depth 3 --screenshots
```

### Output files (saved to `./design-extract-output/`)

| File | Use for |
|---|---|
| `*-design-language.md` | Paste into Claude as context for styling work |
| `*-preview.html` | Open in browser — visual swatches, type scale, a11y score |
| `*-tailwind.config.js` | Drop into any Tailwind project |
| `*-variables.css` | Copy CSS vars into `index.html` |
| `*-shadcn-theme.css` | shadcn/ui globals.css |
| `*-figma-variables.json` | Import into Figma |
| `*-theme.js` | React/CSS-in-JS theme |
| `*-design-tokens.json` | W3C Design Tokens format |

### Useful flags

| Flag | What it does |
|---|---|
| `--dark` | Also extract dark mode palette |
| `--depth 3` | Crawl 3 pages deep for site-wide tokens |
| `--out ./my-folder` | Custom output directory |
| `--wait 2000` | Wait 2s after load (for SPAs) |

### Typical workflow

1. Run `npx designlang <url> --screenshots`
2. Open `*-preview.html` in browser to review
3. Copy `*-variables.css` vars into `index.html` to match a site's style
4. Paste `*-design-language.md` into Claude chat as design context
