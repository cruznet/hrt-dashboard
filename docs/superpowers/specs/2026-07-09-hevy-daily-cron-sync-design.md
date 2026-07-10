# Hevy Daily Background Sync — Design Spec

**Date:** 2026-07-09
**Status:** Approved

---

## Goal

Today, Hevy data (workouts/PRs and body measurements) only refreshes when a user opens the Workouts or Physique tab, gated by a 2h/6h staleness check. If a user hasn't opened the app, or opens it on a fresh device/session, PR-based and bodyweight-based Goals show stale or empty (`—`) values until they visit the right tab.

Add a Cloudflare Worker Cron Trigger that syncs every user's Hevy data server-side once a day, independent of whether they open the app. The existing client-triggered sync paths (manual "Sync" button, open-app 2h/6h auto-sync) are unchanged — this is an additional background layer, not a replacement.

---

## Architecture & Data Flow

```
Cloudflare Cron Trigger (daily, 09:00 UTC)
  → worker.js `scheduled()` handler
    → SELECT user_settings WHERE hevy_api_key IS NOT NULL   (service-role key, bypasses RLS)
    → for each user (sequential, one failure doesn't block others):
        → GET {HEVY_BASE}/workouts             (paginate to 50, same cap as client hevySync())
        → GET {HEVY_BASE}/body_measurements    (paginate all — raw, no dedup/merge server-side)
        → UPSERT user_settings: hevy_workouts_cache, hevy_measurements_raw_cache, hevy_cron_synced_at
    → log per-user failures (console.error, visible via `wrangler tail`) and continue
```

The Worker already has a `SUPABASE_SERVICE_KEY` secret configured (used today by `/api/track` and `/api/account` in `worker.js`) — no new secret needed.

A cron job isn't authenticated as any single user, so it must use the service-role key to read across all rows (RLS normally restricts each user to their own row).

**Why the Worker doesn't merge measurements itself:** the client's existing dedup/merge logic (in `hevyMeasSync()`) buckets each Hevy measurement by *local calendar date* via `localDate(new Date(...))`, which reads the **browser's** timezone (`getFullYear()/getMonth()/getDate()`) — this is exactly the fix shipped in the most recent commit (`efd4935`, "use local calendar date instead of UTC, fixing early day rollover"). A Cloudflare Worker has no browser timezone to read; if it did the date bucketing itself (e.g. via UTC), it would silently reintroduce that same rollover bug for any user not in UTC. So the Worker only caches Hevy's **raw** `body_measurements` response — the same shape `hevyMeasSync()` already fetches and processes today — and the client runs its existing, already-correct, timezone-aware merge logic against that cached raw data. Workouts aren't affected by this: the client already re-derives the PR map fresh from raw workout data on every render (`hevyBuildPRMap()`), so caching the raw workouts array server-side, as below, is safe as originally designed.

---

## Data Model Changes

New columns on `user_settings` (`supabase-schema.sql`, same migration pattern as the existing `goals jsonb DEFAULT '[]'` column):

```sql
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_workouts_cache jsonb DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_measurements_raw_cache jsonb DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_cron_synced_at timestamptz;
```

- `hevy_workouts_cache` — full replace each run with the cron's freshly fetched workout list (mirrors what `hevySync()` stores in `hrt_hevy_workouts` localStorage today).
- `hevy_measurements_raw_cache` — full replace each run with Hevy's **raw** `body_measurements` API response (unprocessed — no dedup, no unit conversion, no date bucketing). The client merges this into `physique_measurements` itself, reusing its existing local-timezone-aware logic.
- `hevy_cron_synced_at` — last successful cron sync time for this user. Separate from the client's own `hrt_hevy_synced` localStorage timestamp; exists purely for observability (confirming the background job is actually running), not read by any client logic.

`physique_measurements` already exists and already syncs to the client — no schema change needed there; the client is what writes the merged result into it (same as today), just now also triggered by cached raw cron data in addition to a live Hevy fetch.

---

## Worker Changes (`worker.js`)

Add a `scheduled(event, env, ctx)` export alongside the existing `fetch()` export.

```js
export default {
  async fetch(request, env) { /* existing, unchanged */ },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runHevyDailySync(env));
  },
};
```

