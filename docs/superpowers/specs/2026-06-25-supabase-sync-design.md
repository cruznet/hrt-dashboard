# Supabase Sync + Google OAuth — Design Spec
_2026-06-25_

## Overview

Three gaps prevent multi-device use: (1) the anon key requires manual paste each session, (2) there is no persistent sign-in (email/password only, no Google), and (3) protocol data lives only in localStorage and is never synced. This sprint closes all three gaps and renames the entry file to `index.html` for Cloudflare Pages deployment.

---

## 1. Rename Entry File

`index-v2.html` → `index.html`. No other file changes from this rename. Git rename preserves history.

---

## 2. Hardcode Anon Key

The Supabase anon key is a public key by design — it is safe and intended to appear in client-side code. RLS policies are the actual security boundary.

### Current code (two locations)

```js
const SUPABASE_ANON_KEY = localStorage.getItem('supa_anon_key') || 'YOUR_SUPABASE_ANON_KEY';
// ...
const key = localStorage.getItem('supa_anon_key') || SUPABASE_ANON_KEY;
if (key && key !== 'YOUR_SUPABASE_ANON_KEY' && window.supabase) {
  _supa = window.supabase.createClient(SUPABASE_URL, key);
}
```

### After

```js
const SUPABASE_ANON_KEY = 'sb_publishable__lU8rYLjeTMoAgXANKsKKA_9Xgau8bm';
// ...
if (window.supabase) {
  _supa = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}
```

`_supa` is always initialised — no key-presence check needed.

### Settings screen cleanup

The `#supa-key` password input, its label, and its save button are removed from the settings screen. No other settings UI changes.

---

## 3. Google OAuth

### Sign-in flow

A **"Continue with Google"** button is added to the existing auth overlay, above the email/password form. Clicking it calls:

```js
async function signInWithGoogle() {
  const { error } = await _supa.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: window.location.origin }
  });
  if (error) showAuthError(error.message);
}
```

`window.location.origin` adapts automatically — `http://localhost:PORT` locally and the Cloudflare domain in production.

The existing `onAuthStateChange` listener already handles the post-Google-redirect session. No other auth wiring is needed.

### One-time Supabase setup (already done)

Google provider is enabled in Supabase Authentication → Providers with Client ID and Client Secret. ✅

### One-time Supabase URL config (must do before deploy)

In Supabase Authentication → URL Configuration:
- **Site URL**: `https://yourdomain.com` (your Cloudflare domain)
- **Redirect URLs**: add `https://yourdomain.com` and `http://localhost:*` (for local dev)

Without this, Google sign-in redirects will fail after deploy.

### Button style

```html
<button onclick="signInWithGoogle()"
  style="width:100%;padding:10px;margin-bottom:12px;border:1px solid var(--border);
         border-radius:6px;background:var(--bg-card);color:var(--text-primary);
         cursor:pointer;font-size:14px;display:flex;align-items:center;
         justify-content:center;gap:8px;">
  <svg width="18" height="18" viewBox="0 0 18 18"><!-- Google G SVG --></svg>
  Continue with Google
</button>
```

Email/password form stays as a secondary option below.

---

## 4. `user_settings` Table

### SQL (user runs once in Supabase SQL Editor)

```sql
create table if not exists user_settings (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  protocols        jsonb not null default '[]'::jsonb,
  active_protocol_key  text,
  active_protocol_data jsonb,
  updated_at       timestamptz not null default now()
);

alter table user_settings enable row level security;

create policy "Users manage own settings"
  on user_settings for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

One row per user. Columns map directly to the three localStorage keys that hold protocol state.

---

## 5. `syncProtocolsToSupabase()`

New helper. Called whenever protocol state changes locally. Upserts the current localStorage protocol state to `user_settings`.

```js
async function syncProtocolsToSupabase() {
  if (!_supa || !_user) return;
  const { error } = await _supa.from('user_settings').upsert({
    user_id:             _user.id,
    protocols:           lsGet('hrt_protocols', []),
    active_protocol_key: localStorage.getItem('hrt_active_protocol') || null,
    active_protocol_data: lsGet('hrt_active_protocol_data', null),
    updated_at:          new Date().toISOString()
  }, { onConflict: 'user_id' });
  if (error) console.warn('syncProtocols:', error.message);
}
```

**Call sites (3):**

| Location | When to call |
|---|---|
| `_doSwitch(key)` (~line 3144) | After updating localStorage active protocol |
| Protocol builder save (~line 3307) | After writing new/edited protocol to localStorage |
| Protocol delete (~line 3215) | After removing protocol from localStorage |

Each call is fire-and-forget (`syncProtocolsToSupabase()` with no await at the call site) — UI never blocks on sync.

---

## 6. `loadUserData()` Additions

After the existing `administration_log` + `daily_metrics` parallel fetch, add two more actions:

### 6a. Restore protocols from `user_settings`

```js
const { data: settings } = await _supa
  .from('user_settings')
  .select('*')
  .eq('user_id', _user.id)
  .single();

if (settings) {
  if (Array.isArray(settings.protocols) && settings.protocols.length)
    localStorage.setItem('hrt_protocols', JSON.stringify(settings.protocols));
  if (settings.active_protocol_key)
    localStorage.setItem('hrt_active_protocol', settings.active_protocol_key);
  if (settings.active_protocol_data)
    localStorage.setItem('hrt_active_protocol_data', JSON.stringify(settings.active_protocol_data));
}
```

**First-login behaviour:** if no `user_settings` row exists, `settings` is null and the block is skipped. The app starts with whatever is (or isn't) in localStorage — no error.

**Conflict resolution:** Supabase always wins on load. This is intentional — the device that last synced is the source of truth.

### 6b. Map `daily_metrics` → `hrt_vitals_log`

After `window._weightHistory` is populated:

```js
if (window._weightHistory?.length) {
  const vitals = window._weightHistory
    .map(r => ({
      date:     r.date,
      weight:   r.weight   ?? null,
      bodyFat:  r.body_fat ?? null,
      mood:     r.mood     ?? null,
      energy:   r.energy   ?? null,
      notes:    r.notes    ?? null
    }))
    .filter(r => r.weight !== null || r.bodyFat !== null ||
                 r.mood   !== null || r.energy  !== null);
  localStorage.setItem('hrt_vitals_log', JSON.stringify(vitals));
}
```

This makes the existing localStorage-path charts (`renderVitalsToCards`, `renderMoodEnergyCharts`) work correctly after a Supabase load without any further changes to those functions.

---

## 7. Scope and Constraints

- All code changes confined to `index.html` (renamed from `index-v2.html`)
- No new files, no new CSS, no new localStorage keys
- `syncProtocolsToSupabase` is fire-and-forget — never blocks UI
- `loadUserData` additions run after existing fetches — no change to existing fetch logic
- No changes to any other screen (Vitals, Log Entry, Calculator, Compounds, Builder)
- Existing email/password auth is preserved — Google is additive
- `escHtml` already covers all user-supplied strings rendered to innerHTML — no new XSS surface
- No admin panel, no user management, no multi-user features

---

## 8. What Is NOT in Scope

- Push/real-time sync between devices (page load only)
- Conflict resolution beyond "Supabase wins on load"
- Syncing `administration_log` writes (already synced via existing `logAdministration`)
- Cloudflare Pages CI/CD setup (manual deploy for now)
- Email verification or password reset flow
- Removing email/password sign-in
