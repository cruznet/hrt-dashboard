# Injection Site Rotation for Protocol Builder — Design Spec

**Date:** 2026-07-15  
**Status:** Approved

---

## Goal

Enable athletes to track and rotate injection sites throughout a protocol cycle to minimize scar tissue, infection risk, and site degradation. The system should support:
- Protocol-level site rotation (shared by most compounds)
- Per-compound custom rotations (e.g., TNE pre-workout gets its own sites)
- Multiple compounds injecting into the same site on the same day (e.g., test + primo in same syringe)
- Visibility across protocol builder and dashboard

---

## Site List

14 predefined anatomical injection sites (left/right pairs):

```
1. Left Ventrogluteal (Hip)
2. Right Ventrogluteal (Hip)
3. Left Dorsogluteal (Upper Outer Glute)
4. Right Dorsogluteal (Upper Outer Glute)
5. Left Vastus Lateralis (Outer Thigh)
6. Right Vastus Lateralis (Outer Thigh)
7. Left Deltoid (Shoulder)
8. Right Deltoid (Shoulder)
9. Left Pectoral (Chest)
10. Right Pectoral (Chest)
11. Left Triceps (Back of Arm)
12. Right Triceps (Back of Arm)
13. Left Biceps (Front of Arm)
14. Right Biceps (Front of Arm)
```

Stored as a constant `INJECTION_SITES` array in index.html.

---

## Data Model

### Protocol Level

```javascript
{
  name: "Summer Bulk 2025",
  injectionSites: [
    "Left Ventrogluteal (Hip)",
    "Right Ventrogluteal (Hip)",
    "Left Dorsogluteal (Upper Outer Glute)",
    "Right Dorsogluteal (Upper Outer Glute)"
  ],
  // ... other protocol fields
}
```

- `injectionSites` — array of 2+ selected sites; rotation cycles through these in order based on day of week
- User selects during protocol setup/editing

### Compound Level

```javascript
{
  name: "Testosterone Enanthate",
  unit: "mg",
  freq: "E3.5D",
  phases: [{ startWeek: 1, endWeek: 16, dose: 500 }],
  customInjectionSites: [
    "Left Deltoid (Shoulder)",
    "Right Deltoid (Shoulder)"
  ],
  // ... other compound fields
}
```

- `customInjectionSites` (optional) — if set, this compound uses its own rotation instead of the protocol's
- Omitted/null = compound uses protocol's `injectionSites`

---

## Rotation Logic

**Principle:** Calendar-based, day-of-week indexed.

**Calculate assigned site for a dose:**

```javascript
function getSiteForDose(doseDate, sites) {
  const dayOfWeek = new Date(doseDate).getDay(); // 0=Sunday, 1=Monday, ..., 6=Saturday
  const siteIndex = dayOfWeek % sites.length;
  return sites[siteIndex];
}
```

**Example (4-site rotation):**
- Sites: `[Left VG, Right VG, Left Dorsal, Right Dorsal]`
- Sunday (day 0) → 0 % 4 = 0 → Left VG
- Monday (day 1) → 1 % 4 = 1 → Right VG
- Wednesday (day 3) → 3 % 4 = 3 → Right Dorsal
- Friday (day 5) → 5 % 4 = 1 → Right VG
- (repeats next week with same day-of-week mapping)

**Key properties:**
- Deterministic — same day of week always gets the same site
- Works with any frequency (ED, EOD, Weekly, E3.5D, etc.)
- Multiple compounds on the same day automatically get the same site (test + primo together = same site)
- Custom compound rotations are independent (TNE on Monday uses Left Deltoid even if protocol uses Left VG)

---

## UI: Protocol Builder

### Adding/Editing a Compound

Extend the existing compound form:

```
[Existing fields: Compound, Unit, Frequency, Start Week, End Week, Dose]

☐ Custom injection site rotation
  (unchecked by default)

[If checked, show:]
Select injection sites (minimum 2):
[Multiselect dropdown from INJECTION_SITES]
Current selection: Left Deltoid, Right Deltoid
```

**Behavior:**
- Checkbox is unchecked by default → compound uses protocol sites
- Check it → multiselect dropdown appears
- User selects 2+ sites
- Saved to `compound.customInjectionSites`
- Can be edited anytime by re-opening the compound

### Compounds List (Protocol View)

Each compound card displays:

