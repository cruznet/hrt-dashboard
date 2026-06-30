# Funnel & Retention Analytics

Events are written by the Cloudflare Worker's `POST /api/track` endpoint into
the `analytics_events` table (see `supabase-schema.sql`, section 6). The table
is not reachable by the browser's anon key — only the Worker's service role
can read/write it. Run these queries directly in the Supabase SQL editor.

## Events tracked

| event_name            | Fired from              | When |
|------------------------|--------------------------|------|
| `landing_view`          | landing.html             | Every page load |
| `cta_click`              | landing.html              | Click on any "Sign In"/"Get Started"/"Start Tracking Free"/"Join Waitlist" button. `properties.cta_id` identifies which one (`nav-signin`, `nav-getstarted`, `mobile-nav-signin`, `mobile-nav-getstarted`, `hero-start`, `pricing-free`, `pricing-waitlist`, `banner-start`) |
| `auth_complete`         | index.html                | A real Google sign-in (not a session restore) — gated on Supabase's `onAuthStateChange` event being `SIGNED_IN` |
| `onboarding_complete`   | index.html                | User finishes the onboarding flow. `properties.mode` is `trt` / `offseason` / `performance` |
| `first_log`              | index.html                | The user's first dose check, vitals entry, or weekly check-in — fired once per browser via a `hrt_first_log_tracked` localStorage flag. `properties.log_type` is `dose` / `vitals` / `checkin` |

Pre-signup events (`landing_view`, `cta_click`) only have `anon_id` (a UUID
stored in `localStorage.hrt_anon_id`, shared across `landing.html` and
`index.html` since they're same-origin). Post-signup events also carry
`user_id`. Join on `anon_id` to connect a user's pre- and post-signup
behavior, keeping in mind `anon_id` is per-browser, not per-person.

## Top-of-funnel: landing → CTA click

```sql
select
  count(*) filter (where event_name = 'landing_view') as landing_views,
  count(*) filter (where event_name = 'cta_click')     as cta_clicks
from analytics_events
where created_at > now() - interval '30 days';
```

## CTA click-through by button

```sql
select
  properties->>'cta_id' as cta_id,
  count(*)              as clicks
from analytics_events
where event_name = 'cta_click'
  and created_at > now() - interval '30 days'
group by 1
order by 2 desc;
```

## Signup → onboarding → first log (conversion funnel)

```sql
with funnel as (
  select
    user_id,
    min(created_at) filter (where event_name = 'auth_complete')       as signed_up_at,
    min(created_at) filter (where event_name = 'onboarding_complete') as onboarded_at,
    min(created_at) filter (where event_name = 'first_log')           as first_log_at
  from analytics_events
  where user_id is not null
  group by user_id
)
select
  count(*)                                 as signups,
  count(onboarded_at)                      as onboarded,
  count(first_log_at)                      as logged,
  round(count(onboarded_at)::numeric / nullif(count(*), 0) * 100, 1)        as pct_onboarded,
  round(count(first_log_at)::numeric / nullif(count(onboarded_at), 0) * 100, 1) as pct_onboarded_to_logged
from funnel;
```

## Day-7 retention

There's no client-side "day 7" event — it's computed by checking whether a
user logged any activity 6-8 days after signup. `administration_log`,
`daily_logs`, and `weekly_checkins` are better retention signals than
`analytics_events` since they capture ongoing usage, not just the funnel
events above.

```sql
with signups as (
  select user_id, min(created_at) as signed_up_at
  from analytics_events
  where event_name = 'auth_complete'
  group by user_id
),
activity as (
  select user_id, date as activity_date from administration_log
  union
  select user_id, date as activity_date from daily_logs
  union
  select user_id, check_in_date as activity_date from weekly_checkins
)
select
  count(distinct s.user_id) as signups,
  count(distinct a.user_id) as retained_day7
from signups s
left join activity a
  on a.user_id = s.user_id
  and a.activity_date between (s.signed_up_at::date + 6) and (s.signed_up_at::date + 8)
where s.signed_up_at < now() - interval '8 days';
```

## Notes for whoever runs these

- All queries are read-only and safe to run ad hoc in the SQL editor.
- `properties` is `jsonb` — use `->>'key'` for text extraction, `->` for nested objects.
- If a query needs to run regularly (e.g. a weekly funnel report), consider
  wrapping it in a Postgres view rather than re-pasting it each time.
