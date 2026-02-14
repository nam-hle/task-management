<!--
  Sync Impact Report
  Version change: 3.0.0 → 3.1.0 (MINOR — priority reordering within existing principles)
  Modified principles:
    - I. Ticket-Based Task Management → Ticket-Based Time Booking (priority inversion:
      time booking is now the primary purpose, todo management is secondary)
  Modified sections:
    - Feature Scope: Reordered pillars — Time Booking is now Pillar 1, Task Watching is Pillar 2
  Removed sections: None
  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ (no changes needed)
    - .specify/templates/spec-template.md ✅ (no changes needed)
    - .specify/templates/tasks-template.md ✅ (no changes needed)
  Follow-up TODOs: None
-->

# Task Management Constitution

## Core Principles

### I. Ticket-Based Time Booking

The application's **primary purpose** is **time booking** — automatically
tracking how developers spend their time across applications, browser
tabs, and IDE activity, then attributing that time to Jira tickets and
Bitbucket PRs for export to Timension. Everything in the app serves this
goal: tickets are the unit of time attribution, and every tracked minute
should map back to a ticket. The **secondary purpose** is **todo/task
management** — a lightweight todo list that organizes work and provides
the ticket linkage that powers time attribution. The app MUST still
function as a basic todo manager without integrations, but the intended
workflow is: track time → match to tickets → review → book.

### II. Local-First Data

All user data MUST be stored locally on the user's machine. The application
MUST function fully offline — external source integrations (Jira, Bitbucket)
enhance the experience but are never required for core functionality. No
cloud accounts, no remote databases, no telemetry.

### III. Adapter Pattern for External Sources

External integrations (Jira, Bitbucket, future sources) MUST follow a
consistent protocol/interface. Each adapter is independently configurable
and MUST handle its own authentication, error recovery, and data mapping.
Adding a new source MUST NOT require changes to existing adapters or core
application logic.

### IV. Simplicity & YAGNI

Start with the simplest implementation that solves the stated problem.
Abstractions MUST be justified by concrete, current use cases — not
hypothetical future needs. Prefer three similar lines of code over a
premature abstraction. Features MUST be specified and planned before
implementation (see Principle V: Spec-Driven Development).

### V. Spec-Driven Development

Every non-trivial feature MUST begin with a specification (`/speckit.specify`)
before any code is written. Specs define WHAT and WHY; implementation plans
define HOW. This ensures alignment before effort is invested. Trivial fixes
(typos, single-line bug fixes) are exempt.

## Technology Constraints

- **Primary language**: Swift (latest stable)
- **UI framework**: SwiftUI (native macOS app)
- **Storage**: SwiftData (or Core Data if SwiftData insufficient)
- **Target platform**: macOS only
- **Minimum macOS version**: determined per feature plan
- **Credentials**: macOS Keychain
- **Package manager**: Swift Package Manager
- New dependencies MUST be justified — prefer Apple frameworks where feasible

## Feature Scope

The application serves two integrated pillars, ordered by priority:

**Pillar 1 (Primary) — Ticket-Based Time Booking**

1. **Automatic time tracking** — monitor active applications and browser
   tabs (Firefox, Chrome) to detect work on Jira tickets and Bitbucket PRs
2. **WakaTime integration** — import coding activity from IDEs for
   project-level context
3. **Learned review & export** — review tracked time, learn patterns for
   auto-approval, export formatted summaries for Timension booking

**Pillar 2 (Secondary) — Todo & Task Management**

4. **Todo management** — create, organize, prioritize, complete todos
5. **Jira ticket linking** — link todos to Jira tickets, sync status,
   surface ticket changes
6. **Bitbucket PR linking** — link todos to PRs, track review status

Pillar 2 provides the ticket linkage that Pillar 1 depends on for
accurate time attribution. Todos are the glue between tracked time and
external tickets.

## Development Workflow

- Feature branches MUST use the format `NNN-short-name` (e.g.,
  `003-app-time-tracking`)
- Never commit directly to `main` — all work goes through feature branches
  merged via fast-forward
- Run `swift build` and resolve all warnings before committing
- Commits MUST be atomic and focused on a single concern
- Commit messages MUST use the branch prefix format (e.g.,
  `003: Description of change`)

## Governance

This constitution supersedes ad-hoc decisions. Amendments require:

1. A clear rationale documented in the commit message
2. Version bump following semver (MAJOR for principle removal/redefinition,
   MINOR for new principles/sections, PATCH for clarifications)
3. Consistency propagation to dependent templates checked post-amendment

All implementation plans MUST include a Constitution Check verifying
compliance with these principles. Violations MUST be explicitly justified
in the plan's Complexity Tracking table.

**Version**: 3.1.0 | **Ratified**: 2026-02-14 | **Last Amended**: 2026-02-14
