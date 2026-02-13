# Implementation Plan: Todo List with External Source Connections

**Branch**: `002-todo-external-sources` | **Date**: 2026-02-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-todo-external-sources/spec.md`

## Summary

Extend the existing terminal task manager (Feature 001) with local todo management as the primary experience. Users create and manage personal todos with projects, tags, checklists, and due dates — all stored locally in SQLite. External source items (Jira, Bitbucket, Email) from the existing adapter system are displayed alongside local todos in a unified list. A new `ListItem` interface abstracts both types for the shared view, while keeping data models cleanly separated.

## Technical Context

**Language/Version**: Go 1.25.0
**Primary Dependencies**: Bubble Tea v1.3.10 (TUI), Bubbles v1.0.0 (components), Huh v0.8.0 (forms), Lip Gloss v1.1.0 (styling), sqlx v1.4.0 (database), modernc.org/sqlite v1.45.0
**Storage**: SQLite (existing, extended with new tables for todos, projects, tags, checklist items, links)
**Testing**: Go standard `testing` package + testify (to add); no tests exist yet — Feature 002 establishes the test foundation
**Target Platform**: macOS / Linux terminal (TUI via Bubble Tea)
**Project Type**: Single Go binary (TUI application)
**Performance Goals**: App launch <2s with 1,000+ items; todo CRUD operations imperceptible (<100ms); search results <1s
**Constraints**: Offline-first for local todos; local storage only (no cloud sync); terminal UI only
**Scale/Scope**: Individual user; 1,000+ combined items (local + external); ~10 external source connections max

## Constitution Check

*No constitution.md found. Gate skipped — no violations to evaluate.*

## Project Structure

### Documentation (this feature)

```text
specs/002-todo-external-sources/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── store.md         # Extended store interface contract
│   └── ui.md            # Unified list item interface contract
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
cmd/taskmanager/main.go              # Entry point (extend with todo store init)

internal/
├── app/
│   ├── app.go                       # Root model (add ViewTodoCreate, ViewTodoEdit views)
│   ├── sources.go                   # Source registration (unchanged)
│   ├── keys.go                      # Keybindings (extend with todo actions: n=new, e=edit, x=complete, d=delete)
│   └── theme.go                     # Styling (add overdue, dimmed, tag colors)
├── model/
│   ├── task.go                      # External task struct (unchanged)
│   ├── config.go                    # AppConfig (unchanged)
│   ├── notification.go              # Notification (unchanged)
│   ├── todo.go                      # NEW: Todo, ChecklistItem structs
│   ├── project.go                   # NEW: Project struct
│   ├── tag.go                       # NEW: Tag struct
│   ├── link.go                      # NEW: Link struct
│   └── listitem.go                  # NEW: ListItem interface (unifies Todo + Task for UI)
├── store/
│   ├── store.go                     # Interface (extend with todo/project/tag/link methods)
│   ├── sqlite.go                    # Implementation (extend with new methods)
│   ├── migrations.go                # Schema (add v3 migration for new tables)
│   ├── todo_store.go                # NEW: Todo CRUD implementation
│   ├── project_store.go             # NEW: Project CRUD implementation
│   ├── tag_store.go                 # NEW: Tag CRUD implementation
│   └── link_store.go                # NEW: Link CRUD implementation
├── source/                          # External source adapters (unchanged)
│   ├── source.go
│   ├── jira/
│   ├── bitbucket/
│   └── email/
├── sync/
│   └── poller.go                    # Background sync (unchanged)
├── ui/
│   ├── layout.go                    # Layout (unchanged)
│   ├── tasklist/
│   │   ├── model.go                 # Unified list (refactor to use ListItem interface)
│   │   └── item.go                  # List item renderer (extend for local todos, overdue, dimmed)
│   ├── todoform/
│   │   └── model.go                 # NEW: Todo create/edit form (Huh forms)
│   ├── projectmgr/
│   │   └── model.go                 # NEW: Project list + create/edit/archive
│   ├── tagmgr/
│   │   └── model.go                 # NEW: Tag management
│   ├── detail/
│   │   └── model.go                 # Detail view (extend for todo details with checklist)
│   ├── config/
│   │   └── model.go                 # Source config forms (unchanged)
│   ├── ai/
│   │   └── model.go                 # AI assistant (unchanged)
│   ├── help/                        # Help overlay (extend with new keybindings)
│   └── command/                     # Command palette (extend with todo commands)
├── credential/                      # Keyring (unchanged)
├── ai/                              # AI assistant (unchanged)
└── crossref/                        # Cross-references (unchanged)

tests/
├── store/
│   ├── todo_store_test.go           # NEW: Todo CRUD tests
│   ├── project_store_test.go        # NEW: Project CRUD tests
│   ├── tag_store_test.go            # NEW: Tag CRUD tests
│   └── link_store_test.go           # NEW: Link CRUD tests
├── model/
│   └── listitem_test.go             # NEW: ListItem interface tests
└── integration/
    └── unified_list_test.go         # NEW: Unified list with mixed items
```

**Structure Decision**: Single project layout (existing). New code is added as new files within the existing `internal/` package structure, following the established convention of one concern per file. Store implementation is split across files by entity type to keep files focused.
