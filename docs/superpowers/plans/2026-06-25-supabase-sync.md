# Supabase Sync + Google OAuth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hardcode the Supabase anon key so Google sign-in works out of the box, sync protocol data to Supabase, and restore it on load — enabling true multi-device use.

**Architecture:** Single-file vanilla JS app (`index.html`). All changes are in that one file. `syncProtocolsToSupabase()` upserts protocol localStorage state to a `user_settings` Supabase table on every write. `loadUserData()` restores that state on sign-in. No build system; test with a browser directly.

**Tech Stack:** Vanilla JS, Supabase JS client (CDN), localStorage, HTML/CSS

## Global Constraints

- All code changes confined to `index.html` (renamed from `index-v2.html`)
- No new files, no new CSS files, no new localStorage keys
- User variable is `_supaUser` (not `_user`) — this is the existing global set by `_initSupaAuth`
- `syncProtocolsToSupabase()` is always fire-and-forget — never awaited at call sites, never blocks UI
- `escHtml` wraps all user-supplied strings rendered to innerHTML — no new innerHTML surfaces in this sprint
- Supabase anon key to hardcode: `sb_publishable__lU8rYLjeTMoAgXANKsKKA_9Xgau8bm`
- Supabase URL: `https://lnxhksnvcewtpwkaghrh.supabase.co`

---

## Pre-flight: Run SQL in Supabase

Before executing any task, the user must run this SQL once in the Supabase dashboard (SQL Editor):

```sql
create table if not exists user_settings (
  user_id              uuid primary key references auth.users(id) on delete cascade,
  protocols            jsonb not null default '[]'::jsonb,
  active_protocol_key  text,
  active_protocol_data jsonb,
  updated_at           timestamptz not null default now()
);

alter table user_settings enable row level security;

create policy "Users manage own settings"
  on user_settings for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

This creates one row per user, protected by RLS. Tasks below can proceed immediately after this runs.

---

### Task 1: Hardcode anon key + auth cleanup + rename

**Files:**
- Rename: `index-v2.html` → `index.html`

**Interfaces:**
- Produces: `_supa` always initialised at page load (no key check); `supaSignIn()` no longer has a `!_supa` guard; settings screen has no anon key input

- [ ] **Step 1: Rename the file**

```bash
cd "/Users/larrycruz/Documents/Claude/Projects/HRT Project/v2/hrt-dashboard"
git mv index-v2.html index.html
```

- [ ] **Step 2: Hardcode the anon key constant**

Find line ~1615 in `index.html`:

```js
const SUPABASE_ANON_KEY = localStorage.getItem('supa_anon_key') || 'YOUR_SUPABASE_ANON_KEY';
```

Replace with:

```js
const SUPABASE_ANON_KEY = 'sb_publishable__lU8rYLjeTMoAgXANKsKKA_9Xgau8bm';
```

- [ ] **Step 3: Simplify `initSupa()`**

Find lines ~1635–1645:

```js
function initSupa() {
  const key = localStorage.getItem('supa_anon_key') || SUPABASE_ANON_KEY;
  if (key && key !== 'YOUR_SUPABASE_ANON_KEY' && window.supabase) {
    _supa = window.supabase.createClient(SUPABASE_URL, key);
    _initSupaAuth();
  } else {
    // Show app in demo mode if no key
    showApp();
    loadDemoData();
  }
}
```

Replace with:

```js
function initSupa() {
  if (window.supabase) {
    _supa = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    _initSupaAuth();
  }
}
```

- [ ] **Step 4: Fix `supaSignIn()` — remove dead guard, fix redirectTo**

Find lines ~1662–1666:

```js
async function supaSignIn() {
  if (!_supa) { alert('Please paste your Supabase Anon Key in Settings first.'); showApp(); loadDemoData(); return; }
  const { error } = await _supa.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.href } });
  if (error) { console.error('[auth] signIn failed:', error); alert('Sign-in failed: ' + error.message); }
}
```

Replace with:

```js
async function supaSignIn() {
  const { error } = await _supa.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } });
  if (error) { console.error('[auth] signIn failed:', error); alert('Sign-in failed: ' + error.message); }
}
```

- [ ] **Step 5: Remove `saveSupaKey()` function**

Find lines ~1672–1675:

```js
function saveSupaKey() {
  const key = document.getElementById('supa-key').value.trim();
  if (key.length > 20) { localStorage.setItem('supa_anon_key', key); initSupa(); }
}
```

Delete those 3 lines entirely.

- [ ] **Step 6: Remove the anon key input from settings HTML**

Find lines ~1542–1552 in the Settings section:

```html
        <div class="card-title">Supabase</div>
        <div class="form-group">
          <label class="form-label">Supabase URL</label>
          <input type="text" class="form-input" id="supa-url" value="https://lnxhksnvcewtpwkaghrh.supabase.co" readonly>
        </div>
        <div class="form-group">
          <label class="form-label">Anon Key</label>
          <input type="password" class="form-input" id="supa-key" placeholder="Paste your anon key here" oninput="saveSupaKey()">
        </div>
        <div style="font-size:11px;color:var(--text-muted);">Get your anon key from the Supabase dashboard → Settings → API.</div>
