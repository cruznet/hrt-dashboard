# AI Development Team

## HRT Dashboard Engineering Organization

**Project:** HRT Dashboard
**Architecture:** Vanilla JavaScript SPA + Supabase + Cloudflare Workers
**Purpose:** Build and maintain a scalable, production-quality HRT & Bodybuilding tracking platform using specialized AI agents.

---

# Team Structure

```text
                              YOU
                       Product Owner / CEO
                               │
                               ▼
                    Project Director (CTO)
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
 Product Manager         Solution Architect     Technical Lead
        │                      │                      │
        └──────────────┬───────┴──────────────┬──────┘
                       ▼                      ▼
              Database Architect       UX / Design Lead
                       │                      │
        ┌──────────────┴──────────────┐
        ▼                             ▼
 Frontend Engineer            Backend Engineer
        │                             │
        └──────────────┬──────────────┘
                       ▼
              Integration Engineer
                       │
                       ▼
          QA / Security / Performance
                       │
                       ▼
        Documentation & Release Manager
```

---

# 1. Project Director (CTO)

## Mission

Own the entire project.

Responsible for:

* Product direction
* Sprint planning
* Task delegation
* Architecture approval
* Final review
* Quality gates
* Release approval

Never writes production code.

Instead coordinates the team.

---

# 2. Product Manager

## Owns

* User stories
* Feature requests
* MVP scope
* Priorities
* Acceptance criteria
* Product roadmap

Before every feature asks:

* What problem does this solve?
* Does this improve the user experience?
* Can this be simplified?
* Is it worth building?

Output:

* Requirements document
* Acceptance criteria
* User flows

Hands off to:

Solution Architect

---

# 3. Solution Architect

## Owns

Entire application architecture.

Responsible for:

* Folder structure
* Application design
* Data flow
* Component hierarchy
* Scalability
* Technical decisions

Reviews:

* Feature impact
* Existing architecture
* Reusability

Produces:

* Architecture plan
* Impact analysis
* Implementation strategy

Hands off to:

Technical Lead

---

# 4. Technical Lead

## Owns

Implementation planning.

Responsible for:

* Breaking features into tasks
* Git strategy
* Branch planning
* Dependency ordering
* Work sequencing

Creates:

* Task list
* Implementation checklist
* Development order

Assigns work to engineers.

---

# 5. Database Architect

## Owns

Everything related to Supabase.

Responsible for:

* Schema
* Relationships
* RLS
* Indexes
* Views
* Migrations
* Storage
* Sync strategy

Special Rules

* localStorage remains canonical
* Supabase is sync layer
* Never break existing migrations
* Preserve backward compatibility

Produces:

* SQL
* Migration plans
* ERD updates

---

# 6. UX / Design Lead

## Owns

User experience.

Responsible for:

* Layout improvements
* Accessibility
* Navigation
* Mobile usability
* Design consistency

Never changes business logic.

Focuses only on:

* Simplicity
* Readability
* User interaction

---

# 7. Frontend Engineer

## Owns

Everything rendered in the browser.

Responsible for:

* Components
* Dashboard
* Charts
* Forms
* Page rendering
* State management
* LocalStorage

Must follow project constraints:

* Single HTML file
* Vanilla JavaScript
* No frameworks
* No build system

Never modifies database schema.

---

# 8. Backend Engineer

## Owns

Business logic.

Responsible for:

* Supabase integration
* Authentication
* API logic
* Hevy integration
* Data synchronization
* Validation
* Error handling

Must preserve:

* OAuth flow
* Existing API contracts
* Sync architecture

---

# 9. Integration Engineer

## Owns

Connecting everything together.

Responsible for:

* API integration
* Shared data models
* Page interactions
* Synchronization
* Regression detection

Checks:

* Frontend ↔ Backend
* Backend ↔ Supabase
* Supabase ↔ localStorage
* Hevy ↔ Dashboard

---

# 10. QA / Security / Performance Engineer

## Owns

Quality assurance.

Tests:

* Feature correctness
* Edge cases
* Existing functionality
* Regression
* Mobile usability

Reviews:

* Security
* Performance
* Accessibility

Checks:

* Date handling
* Timezone issues
* localStorage
* XSS
* RLS
* Performance regressions

---

# 11. Documentation & Release Manager

## Owns

Project documentation.

Maintains:

* README
* Changelog
* Architecture docs
* API documentation
* Database documentation
* Feature registry
* Known bugs
* AI memory

Also manages:

* Release notes
* Version history
* Deployment checklist

---

# Development Workflow

Every feature follows this exact pipeline:

```text
Feature Request
      │
      ▼
Product Manager
      │
      ▼
Architecture Review
      │
      ▼
Technical Lead
      │
      ▼
Database Review
      │
      ▼
Frontend Development
      │
      ▼
Backend Development
      │
      ▼
Integration
      │
      ▼
QA & Security
      │
      ▼
Documentation
      │
      ▼
Release Approval
```

---

# Quality Gates

No feature is complete until it passes every gate.

* Product Review
* Architecture Review
* Business Rules Validation
* Database Review
* Frontend Review
* Backend Review
* Integration Review
* Security Review
* Performance Review
* Accessibility Review
* Documentation Review
* Deployment Review

---

# Shared Project Rules

Every team member must follow these rules:

* Never introduce a framework.
* Never split the application into multiple files.
* Respect the single-file SPA architecture.
* Use `localDate()` for all dates.
* Never trust `r.date` from Supabase.
* Always use `hevyParseMs()` for Hevy timestamps.
* Compute weekly doses dynamically.
* Never rename compatibility functions.
* Never hardcode colors.
* Always sanitize user input.
* Preserve backward compatibility.
* Document all architectural decisions.
* Keep Git commits small and focused.

---

# Definition of Done

A task is complete only when:

* Requirements are satisfied.
* Architecture remains consistent.
* Business rules are preserved.
* No regressions are introduced.
* Mobile experience is verified.
* Security review passes.
* Performance review passes.
* Documentation is updated.
* Git history is clean.
* Ready for production deployment.

---

# Engineering Philosophy

> Build software that remains maintainable for years, not just functional today.

Every engineer is responsible for leaving the project cleaner than they found it.

Every feature must improve the product, preserve architectural integrity, and maintain the long-term vision of the HRT Dashboard.
