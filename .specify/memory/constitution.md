<!--
  Sync Impact Report
  Version change: 1.0.0 → 2.0.0 (MAJOR — platform redefinition)
  Modified principles:
    - I. Local-First Data (unchanged)
    - II. Adapter Pattern for External Sources (unchanged)
    - III. Simplicity & YAGNI (unchanged)
    - IV. Spec-Driven Development (unchanged)
  Added principles:
    - V. Todo-First Design
  Modified sections:
    - Technology Constraints: Go/TUI → Swift/SwiftUI native macOS
  Removed sections: None
  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ (no changes needed)
    - .specify/templates/spec-template.md ✅ (no changes needed)
    - .specify/templates/tasks-template.md ✅ (no changes needed)
  Follow-up TODOs: None
-->

# Task Management Constitution

## Core Principles

### I. Todo-First Design

The application is a **todo list first**. Todos are the central entity
around which everything else revolves. Jira tickets, Bitbucket PRs, and
time tracking entries MUST link back to todos — they are contextual
enrichments, not standalone features. The app MUST be useful as a
standalone todo manager even with zero external integrations configured.

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
implementation (see Principle V).

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

The application covers four integrated capabilities, all centered on todos:

1. **Todo management** — create, organize, prioritize, complete todos
2. **Jira ticket linking** — link todos to Jira tickets, sync status
3. **Bitbucket PR linking** — link todos to PRs, track review status
4. **Time tracking & booking** — track time per todo, export for
   Timension booking

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

**Version**: 2.0.0 | **Ratified**: 2026-02-14 | **Last Amended**: 2026-02-14