```
Testosterone Enanthate | E3.5D
Rotation: Left VG → Right VG → Left Dorsal → Right Dorsal
[+ Phase] [Remove]

TNE | ED
Rotation: Left Deltoid → Right Deltoid (custom)
[+ Phase] [Remove]
```

Display format: `Site1 → Site2 → Site3 → ...` (cycle indicator)

### Timeline Tab (Week-by-Week View)

Extend existing timeline to show assigned site for each compound each week:

```
Week 1
           Monday              Wednesday            Friday
Test E     500mg Left VG       500mg Right Dorsal   500mg Left VG
Primo      600mg Left VG       600mg Right Dorsal   600mg Left VG
TNE        50mg Left Deltoid   —                    50mg Left Deltoid
```

Calculate site for each frequency occurrence during that week, display next to dose.

---

## UI: Dashboard Dose Log

When rendering today's/upcoming doses on the dashboard, display the assigned site:

```
Active Protocol: Summer Bulk 2025

Today's Doses:
☑ Testosterone Enanthate 500mg (Right Ventrogluteal) — Taken at 2:34 PM
☑ Primobolan 600mg (Right Ventrogluteal) — Taken at 2:34 PM
☐ TNE 50mg (Left Deltoid)

Upcoming:
Wed: Test E 500mg (Right Dorsal) + Primo 600mg (Right Dorsal)
Fri: Test E 500mg (Left VG) + Primo 600mg (Left VG)
```

When a user checks off a dose, the site is recorded alongside the dose log entry (same as other dose metadata).

---

## Manual Override

**Scenario:** User wants to skip a site one day (e.g., bruised deltoid, site irritation).

**UI:**
1. User clicks a dose in the protocol view or dashboard
2. A modal appears: "Override injection site for this dose only?"
3. Dropdown shows current assigned site + all 14 options
4. User selects a different site, clicks Save
5. Override applies only to that specific date; next week resumes normal rotation

**Data:**
Store as a per-date override in a protocol-level map:
```javascript
protocol.injectionSiteOverrides = {
  "2025-07-21": { // Monday, overriding Left VG → Right Deltoid
    "Testosterone Enanthate": "Right Deltoid (Shoulder)",
    "Primobolan": "Right Deltoid (Shoulder)" // or null if not overridden
  }
}
```

Check overrides before calculating site:
```javascript
function getSiteForDose(doseDate, compoundName, sites) {
  const dateKey = formatDate(doseDate); // "YYYY-MM-DD"
  if (protocol.injectionSiteOverrides?.[dateKey]?.[compoundName]) {
    return protocol.injectionSiteOverrides[dateKey][compoundName];
  }
  return getSiteForDose(doseDate, sites); // normal rotation
}
```

---

## Storage & Persistence

- `protocol.injectionSites` — saved to Supabase `protocols` table as part of protocol JSON
- `compound.customInjectionSites` — saved within the protocol's compounds array
- `protocol.injectionSiteOverrides` — saved to Supabase alongside other protocol metadata

No schema changes required; stored as JSON within existing protocol records.

---

## Testing Strategy

**Unit tests (pure functions):**
- `getSiteForDose(date, sites)` — verify day-of-week indexing
- Rotation cycles correctly across weeks
- 2-site, 4-site, 6-site rotations all work
- Override logic returns correct site when override exists, falls back to rotation when not

**Integration tests:**
- Protocol created with 4-site rotation; compound added with 2-site custom rotation
- Timeline renders correct sites for each dose
- Dashboard shows correct site for today's doses
- Manual override saves and persists
- Editing protocol sites updates all dose displays

**Smoke tests (existing pre-deploy checklist):**
- Protocol builder opens; compound form shows checkbox
- Checking checkbox shows site multiselect
- Sites save and display in compounds list
- Timeline shows sites
- Dashboard shows sites on dose log

---

## Out of Scope

- Tracking which site was *actually* used vs. planned (separate future feature)
- Site-specific injury/irritation logging
- Integration with Hevy or Apple Health for anatomical data
- Mobile-specific site visualization (e.g., 3D body diagram)

---

## Future Considerations

- **Site preference learning:** "This user always uses glutes → suggest those as default"
- **Injury tracking:** Log site irritation, automatically skip it for N days
- **Coach visibility:** Show coach which sites user selected + rotation on athlete dashboard
- **Dose history:** "Last month I used Left VG 6 times, Right VG 4 times" analytics