`runHevyDailySync(env)`:
1. `GET {SUPABASE_URL}/rest/v1/user_settings?select=user_id,hevy_api_key&hevy_api_key=not.is.null` with the service-role key.
2. For each row, sequentially (no concurrency — user count is small, and this avoids hammering Hevy's API):
   - Fetch workouts (reuse the same pagination shape as client `hevySync()`: page through `pageSize=10` until 50 workouts collected or pages exhausted).
   - Fetch body measurements (page through until exhausted, same as client `hevyMeasSync()`) — kept as the **raw** array Hevy returns, no processing.
   - `PATCH`/upsert that user's `user_settings` row with `hevy_workouts_cache`, `hevy_measurements_raw_cache`, and `hevy_cron_synced_at = now()`.
   - Wrap each user's work in try/catch; on error, `console.error` and continue to the next user. No retries.

### wrangler.jsonc

```jsonc
"triggers": {
  "crons": ["0 9 * * *"]
}
```

Once daily at 09:00 UTC. Arbitrary but reasonable off-peak choice; trivially changeable later.

---

## Client Changes (`index.html`)

**Workouts** — in `loadUserData()`, alongside the existing "Supabase wins on load" block (~line 3993-4032), add:

```js
if (Array.isArray(settings.hevy_workouts_cache) && settings.hevy_workouts_cache.length)
  localStorage.setItem(HEVY_DATA_LS, JSON.stringify(settings.hevy_workouts_cache));
```

No timestamp comparison — consistent with how every other synced field (`protocols`, `bloodwork_panels`, `goals`, etc.) already works in this function.

**Measurements** — extract the merge/dedup body out of `hevyMeasSync()` (index.html ~line 7905-7941) into a standalone function, e.g. `hevyMergeRawMeasurements(rawEntries)`, that takes Hevy's raw `body_measurements` array and applies it to `measLoad()` + `measSaveAll()` exactly as the live-fetch path does today (dedup by date, most-non-null-fields wins, existing manual values always take priority, `weight_kg` → lbs conversion, uses the browser's own `localDate()`). Both `hevyMeasSync()` (live fetch) and the new load-time path call this same function, so there's one merge implementation, not two.

In `loadUserData()`, after restoring `physique_measurements` from Supabase, call it against the cached raw data:

```js
if (Array.isArray(settings.hevy_measurements_raw_cache) && settings.hevy_measurements_raw_cache.length)
  hevyMergeRawMeasurements(settings.hevy_measurements_raw_cache);
```

This is safe to run on every load: the merge is keyed by date and idempotent for unchanged data, and existing manual values always win, so re-applying the same cached data repeatedly never creates duplicates or overwrites manual entries.

**Why this doesn't clobber fresher client data:** `syncProtocolsToSupabase()` (the client's own upsert function) never includes `hevy_workouts_cache` or `hevy_measurements_raw_cache` in its payload. PostgREST upserts only set columns present in the request body, so client-triggered saves (e.g. editing a protocol) leave both columns untouched.

---

## Error Handling

- Per-user try/catch in the cron loop — a revoked/invalid Hevy key or a transient Hevy API error for one user is logged and skipped; the run continues for remaining users.
- No retry logic.
- No client-facing error state (e.g. a "last sync failed" banner) in this iteration — out of scope, not requested.
- Failures are visible via Cloudflare Worker logs (`wrangler tail` or dashboard), same observability level as the existing `/api/track` and `/api/healthkit` error paths.

---

## Testing Strategy

- `hevyMergeRawMeasurements()` is pure enough (given an array of measurement records) to unit test directly, independent of the cron or Supabase.
- Local: `wrangler dev --test-scheduled`, then trigger via `/__scheduled` to exercise `scheduled()` against a real (test) user's Hevy key and Supabase row before relying on the live daily trigger.
- Verify: after a manual test run, confirm `hevy_workouts_cache`, `hevy_measurements_raw_cache`, and `hevy_cron_synced_at` are populated in Supabase, and that a fresh `loadUserData()` call (e.g. new browser session, cleared localStorage) seeds `hrt_hevy_workouts` from the cache, merges cached measurements into `physique_measurements`, and goals with a `lift` or `weight`/`bodyfat` source render a value without visiting the Workouts/Physique tab.

---

## Out of Scope

- Client-visible sync-failure UI (e.g. a banner if the cron failed for a user).
- Retry/backoff logic for failed per-user syncs.
- Changing or removing the existing manual "Sync" button or 2h/6h open-app auto-sync — both remain exactly as they are today.
- Concurrency/queueing for the per-user cron loop — current user count doesn't warrant it.
