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
        → GET {HEVY_BASE}/workouts        (paginate to 50, same cap as client hevySync())
        → GET {HEVY_BASE}/body_measurements (paginate all, same dedup as client hevyMeasSync())
        → merge measurements into existing physique_measurements (existing values win over Hevy)
        → UPSERT user_settings: hevy_workouts_cache, physique_measurements, hevy_cron_synced_at
    → log per-user failures (console.error, visible via `wrangler tail`) and continue
```

The Worker already has a `SUPABASE_SERVICE_KEY` secret configured (used today by `/api/track` and `/api/account` in `worker.js`) — no new secret needed.

A cron job isn't authenticated as any single user, so it must use the service-role key to read across all rows (RLS normally restricts each user to their own row).

---

## Data Model Changes

New columns on `user_settings` (`supabase-schema.sql`, same migration pattern as the existing `goals jsonb DEFAULT '[]'` column):

```sql
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_workouts_cache jsonb DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS hevy_cron_synced_at timestamptz;
```

- `hevy_workouts_cache` — full replace each run with the cron's freshly fetched workout list (mirrors what `hevySync()` stores in `hrt_hevy_workouts` localStorage today).
- `hevy_cron_synced_at` — last successful cron sync time for this user. Separate from the client's own `hrt_hevy_synced` localStorage timestamp; exists purely for observability (confirming the background job is actually running), not read by any client logic.

`physique_measurements` already exists and already syncs to the client — no schema change needed for measurements, just a new writer (the cron) in addition to the existing client writer.

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
1. `GET {SUPABASE_URL}/rest/v1/user_settings?select=user_id,hevy_api_key,physique_measurements&hevy_api_key=not.is.null` with the service-role key.
2. For each row, sequentially (no concurrency — user count is small, and this avoids hammering Hevy's API):
   - Fetch workouts (reuse the same pagination shape as client `hevySync()`: page through `pageSize=10` until 50 workouts collected or pages exhausted).
   - Fetch body measurements (page through until exhausted, same as client `hevyMeasSync()`).
   - Dedup body measurements by date (most non-null fields wins), convert `weight_kg` → lbs, merge into that user's existing `physique_measurements` array with existing (manual) values taking priority over Hevy-sourced values for the same date — this is a direct port of the merge logic in `hevyMeasSync()` (index.html ~line 7905-7941).
   - `PATCH`/upsert that user's `user_settings` row with `hevy_workouts_cache`, updated `physique_measurements`, and `hevy_cron_synced_at = now()`.
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

In `loadUserData()`, alongside the existing "Supabase wins on load" block (~line 3993-4032), add:

```js
if (Array.isArray(settings.hevy_workouts_cache) && settings.hevy_workouts_cache.length)
  localStorage.setItem(HEVY_DATA_LS, JSON.stringify(settings.hevy_workouts_cache));
```

No timestamp comparison — consistent with how every other synced field (`protocols`, `bloodwork_panels`, `goals`, etc.) already works in this function. `physique_measurements` handling needs no change; the cron writes to the same column the client already reads.

**Why this doesn't clobber fresher client data:** `syncProtocolsToSupabase()` (the client's own upsert function) never includes `hevy_workouts_cache` in its payload. PostgREST upserts only set columns present in the request body, so client-triggered saves (e.g. editing a protocol) leave `hevy_workouts_cache` untouched.

---

## Error Handling

- Per-user try/catch in the cron loop — a revoked/invalid Hevy key or a transient Hevy API error for one user is logged and skipped; the run continues for remaining users.
- No retry logic.
- No client-facing error state (e.g. a "last sync failed" banner) in this iteration — out of scope, not requested.
- Failures are visible via Cloudflare Worker logs (`wrangler tail` or dashboard), same observability level as the existing `/api/track` and `/api/healthkit` error paths.

---

## Testing Strategy

- Local: `wrangler dev --test-scheduled`, then trigger via `/__scheduled` to exercise `scheduled()` against a real (test) user's Hevy key and Supabase row before relying on the live daily trigger.
- Verify: after a manual test run, confirm `hevy_workouts_cache` and `hevy_cron_synced_at` are populated in Supabase, and that a fresh `loadUserData()` call (e.g. new browser session, cleared localStorage) seeds `hrt_hevy_workouts` from the cache and goals with a `lift` source render a value without visiting the Workouts tab.

---

## Out of Scope

- Client-visible sync-failure UI (e.g. a banner if the cron failed for a user).
- Retry/backoff logic for failed per-user syncs.
- Changing or removing the existing manual "Sync" button or 2h/6h open-app auto-sync — both remain exactly as they are today.
- Concurrency/queueing for the per-user cron loop — current user count doesn't warrant it.
