# Research: Todo List with External Source Connections

**Feature Branch**: `002-todo-external-sources`
**Date**: 2026-02-13

## R-001: Local Todo Data Model vs Existing Task Model

**Decision**: Separate `Todo` model alongside existing `Task` model, unified via a `ListItem` interface for the UI.

**Rationale**: The existing `Task` struct is optimized for external source items (SourceType, SourceItemID, FetchedAt, RawData). Local todos have fundamentally different attributes (projects, tags, checklists, custom ordering, due dates) that don't map cleanly to `Task`. Forcing local todos into the `Task` model would bloat the struct and create confusing null/empty fields. A shared `ListItem` interface gives the UI a common abstraction without coupling the data models.

**Alternatives considered**:
- *Unified Task model with source_type="local"*: Would reuse existing infrastructure but forces awkward mappings — checklist items, projects, and tags have no equivalent in the Task struct. Filtering and querying become complex with overloaded fields.
- *Complete rewrite replacing Task with a universal model*: Too much churn for Feature 001's working code. Breaking change with no incremental benefit.

---

## R-002: SQLite Schema Extension Strategy

**Decision**: Add a v3 migration with new tables (todos, projects, tags, todo_tags, checklist_items, links) alongside existing tables. No changes to existing tables.

**Rationale**: The existing migration system (schema_version table with sequential versions) supports additive migrations cleanly. New tables don't affect existing Task/Source/Notification functionality. SQLite's WAL mode handles concurrent reads between the poller (writing external tasks) and the UI (reading todos) without contention.

**Alternatives considered**:
- *Separate SQLite database for todos*: Eliminates any risk to existing data but makes unified queries (search across both) impossible without cross-database joins. Adds complexity to the store layer.
- *Add columns to existing tasks table*: Would create wide sparse rows and complicate existing queries. Foreign key relationships (todo→project, todo→tags) aren't possible with a single-table approach.

---

## R-003: Unified List View Architecture

**Decision**: Define a `ListItem` Go interface that both `Todo` and `Task` implement. The task list view fetches from both stores, merges into a single `[]ListItem` slice, sorts/filters uniformly, and delegates rendering to type-specific logic.

**Rationale**: The existing `tasklist.Model` operates on `[]model.Task`. Changing it to `[]ListItem` (interface) keeps the same Bubble Tea Update/View pattern while supporting heterogeneous items. Type-switch in the renderer handles source-specific visual differences (local todo styling, external source badges, overdue indicators).

**Alternatives considered**:
- *Two separate list panels (todos + external)*: Defeats the unified view requirement (FR-002). Users would need to switch between panels.
- *Convert Tasks to Todos on fetch*: Lossy conversion — external items don't have checklists/projects/tags. Would need a "read-only todo" concept that adds confusion.

---

## R-004: Custom Ordering Implementation

**Decision**: Use an integer `sort_order` column on the todos table. When the user reorders, update affected rows' sort_order values. Default sort places new items at the end (max sort_order + 1).

**Rationale**: Integer-based ordering is simple, fast to query (`ORDER BY sort_order`), and works well with SQLite. Reordering a single item between two others requires updating only one row (set sort_order to midpoint). Periodic normalization (re-number from 0 in increments of 1000) prevents integer exhaustion.

**Alternatives considered**:
- *Fractional ordering (float64)*: Precision loss after many reorders. Normalization still needed.
- *Linked-list ordering (prev_id/next_id)*: Complex queries for sorted retrieval. Poor performance for bulk operations.
- *Lexicographic ordering (string keys)*: Over-engineered for a local single-user app.

---

## R-005: Due Date and Overdue Handling

**Decision**: Store due_date as nullable DATETIME in SQLite. Overdue detection is computed at render time by comparing `due_date < now() AND status != 'complete'`. Date-based filters (today, upcoming, overdue) are implemented as query conditions in the store layer.

**Rationale**: Computing overdue at render time avoids background jobs or triggers. For a local single-user app, the performance cost is negligible. The store provides filtered queries so the UI doesn't need to post-filter large result sets.

