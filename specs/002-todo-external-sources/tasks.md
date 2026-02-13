# Tasks: Todo List with External Source Connections

**Input**: Design documents from `/specs/002-todo-external-sources/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Single project** (Go binary): `internal/`, `cmd/`, `tests/` at repository root
- Paths reference the existing Feature 001 codebase structure

---

## Phase 1: Setup

**Purpose**: Add test dependency and create test infrastructure (no tests exist yet)

- [x] T001 Add `github.com/stretchr/testify` dependency to `go.mod` via `go get github.com/stretchr/testify`
- [x] T002 [P] Create test helper with in-memory SQLite setup in `tests/testutil/store.go` — provide a `NewTestStore(t)` function that opens `:memory:` SQLite, runs all migrations (v1-v3), and returns a ready `*store.SQLiteStore`. Use the existing migration logic from `internal/store/migrations.go`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data layer that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 [P] Create Todo and ChecklistItem model structs in `internal/model/todo.go` — Todo fields: ID, Title, Description, Status (open/complete), Priority (1-5), DueDate (*time.Time), SortOrder (int), ProjectID (*string), CreatedAt, CompletedAt (*time.Time), UpdatedAt. Also include a Tags ([]Tag) field for query results. ChecklistItem fields: ID, TodoID, Text, Checked (bool), SortOrder, CreatedAt. Follow existing model conventions from `internal/model/task.go` (db tags, json tags)
- [x] T004 [P] Create ListItem interface in `internal/model/listitem.go` — define the interface per `contracts/ui.md`: GetID, GetTitle, GetDescription, GetStatus, GetPriority, IsCompleted, GetSource, IsLocal, GetCreatedAt, GetUpdatedAt, GetDueDate, IsOverdue, GetProjectID, GetSortOrder. Implement the interface on Todo (source="local") and on Task (source=SourceType, no due date, no project). See `contracts/ui.md` for exact method signatures
- [x] T005 [P] Create Project model struct in `internal/model/project.go` — fields: ID, Name, Description, Color, Icon, Archived (bool), SortOrder, CreatedAt, UpdatedAt. Follow existing model conventions
- [x] T006 [P] Create Tag model struct in `internal/model/tag.go` — fields: ID, Name, Color, CreatedAt. Follow existing model conventions
- [x] T007 [P] Create Link model struct in `internal/model/link.go` — fields: ID, TodoID, TaskID, LinkType (manual/auto), CreatedAt. Follow existing model conventions
- [x] T008 Add v3 migration to `internal/store/migrations.go` — add all 6 new tables (projects, todos, tags, todo_tags, checklist_items, links) with indexes and constraints exactly as defined in `data-model.md` Migration v3 section. Update the migration runner to handle v3. Ensure the projects table is created BEFORE todos (foreign key dependency)
- [x] T009 Create TodoFilter struct and extend Store interface in `internal/store/store.go` — add TodoFilter struct per `contracts/store.md`. Add all new method signatures to the Store interface: Todo CRUD (7 methods), Project CRUD (7 methods), Tag CRUD (6 methods), Checklist CRUD (6 methods), Link management (4 methods). Keep all existing methods unchanged
- [x] T010 Implement Todo CRUD methods on SQLiteStore in `internal/store/todo_store.go` — implement CreateTodo, UpdateTodo, DeleteTodo, GetTodoByID, GetTodos (with full TodoFilter support including tag filtering via JOIN, date-based filtering for today/upcoming/overdue), GetTodoCount, ReorderTodo. Auto-set created_at/updated_at. Auto-set completed_at on status→complete, clear on status→open. Default sort_order to max+1 for new todos. Use sqlx named queries following the pattern in `internal/store/sqlite.go`

**Checkpoint**: Foundation ready — data models, migration, store interface, and core Todo CRUD in place

---

## Phase 3: User Story 1 — Create and Manage Personal Todos (Priority: P1) MVP

**Goal**: Users can create, view, edit, complete, delete, and reorder local todos with checklists. The app is fully functional as a standalone todo list with zero external sources.

**Independent Test**: Create several todos with titles/descriptions/priorities/due dates, mark some complete (verify dimmed/struck-through), edit one, delete another with confirmation, reorder via priority. Verify persistence across app restarts.

### Implementation for User Story 1

- [x] T011 [P] [US1] Implement Checklist CRUD methods on SQLiteStore in `internal/store/todo_store.go` (append to same file) — implement AddChecklistItem, UpdateChecklistItem, DeleteChecklistItem, GetChecklistItems (ordered by sort_order), ToggleChecklistItem (flip checked 0↔1), ReorderChecklistItem. CASCADE delete is handled by schema
- [x] T012 [P] [US1] Add overdue and completed styling to theme in `internal/app/theme.go` — add Lip Gloss styles: DimmedStyle (for completed items — faint/struck-through), OverdueStyle (red/bold for overdue indicator), LocalBadgeStyle (for "local" source badge), DueDateStyle (subtle color for due date display). Follow existing theme patterns
- [x] T013 [US1] Create todo create/edit form in `internal/ui/todoform/model.go` — build a Huh form with fields: Title (required text input), Description (optional text area), Priority (select 1-5, default 3), DueDate (optional text input with date format hint YYYY-MM-DD), Status (select open/complete, edit mode only). Use heap-allocated formBindings pattern from `internal/ui/config/model.go`. Handle form submission by dispatching a TodoCreatedMsg or TodoUpdatedMsg. Handle Esc to cancel and return to list
- [x] T014 [US1] Refactor task list view to use ListItem interface in `internal/ui/tasklist/model.go` — change the internal item storage from `[]model.Task` to `[]model.ListItem`. Update the fetch logic to load both local todos (via GetTodos) and external tasks (via GetTasks), convert both to ListItem, merge into a single slice, and sort by the active sort mode. Add a `showCompleted` bool toggle (default true). When showCompleted is false, filter out items where IsCompleted()==true. Add a `TasksAndTodosLoadedMsg` that carries both item types. Preserve existing pagination and infinite scroll behavior
- [x] T015 [US1] Extend list item renderer for local todos in `internal/ui/tasklist/item.go` — use type-switch on ListItem to render local todos differently from external tasks: open local todo shows ○ prefix, completed shows ✓ with DimmedStyle, overdue shows ○ with red OVERDUE indicator. Show priority badge [P1]-[P5], due date (if set), source badge ("local" vs "jira" etc). External tasks continue to use ● prefix with source-specific colored badge
- [x] T016 [US1] Add todo-related view states and keybindings in `internal/app/app.go` and `internal/app/keys.go` — add ViewTodoCreate and ViewTodoEdit to ViewState enum. In keys.go, add keybindings: n=new todo (→ViewTodoCreate), e=edit selected todo (→ViewTodoEdit, local only), x=toggle complete on selected (local only, dispatches update), d=delete selected with confirmation (local only), H=toggle show/hide completed. Wire these into the root Model's Update() method. Handle TodoCreatedMsg, TodoUpdatedMsg, TodoDeletedMsg to refresh the list
- [x] T017 [US1] Extend detail view for local todo details with checklist in `internal/ui/detail/model.go` — when the selected item IsLocal(), show todo-specific details: title, description (rendered markdown), priority, due date, status. Below the description, render the checklist: each item shows ☐/☑ + text. Add keybindings within detail view: a=add checklist item (inline text input), Space=toggle check on selected checklist item, Backspace=delete checklist item. Dispatch store operations via messages. For external items, keep existing behavior unchanged
- [x] T018 [US1] Wire todo form and detail into app initialization in `cmd/taskmanager/main.go` and `internal/app/app.go` — ensure the todo form model is initialized in app.Model's Init. Load todos alongside tasks on startup (dispatch both GetTodos and GetTasks). Ensure the todo store methods are accessible from the app model. Verify the app compiles and runs with `go build ./cmd/taskmanager`

**Checkpoint**: User Story 1 complete — the app functions as a standalone todo list. Create, edit, complete, delete, reorder todos with checklists. No external sources required.

---

## Phase 4: User Story 2 — Organize Todos with Projects and Tags (Priority: P2)

**Goal**: Users can create projects and tags, assign todos to projects, tag todos, and filter the list by project or tag.

**Independent Test**: Create two projects ("Work", "Personal"), create todos in each, add tags ("urgent", "errands"), filter by project, filter by tag, archive a project and verify todos move to Inbox.

### Implementation for User Story 2

- [x] T019 [P] [US2] Implement Project CRUD methods on SQLiteStore in `internal/store/project_store.go` — implement CreateProject, UpdateProject, DeleteProject (SET NULL on todos.project_id), GetProjectByID, GetProjects (ordered by sort_order, filterable by includeArchived), ArchiveProject, RestoreProject. Validate unique name (case-insensitive via COLLATE NOCASE or lower())
- [x] T020 [P] [US2] Implement Tag CRUD methods on SQLiteStore in `internal/store/tag_store.go` — implement CreateTag, UpdateTag, DeleteTag (CASCADE via todo_tags), GetTags (ordered by name), GetTagsForTodo (JOIN todo_tags), SetTodoTags (delete all existing + insert new in a transaction). Validate unique name (case-insensitive)
- [x] T021 [US2] Create project management view in `internal/ui/projectmgr/model.go` — build a Bubble Tea model that shows a list of projects (active and optionally archived). Keybindings: n=create new project (inline Huh form with name, description, color, icon), e=edit selected, a=archive/restore toggle, d=delete with confirmation (warns about orphaned todos). Add a ViewProjectList state to app.go and wire the p keybinding to open it
- [x] T022 [US2] Create tag management view in `internal/ui/tagmgr/model.go` — build a Bubble Tea model that shows a list of all tags with usage counts. Keybindings: n=create new tag (name + color), e=edit, d=delete with confirmation (warns about removal from todos). Add a ViewTagList state to app.go and wire the t keybinding to open it
- [x] T023 [US2] Extend todo form with project and tag selection in `internal/ui/todoform/model.go` — add a Project field (select from active projects + "None/Inbox" option) and a Tags field (multi-select from existing tags) to the create/edit form. When saving, call SetTodoTags to update tag associations. Load projects and tags from store when form initializes
- [x] T024 [US2] Add project and tag filter support to task list in `internal/ui/tasklist/model.go` — add activeProjectFilter (*string, nil=all, "inbox"=no project, UUID=specific project) and activeTagFilter ([]string). When fetching todos, pass these into TodoFilter. Add keybindings or command palette entries to select project/tag filters. Show active filter in the status bar. Extend the source filter keys (existing 1-5) with project filter awareness
- [x] T025 [US2] Extend list item renderer with project and tag badges in `internal/ui/tasklist/item.go` — for local todos, show the project name (if assigned) with a folder icon and the tag names with a label icon after the title. Use tag colors for rendering. Truncate if too many tags to fit the terminal width

**Checkpoint**: User Story 2 complete — todos can be organized into projects and tagged. Filtering by project/tag works in the list view.

---

## Phase 5: User Story 3 — Connect External Sources (Priority: P3)

**Goal**: External source items (Jira, Bitbucket, Email) from the existing adapter system appear alongside local todos in the unified list with clear source indicators and graceful handling of unavailability.

**Independent Test**: Configure one external source (e.g., Jira), verify items appear in the unified list with source badge, disconnect network and verify items show stale indicator.

### Implementation for User Story 3

- [x] T026 [US3] Ensure unified list merge works with external tasks in `internal/ui/tasklist/model.go` — verify the ListItem merge logic from T014 correctly interleaves local todos and external tasks. External tasks should show source-specific badges (Jira=blue diamond, Bitbucket=orange, Email=envelope). Test with both empty and populated external sources. Ensure external items are not editable/deletable via local todo keybindings (x/e/d should no-op or show a message for external items)
- [x] T027 [US3] Add stale indicator for unreachable external sources in `internal/ui/tasklist/item.go` and `internal/app/app.go` — when a sync error (SyncErrorMsg or AuthError) is received for a source, mark that source as stale in the app model. In the list renderer, show a stale badge (e.g., ⚠ or clock icon) next to items from stale sources. Show a notification in the status bar indicating which source is unreachable. Clear the stale flag when the next sync succeeds
- [x] T028 [US3] Extend detail view for external item metadata in `internal/ui/detail/model.go` — when the selected item is external (!IsLocal()), show source-specific metadata: assignee, status, source URL (clickable if terminal supports OSC 8), last synced time. The existing detail view from Feature 001 already shows this — verify it still works correctly with the ListItem refactor from T014 and the checklist additions from T017. Fix any regressions

**Checkpoint**: User Story 3 complete — external source items appear in the unified list alongside local todos with proper source indicators and stale handling.

---

## Phase 6: User Story 4 — Interact with External Items (Priority: P4)

**Goal**: Users can perform actions on external items (change status, add comments) and link local todos to external items for cross-referencing.

**Independent Test**: Change an external item's status from the app, verify the change appears in the external system. Link a local todo to an external item, verify both show the linkage.

### Implementation for User Story 4

- [x] T029 [P] [US4] Implement Link CRUD methods on SQLiteStore in `internal/store/link_store.go` — implement CreateLink (validate todo_id exists, enforce UNIQUE(todo_id, task_id)), DeleteLink, GetLinksForTodo (return links with associated task titles), GetLinksForTask (return links with associated todo titles). Follow existing sqlx patterns
- [x] T030 [US4] Add link management to detail view in `internal/ui/detail/model.go` — when viewing a local todo's detail, show a "Linked Items" section listing linked external tasks (title + source badge). Add keybinding: l=link to external item (opens a picker showing available external tasks from the current list). Add keybinding: u=unlink selected link. When viewing an external item's detail, show "Linked Todos" section listing linked local todos. Navigation: Enter on a linked item switches to that item's detail
- [x] T031 [US4] Verify external item actions work with unified list in `internal/app/app.go` — the existing Feature 001 already supports ExecuteAction for external items (status changes, comments). Verify this still works after the ListItem refactor. When an action is executed on an external item from the unified list, ensure the correct source adapter is called and the result refreshes the list. Fix any regressions from the refactor

**Checkpoint**: User Story 4 complete — users can interact with external items and link them to local todos.

---

## Phase 7: User Story 5 — Search and Filter Across All Sources (Priority: P5)

**Goal**: Users can search by keyword across all sources and filter the unified list by source, status, priority, tag, project, and date-based views (today/upcoming/overdue).

**Independent Test**: Search for a keyword that exists in both a local todo and an external item, verify both appear. Apply a "today" date filter, verify only items due today are shown. Combine source + status filters.

### Implementation for User Story 5

- [x] T032 [US5] Implement unified search across local and external items in `internal/ui/tasklist/model.go` — extend the existing search mode (triggered by /) to query both stores: pass Query to TodoFilter for local todos and to TaskFilter for external tasks. Merge results into a single ListItem slice sorted by relevance (exact title match > title contains > description contains). Show result count in status bar
- [x] T033 [US5] Add date-based filter support to task list in `internal/ui/tasklist/model.go` — add a date filter mode (today/upcoming/overdue/none). Wire a keybinding or command palette entry to cycle through date filters. Pass the DueDate filter value to TodoFilter when fetching. Date filters only apply to local todos (external items have no due dates). Show the active date filter in the status bar
- [x] T034 [US5] Extend source filter to include local source in `internal/ui/tasklist/model.go` — update the source filter keys: 1=all sources, 2=local todos only, 3=Jira only, 4=Bitbucket only, 5=Email only. When a source filter is active, only fetch from matching stores (e.g., 2=only GetTodos, 3=only GetTasks with SourceType=jira). Show active source filter in status bar
- [x] T035 [US5] Implement combined filter state management in `internal/ui/tasklist/model.go` — ensure all filters (source, status, priority, project, tag, date, search query) can be combined (AND logic). Show a filter summary in the status bar (e.g., "Filters: local | overdue | #urgent"). Add a keybinding to clear all filters at once (e.g., Esc when not in search mode, or a dedicated key). Ensure clearing search preserves other filter state as per spec acceptance scenario 3

**Checkpoint**: User Story 5 complete — full search and multi-dimensional filtering across all sources.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T036 [P] Update help overlay with new keybindings in `internal/ui/help/model.go` — add all new keybindings to the help screen: n (new todo), e (edit), x (complete), d (delete), H (hide/show completed), p (projects), t (tags), l (link), source filter keys (1-5), date filter commands. Group by context (global, list, detail, form)
- [x] T037 [P] Extend command palette with todo commands in `internal/ui/command/model.go` — add commands: "new todo", "projects", "tags", "filter by project: X", "filter by tag: X", "clear filters", "toggle completed". Wire each to the appropriate action/view
- [x] T038 Verify app builds and runs end-to-end — run `go build ./cmd/taskmanager`, launch the app, and verify: (1) empty state shows welcome/instructions, (2) creating a todo works, (3) project/tag management works, (4) external sources still load if configured, (5) search and filters work, (6) help screen shows all keybindings. Fix any compilation errors or runtime panics
- [x] T039 Run quickstart.md validation — follow the steps in `specs/002-todo-external-sources/quickstart.md` from scratch and verify the setup, build, and test instructions are accurate. Fix any discrepancies

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 (Phase 3): Can start after Phase 2 — no dependencies on other stories
  - US2 (Phase 4): Can start after Phase 2 — independent of US1 but benefits from US1's list view refactor
  - US3 (Phase 5): Can start after Phase 2 — depends on US1's ListItem refactor (T014)
  - US4 (Phase 6): Depends on US3 (needs external items in unified list)
  - US5 (Phase 7): Depends on US1 (list view) and US3 (external items in list)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

```text
Phase 2 (Foundational)
    │
    ├──► US1 (P1) ──► US3 (P3) ──► US4 (P4)
    │                    │
    ├──► US2 (P2)        └──► US5 (P5)
    │                         ▲
    └─────────────────────────┘