```

Replace with (keep the section title and URL for transparency, remove key input and helper):

```html
        <div class="card-title">Supabase</div>
        <div class="form-group">
          <label class="form-label">Supabase URL</label>
          <input type="text" class="form-input" id="supa-url" value="https://lnxhksnvcewtpwkaghrh.supabase.co" readonly>
        </div>
```

- [ ] **Step 7: Verify**

```bash
grep -n 'supa_anon_key\|YOUR_SUPABASE_ANON_KEY\|saveSupaKey\|supa-key' index.html
```

Expected output: no lines (all three references removed).

```bash
grep -n 'SUPABASE_ANON_KEY\|initSupa\|supaSignIn' index.html | head -10
```

Expected: `SUPABASE_ANON_KEY` declaration with hardcoded value; `initSupa` without `localStorage` reference; `supaSignIn` without `!_supa` guard.

- [ ] **Step 8: Smoke test**

Open `index.html` in a browser. Expected:
- Page loads without errors in console
- Auth overlay shows with "Sign in with Google" button
- Clicking the button initiates Google OAuth redirect (no "paste your key" alert)
- Settings screen shows only the URL field, no key input

- [ ] **Step 9: Commit**

```bash
git add index.html
git commit -m "feat: hardcode supabase anon key, simplify initSupa, fix google oauth redirect"
```

---

### Task 2: `syncProtocolsToSupabase()` + 3 call sites

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `_supa` (always initialised after Task 1), `_supaUser` (set by `_initSupaAuth`), `lsGet(key, fallback)`, `localStorage.getItem`
- Produces: `syncProtocolsToSupabase()` — async function, upserts `hrt_protocols` + `hrt_active_protocol` + `hrt_active_protocol_data` to `user_settings` table

- [ ] **Step 1: Add `syncProtocolsToSupabase()` after `loadUserData` closes**

Find the line after `loadUserData` closes (around line ~1699, just before `function updateUserUI`):

```js
  } catch (e) {
    console.error('[loadUserData] fatal:', e);
  }
}

function updateUserUI(user) {
```

Insert `syncProtocolsToSupabase` between the two functions:

```js
  } catch (e) {
    console.error('[loadUserData] fatal:', e);
  }
}

async function syncProtocolsToSupabase() {
  if (!_supa || !_supaUser) return;
  const { error } = await _supa.from('user_settings').upsert({
    user_id:              _supaUser.id,
    protocols:            lsGet('hrt_protocols', []),
    active_protocol_key:  localStorage.getItem('hrt_active_protocol') || null,
    active_protocol_data: lsGet('hrt_active_protocol_data', null),
    updated_at:           new Date().toISOString()
  }, { onConflict: 'user_id' });
  if (error) console.warn('[syncProtocols]', error.message);
}

