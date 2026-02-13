# Quickstart: Todo List with External Source Connections

**Feature Branch**: `002-todo-external-sources`
**Date**: 2026-02-13

## Prerequisites

- Go 1.25.0+ installed
- Git (for branch management)
- Terminal with 256-color support (for Lip Gloss styling)

## Setup

```bash
# Clone and switch to feature branch
git clone <repo-url> task-management
cd task-management
git checkout 002-todo-external-sources

# Install dependencies
go mod download

# Build
go build -o taskmanager ./cmd/taskmanager

# Run
./taskmanager
```

## Database Location

SQLite database is stored at:
```
~/.local/share/taskmanager/tasks.db
```

The v3 migration (new tables for todos, projects, tags, etc.) runs automatically on first launch after the feature is implemented.

## Running Tests

```bash
# All tests
go test ./...

# Store tests only (uses in-memory SQLite)
go test ./tests/store/...

# Model tests
go test ./tests/model/...

# Integration tests
go test ./tests/integration/...

# With verbose output
go test -v ./...

# With coverage
go test -cover ./...
```

## Key Files to Modify (by priority)

### P1: Local Todo CRUD
1. `internal/model/todo.go` — Todo and ChecklistItem structs
2. `internal/model/listitem.go` — ListItem interface
3. `internal/store/migrations.go` — v3 migration (new tables)
4. `internal/store/store.go` — Extended Store interface
5. `internal/store/todo_store.go` — Todo CRUD implementation
6. `internal/ui/todoform/model.go` — Create/edit form
7. `internal/ui/tasklist/model.go` — Refactor to use ListItem
8. `internal/ui/tasklist/item.go` — Extend renderer
9. `internal/app/app.go` — Add ViewTodoCreate/ViewTodoEdit
10. `internal/app/keys.go` — Add n/e/x/d/H keybindings

### P2: Projects & Tags
11. `internal/model/project.go` — Project struct
12. `internal/model/tag.go` — Tag struct
13. `internal/store/project_store.go` — Project CRUD
14. `internal/store/tag_store.go` — Tag CRUD
15. `internal/ui/projectmgr/model.go` — Project management view
16. `internal/ui/tagmgr/model.go` — Tag management view

### P3: External Sources (mostly existing)
17. `internal/model/link.go` — Link struct
18. `internal/store/link_store.go` — Link CRUD
19. `internal/ui/detail/model.go` — Extend with checklist + links

### P5: Search & Filter
20. `internal/ui/tasklist/model.go` — Add date-based filters, combined source filter

## Development Workflow

1. **Start with models**: Define structs in `internal/model/`
2. **Write migration**: Add v3 schema to `internal/store/migrations.go`
3. **Implement store**: Write CRUD methods with tests
4. **Build UI**: Create forms and extend list view
5. **Wire up app**: Connect views in `app.go`, add keybindings
6. **Test end-to-end**: Manual testing in the TUI

## Architecture Notes

- **Bubble Tea pattern**: All UI is Model/Update/View. State changes happen via messages (tea.Msg). Never mutate state outside Update().
- **Store pattern**: All database access goes through the Store interface. SQLiteStore is the only implementation.
- **Heap-allocated bindings**: Form state (Huh) uses pointer-based bindings to survive Bubble Tea's model copying. See `internal/ui/config/model.go` for the pattern.
- **ListItem interface**: The key abstraction. Both Todo and Task implement it. The task list view works with `[]ListItem` for the unified display.