```

- **US1 → US3**: US3 needs the ListItem-based unified list from US1
- **US3 → US4**: US4 needs external items in the list from US3
- **US1 + US3 → US5**: US5 searches across both local and external items

### Within Each User Story

- Models/store methods before UI components
- Store implementation before forms and views
- Core UI before keybinding wiring
- Story complete before moving to next priority

### Parallel Opportunities

Within Phase 2 (Foundational):
- T003, T004, T005, T006, T007 can all run in parallel (different model files)
- T008 (migration) can run in parallel with models but T009 (interface) and T010 (implementation) must follow

Within US1:
- T011 (checklist store) and T012 (theme) can run in parallel
- T013 (form), T014 (list refactor), T015 (renderer) can partially overlap (different files)

Within US2:
- T019 (project store) and T020 (tag store) can run in parallel
- T021 (project view) and T022 (tag view) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch parallel store + theme tasks:
Task: "Implement Checklist CRUD in internal/store/todo_store.go"     # T011
Task: "Add overdue and completed styling in internal/app/theme.go"   # T012

# Then launch form + list refactor (after store is done):
Task: "Create todo form in internal/ui/todoform/model.go"            # T013
Task: "Refactor task list to ListItem in internal/ui/tasklist/model.go"  # T014
Task: "Extend item renderer in internal/ui/tasklist/item.go"         # T015
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational (T003-T010)
3. Complete Phase 3: User Story 1 (T011-T018)
4. **STOP and VALIDATE**: App works as a standalone todo list with checklists, completion toggle, reordering, overdue indicators
5. Deploy/demo if ready — delivers immediate value

### Incremental Delivery

1. Setup + Foundational → Data layer ready
2. Add US1 → Standalone todo list (MVP!)
3. Add US2 → Projects and tags for organization
4. Add US3 → External sources in unified view
5. Add US4 → Interact with external items + linking
6. Add US5 → Full search and filtering
7. Polish → Help, command palette, validation

### Recommended Execution Order

For a single developer: **US1 → US2 → US3 → US5 → US4** (US5 benefits from having external items but can be partially implemented after US1 alone; US4 is the least critical for daily use)

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable after Phase 2
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- The existing Feature 001 code (source adapters, poller, config, AI) remains unchanged — only the list view, detail view, and app model are extended