function updateUserUI(user) {
```

- [ ] **Step 2: Wire into `_doSwitch` — call after localStorage writes**

Find the end of `_doSwitch` (~line 3164–3167):

```js
  renderCycleProgress(p);
  renderUpcoming();
  updateTopbarBadge();
}
```

Replace with:

```js
  renderCycleProgress(p);
  renderUpcoming();
  updateTopbarBadge();
  syncProtocolsToSupabase();
}
```

- [ ] **Step 3: Wire into `_pbDoSave` (builder save) — call after localStorage write**

Find the line in `_pbDoSave` where protocols are saved (~line 3307), then the lines that follow:

```js
  localStorage.setItem('hrt_protocols', JSON.stringify(saved));

  // Refresh active protocol if this one is active
  const active = localStorage.getItem('hrt_active_protocol');
  if (active === protocol.saved_at) {
    localStorage.setItem('hrt_active_protocol_data', JSON.stringify(protocol));
    renderUpcoming();
  }

  pbState.modificationLog = modLog;
  pbEditIndex = -1;
  return protocol;
}
```

Replace with:

```js
  localStorage.setItem('hrt_protocols', JSON.stringify(saved));

  // Refresh active protocol if this one is active
  const active = localStorage.getItem('hrt_active_protocol');
  if (active === protocol.saved_at) {
    localStorage.setItem('hrt_active_protocol_data', JSON.stringify(protocol));
    renderUpcoming();
  }

  syncProtocolsToSupabase();
  pbState.modificationLog = modLog;
  pbEditIndex = -1;
  return protocol;
}
```

- [ ] **Step 4: Wire into `deleteProtocol` — call after localStorage writes**

Find `deleteProtocol` (~line 3210–3221):

```js
function deleteProtocol(index) {
  const saved = lsGet('hrt_protocols', []);
  const p = saved[index];
  const active = localStorage.getItem('hrt_active_protocol');
  saved.splice(index, 1);
  localStorage.setItem('hrt_protocols', JSON.stringify(saved));
  if (active === p?.saved_at) {
    localStorage.removeItem('hrt_active_protocol');
    localStorage.removeItem('hrt_active_protocol_data');
  }
  renderProtocolsPage();
}
```

Replace with:

```js
function deleteProtocol(index) {
  const saved = lsGet('hrt_protocols', []);
  const p = saved[index];
  const active = localStorage.getItem('hrt_active_protocol');
  saved.splice(index, 1);
  localStorage.setItem('hrt_protocols', JSON.stringify(saved));
  if (active === p?.saved_at) {
    localStorage.removeItem('hrt_active_protocol');
    localStorage.removeItem('hrt_active_protocol_data');
  }
  syncProtocolsToSupabase();
  renderProtocolsPage();
}
```

- [ ] **Step 5: Verify call sites**

```bash
grep -n 'syncProtocolsToSupabase' index.html
```

Expected: 4 lines — the function definition, and 3 call sites (`_doSwitch`, `_pbDoSave`/`_pbDoSave`'s body, `deleteProtocol`).

- [ ] **Step 6: Smoke test**

Sign in with Google. Switch to a different protocol via the Protocols page. Open Supabase dashboard → Table Editor → `user_settings`. Confirm a row exists for your user with `active_protocol_key` and `protocols` populated. Then save an edited protocol in the builder — refresh the `user_settings` row and confirm `updated_at` changed.

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "feat: add syncProtocolsToSupabase, wire into _doSwitch, builder save, deleteProtocol"
```

---

### Task 3: `loadUserData()` additions — restore protocols + map vitals

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `_supa`, `_supaUser.id`, `window._weightHistory` (set by existing fetch), `syncProtocolsToSupabase()` from Task 2
- Produces: on sign-in, `hrt_protocols` / `hrt_active_protocol` / `hrt_active_protocol_data` / `hrt_vitals_log` are all populated from Supabase before charts render

- [ ] **Step 1: Add `user_settings` fetch + protocol restore to `loadUserData`**

Find the existing `loadUserData` body (~lines 1680–1699):