**Alternatives considered**:
- *Cron-like background job to mark items overdue*: Unnecessary complexity for a TUI app. Adds state management for "overdue" as a separate status.
- *Overdue as a separate status field*: Creates state synchronization issues — what if the user extends the due date? Better to derive from data.

---

## R-006: Checklist Item Storage

**Decision**: Separate `checklist_items` table with foreign key to `todos(id)` and `ON DELETE CASCADE`. Each item has text, checked state, and sort_order.

**Rationale**: A separate table allows efficient CRUD on individual checklist items without rewriting the entire todo. CASCADE delete ensures cleanup. The sort_order column maintains user-defined ordering.

**Alternatives considered**:
- *JSON array in todo.description or a dedicated JSON column*: Simpler schema but makes individual item updates require read-modify-write of the entire JSON. No referential integrity. Querying individual items (e.g., "how many unchecked items") requires JSON parsing.
- *Embedded struct in Go only (no DB persistence)*: Checklist items would be lost on restart. Violates FR-004.

---

## R-007: Project and Tag Architecture

**Decision**: Projects are a one-to-many relationship (todo belongs to at most one project). Tags are many-to-many via a junction table. Both have their own management UI (create/edit/delete/archive).

**Rationale**: This matches the spec's entity definitions exactly. A todo without a project is in the implicit "Inbox" (project_id IS NULL). The junction table for tags is the standard relational pattern for many-to-many and enables efficient filtering.

**Alternatives considered**:
- *Tags as comma-separated string on todo*: Simple but makes filtering by tag require LIKE queries. No tag management (rename, delete, color).
- *Projects as tags with a special flag*: Blurs the distinction between hierarchical grouping (projects) and cross-cutting labels (tags). The spec explicitly defines them as separate entities.

---

## R-008: Testing Strategy

**Decision**: Use Go's standard `testing` package with `github.com/stretchr/testify` for assertions. Tests use in-memory SQLite (`:memory:`) for store tests. No mocking framework — use interface-based test doubles.

**Rationale**: The project has no tests yet. Starting with the standard library + testify keeps dependencies minimal. In-memory SQLite is fast and provides real SQL execution (no mocks needed for the store layer). Interface-based test doubles for the Source and Store interfaces are idiomatic Go.

**Alternatives considered**:
- *gomock or mockery*: Adds code generation complexity. The interfaces are small enough for hand-written test doubles.
- *dockertest with real PostgreSQL*: The app uses SQLite, not PostgreSQL. No need.
- *Testcontainers*: Over-engineered for a single-binary TUI app with SQLite.

---

## R-009: Link Management (Todo ↔ External Item)

**Decision**: A `links` table stores explicit associations between a local todo ID and an external task ID. Links are primarily user-created (manual). Auto-detection (matching Jira keys in todo titles) is a secondary enhancement.

**Rationale**: Explicit links are reliable and user-controlled. The existing `crossref` package in Feature 001 provides pattern matching for Jira keys in PR branches — the same approach can detect potential links, but the user confirms them. This avoids false positives.

**Alternatives considered**:
- *Automatic linking only*: Fragile — title similarity matching produces false positives. Users lose control.
- *No linking at all*: Misses FR-012. Users would need to manually track associations outside the app.

---

## R-010: Form Library for Todo Creation/Editing

**Decision**: Use Huh v0.8.0 (already a dependency) for todo create/edit forms, following the same pattern as the existing config forms in `internal/ui/config/model.go`.

**Rationale**: Huh is already integrated and provides form fields (text input, select, date picker, multi-select) that cover all todo attributes. The existing config form pattern (heap-allocated formBindings, validation flow) is proven and can be reused directly.

**Alternatives considered**:
- *Custom form implementation with Bubbles textinput*: More control but significantly more code. Huh already handles focus management, validation, and keyboard navigation.
- *Prompt-based input (one field at a time)*: Poor UX for creating a todo with multiple optional fields. Users would need to answer prompts sequentially.
