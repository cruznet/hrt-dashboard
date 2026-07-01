# Pre-Deploy Checklist (manual, ~60-90 seconds)

`tests/smoke-test.js` only covers what's reachable without a real login —
Google OAuth can't be automated here. Run through this by hand before every
deploy. Open the browser console and keep an eye on it throughout.

1. **Run the automated smoke test first** — see header of `tests/smoke-test.js`
   for the command. Don't proceed to the manual steps below until it passes.
2. **Login** — go to `index.html`, sign in with Google. Confirm it lands on
   the dashboard (not stuck on the auth overlay).
3. **Dashboard renders** — readiness score, streak card, mode context card,
   and check-in card all show data (not blank/broken).
4. **Log a dose** — tap a scheduled dose, confirm it shows as taken and the
   adherence badge updates.
5. **Log vitals** — open the log form, submit a BP/glucose/mood entry,
   confirm it saves and shows in "last vitals entry."
6. **Bloodwork page** — navigate there, confirm markers render with no
   layout breakage.
7. **Protocols page** — navigate there, confirm the protocol list (or empty
   state) renders correctly.
8. **Settings page** — navigate there, confirm it opens without errors.
9. **Timeline page** — navigate there, confirm the activity feed (or empty
   state) renders with no layout breakage; confirm the Dashboard's "Recent
   Activity" card matches its most recent entries.
10. **Goals card** — on Dashboard, add a goal via each source type (Manual,
    Bodyweight, Lift PR, Lab Marker); confirm progress bar and current value
    render, then delete one to confirm it removes cleanly.
11. **Console check** — confirm no red errors logged during steps 2-10.

If anything fails, stop and fix before deploying — don't ship on top of a
broken auth-gated path.