```js
async function loadUserData() {
  if (!_supa || !_supaUser) return;
  updateUserUI(_supaUser);
  const uid = _supaUser.id;
  try {
    const [logsRes, metricsRes] = await Promise.all([
      _supa.from('administration_log').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(50),
      _supa.from('daily_metrics').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(90)
    ]);
    if (logsRes.error) console.error('[loadUserData] logs query failed:', logsRes.error);
    if (metricsRes.error) console.error('[loadUserData] metrics query failed:', metricsRes.error);
    if (metricsRes.data?.length) renderMetrics(metricsRes.data);
    if (logsRes.data?.length) renderLastEntry(logsRes.data[0]);
    // Store for chart rendering
    window._weightHistory = metricsRes.data || [];
    setTimeout(renderRealCharts, 100);
  } catch (e) {
    console.error('[loadUserData] fatal:', e);
  }
}
```

Replace with:

```js
async function loadUserData() {
  if (!_supa || !_supaUser) return;
  updateUserUI(_supaUser);
  const uid = _supaUser.id;
  try {
    const [logsRes, metricsRes, settingsRes] = await Promise.all([
      _supa.from('administration_log').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(50),
      _supa.from('daily_metrics').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(90),
      _supa.from('user_settings').select('*').eq('user_id', uid).maybeSingle()
    ]);
    if (logsRes.error) console.error('[loadUserData] logs query failed:', logsRes.error);
    if (metricsRes.error) console.error('[loadUserData] metrics query failed:', metricsRes.error);
    if (settingsRes.error) console.error('[loadUserData] settings query failed:', settingsRes.error);

    // Restore protocol state from Supabase (Supabase wins on load)
    const settings = settingsRes.data;
    if (settings) {
      if (Array.isArray(settings.protocols) && settings.protocols.length)
        localStorage.setItem('hrt_protocols', JSON.stringify(settings.protocols));
      if (settings.active_protocol_key)
        localStorage.setItem('hrt_active_protocol', settings.active_protocol_key);
      if (settings.active_protocol_data)
        localStorage.setItem('hrt_active_protocol_data', JSON.stringify(settings.active_protocol_data));
    }

    if (metricsRes.data?.length) renderMetrics(metricsRes.data);
    if (logsRes.data?.length) renderLastEntry(logsRes.data[0]);

    // Store for chart rendering and map to hrt_vitals_log
    window._weightHistory = metricsRes.data || [];
    if (window._weightHistory.length) {
      const vitals = window._weightHistory
        .map(r => ({
          date:    r.date,
          weight:  r.weight   ?? null,
          bodyFat: r.body_fat ?? null,
          mood:    r.mood     ?? null,
          energy:  r.energy   ?? null,
          notes:   r.notes    ?? null
        }))
        .filter(r => r.weight !== null || r.bodyFat !== null ||
                     r.mood   !== null || r.energy  !== null);
      localStorage.setItem('hrt_vitals_log', JSON.stringify(vitals));
    }

    setTimeout(renderRealCharts, 100);
  } catch (e) {
    console.error('[loadUserData] fatal:', e);
  }
}
```

Note: `.maybeSingle()` returns `null` data (not an error) when no row exists — this is correct first-login behaviour.

- [ ] **Step 2: Verify**

```bash
grep -n 'user_settings\|maybeSingle\|hrt_vitals_log\|body_fat' index.html
```

Expected: `user_settings` appears in `loadUserData`; `maybeSingle` appears once; `hrt_vitals_log` appears in the vitals mapping block; `body_fat` appears in the map.

- [ ] **Step 3: Smoke test — new device simulation**

1. Open `index.html` in a private/incognito window (clean localStorage)
2. Sign in with Google
3. Open browser DevTools → Application → localStorage
4. Confirm `hrt_protocols`, `hrt_active_protocol`, and `hrt_active_protocol_data` are populated (matching what's in Supabase `user_settings`)
5. Confirm `hrt_vitals_log` is populated (matching Supabase `daily_metrics`)
6. Confirm the dashboard renders: Dose Schedule card shows correct protocol, weight/mood/energy charts render

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: restore protocols from user_settings and map daily_metrics to hrt_vitals_log on load"
```

---

## Post-sprint: Before deploying to Cloudflare

Add your Cloudflare domain to Supabase Authentication → URL Configuration:
- **Site URL**: `https://yourdomain.com`
- **Redirect URLs**: `https://yourdomain.com` and `http://localhost:*`

Without this, Google sign-in redirects fail after deploy.
