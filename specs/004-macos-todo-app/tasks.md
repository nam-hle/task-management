# Tasks: Native macOS Todo App

**Input**: Design documents from `/specs/004-macos-todo-app/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/services.md, research.md, quickstart.md

**Tests**: Not explicitly requested — test tasks omitted. Tests can be added per story later.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **macOS app**: All source code under `TaskManagement/` at repository root
- **Tests**: `TaskManagement/Tests/TaskManagementTests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Xcode project initialization and directory structure

- [ ] T001 Create Xcode project (macOS App, SwiftUI, SwiftData) with bundle ID `com.taskmanagement.app` and minimum deployment target macOS 14.0
- [ ] T002 Configure entitlements: `com.apple.security.automation.apple-events`, disable App Sandbox; add Info.plist keys for `NSAccessibilityUsageDescription` and `NSAppleEventsUsageDescription` per quickstart.md
- [ ] T003 Create directory structure: `TaskManagement/Models/`, `TaskManagement/Services/`, `TaskManagement/Views/Sidebar/`, `TaskManagement/Views/TodoList/`, `TaskManagement/Views/TodoDetail/`, `TaskManagement/Views/TimeTracking/`, `TaskManagement/Views/Settings/`, `TaskManagement/Views/MenuBar/`, `TaskManagement/Networking/`, `TaskManagement/Tests/TaskManagementTests/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core models and app shell that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Create enums (Priority, BookingStatus, EntrySource, IntegrationType) in `TaskManagement/Models/Enums.swift`
- [ ] T005 [P] Create `@Model Todo` entity with all fields, relationships stubs, soft-delete support, and validation per data-model.md in `TaskManagement/Models/Todo.swift`
- [ ] T006 [P] Create `@Model Project` entity with fields, `todos` relationship, and name uniqueness validation in `TaskManagement/Models/Project.swift`
- [ ] T007 [P] Create `@Model Tag` entity with fields, many-to-many `todos` relationship using `@Relationship(inverse:)`, and name uniqueness validation in `TaskManagement/Models/Tag.swift`
- [ ] T008 Create `TaskManagementApp.swift` with `@main` App, WindowGroup, MenuBarExtra (`.window` style), shared `@Observable` TimerManager via `.environment()`, and SwiftData `modelContainer` for all entities
- [ ] T009 Create `ContentView.swift` with `NavigationSplitView` shell (sidebar, list, detail columns) in `TaskManagement/Views/ContentView.swift`

**Checkpoint**: Foundation ready — core models exist, app launches with empty shell, user story implementation can begin

---

## Phase 3: User Story 1 — Todo Management (Priority: P1) MVP

**Goal**: A fully functional standalone todo manager with projects, tags, search, filtering, keyboard shortcuts, and soft delete

**Independent Test**: Create 10+ todos across 2 projects with various priorities and tags. Filter by project, tag, priority, and search text. Complete, reopen, delete (trash), and restore todos. Quit and reopen — all data persists.

### Implementation for User Story 1

- [ ] T010 [P] [US1] Implement TodoService (create, update, complete, reopen, softDelete, restore, purgeExpired, list with filters, listTrashed, reorder) in `TaskManagement/Services/TodoService.swift`
- [ ] T011 [P] [US1] Implement ProjectService (create, update, delete with nullify, list ordered by sortOrder) in `TaskManagement/Services/ProjectService.swift`
- [ ] T012 [P] [US1] Implement TagService (create, update, delete with removal from todos, list ordered by name) in `TaskManagement/Services/TagService.swift`
- [ ] T013 [P] [US1] Create SidebarView with project list, "All Todos" / "Completed" / "Trash" smart filters, and project create/edit actions in `TaskManagement/Views/Sidebar/SidebarView.swift`
- [ ] T014 [P] [US1] Create ProjectRow component displaying project name, color indicator, and todo count in `TaskManagement/Views/Sidebar/ProjectRow.swift`
- [ ] T015 [US1] Create TodoListView with filtered/sorted todo list, inline completion toggle, and empty states in `TaskManagement/Views/TodoList/TodoListView.swift`
- [ ] T016 [P] [US1] Create TodoRow component displaying title, priority badge, project/tag chips, due date, and completion checkbox in `TaskManagement/Views/TodoList/TodoRow.swift`
- [ ] T017 [P] [US1] Create SearchBar with real-time text filtering in `TaskManagement/Views/TodoList/SearchBar.swift`
- [ ] T018 [US1] Create TodoDetailView with editable title, description, priority picker, project picker, tag picker, due date picker, and delete action in `TaskManagement/Views/TodoDetail/TodoDetailView.swift`
- [ ] T019 [US1] Wire ContentView: connect SidebarView selection to TodoListView filtering, TodoListView selection to TodoDetailView, and integrate SearchBar in `TaskManagement/Views/ContentView.swift`
- [ ] T020 [US1] Add keyboard shortcuts: Cmd+N (create todo), Enter/Cmd+Return (complete), Delete/Backspace (soft delete), Cmd+F (focus search), arrow keys (navigate list)

**Checkpoint**: User Story 1 fully functional — standalone todo manager with projects, tags, search, filtering, keyboard shortcuts, and persistence. App is usable as MVP.

---

## Phase 4: User Story 2 — Jira Ticket Linking (Priority: P2)

**Goal**: Link todos to Jira tickets, view synced ticket data (summary, status, assignee), import todos from Jira, and periodic background sync

**Independent Test**: Configure Jira credentials in settings. Link a todo to an existing Jira ticket by ID. Verify summary, status, and assignee display on the todo. Change ticket status in Jira, trigger sync, confirm updated status. Import a todo from a Jira ticket. Test offline: cached data displays with staleness indicator.

### Implementation for User Story 2

- [ ] T021 [P] [US2] Create `@Model JiraLink` entity with all fields, `todo` relationship, ticketID regex validation, and isBroken flag in `TaskManagement/Models/JiraLink.swift`
- [ ] T022 [P] [US2] Create `@Model IntegrationConfig` entity with type, serverURL, username, syncInterval, isEnabled, lastSyncedAt in `TaskManagement/Models/IntegrationConfig.swift`
- [ ] T023 [P] [US2] Implement KeychainService (saveToken, getToken, deleteToken) using Security framework with `kSecClassGenericPassword` and `kSecAttrAccessibleWhenUnlocked` in `TaskManagement/Services/KeychainService.swift`
- [ ] T024 [P] [US2] Implement HTTPClient with URLSession, retry logic, exponential backoff for 429, and Basic/Bearer auth support in `TaskManagement/Networking/HTTPClient.swift`
- [ ] T025 [US2] Implement JiraAPI with endpoints for Cloud (v3) and Server/DC (v2): getTicket, searchTickets, with auto-detection of Cloud vs Server from URL in `TaskManagement/Networking/JiraAPI.swift`
- [ ] T026 [US2] Implement JiraService (configure, linkToTodo, unlinkFromTodo, fetchTicket, searchTickets, syncAll, importAsTodo) in `TaskManagement/Services/JiraService.swift`
- [ ] T027 [US2] Implement SyncService with `NSBackgroundActivityScheduler` for 15-minute periodic sync (Jira only initially), offline fallback, and explicit `context.save()` in `TaskManagement/Services/SyncService.swift`
- [ ] T028 [P] [US2] Create JiraConfigView with server URL, username, token fields, test connection button, and sync interval picker in `TaskManagement/Views/Settings/JiraConfigView.swift`
- [ ] T029 [P] [US2] Create SettingsView as container with tab navigation for integration configs in `TaskManagement/Views/Settings/SettingsView.swift`
- [ ] T030 [US2] Create JiraLinkView displaying cached ticket summary, status, assignee, last synced time, staleness indicator, and broken-link badge in `TaskManagement/Views/TodoDetail/JiraLinkView.swift`
- [ ] T031 [US2] Add Jira linking actions to TodoDetailView: "Link Jira Ticket" (search/enter ID), "Import from Jira", "Unlink" in `TaskManagement/Views/TodoDetail/TodoDetailView.swift`

**Checkpoint**: User Story 2 fully functional — Jira credentials stored securely, tickets linked to todos with synced data, import from Jira works, background sync updates cached data

---

## Phase 5: User Story 3 — Bitbucket PR Linking (Priority: P3)

**Goal**: Link todos to Bitbucket PRs, view synced PR data (title, status, author, reviewers), and periodic background sync

**Independent Test**: Configure Bitbucket credentials in settings. Link a todo to a PR by repo/number. Verify PR title, status, author, and reviewers display. Merge the PR in Bitbucket, trigger sync, confirm status updates to "Merged". Filter todos by "has open PR".

### Implementation for User Story 3

- [ ] T032 [P] [US3] Create `@Model BitbucketLink` entity with all fields, `todo` relationship, and validation rules in `TaskManagement/Models/BitbucketLink.swift`
- [ ] T033 [US3] Implement BitbucketAPI with endpoints for Cloud (v2.0) and Server/DC (v1.0): getPR, searchPRs, with auto-detection of Cloud vs Server from URL in `TaskManagement/Networking/BitbucketAPI.swift`
- [ ] T034 [US3] Implement BitbucketService (configure, linkToTodo, unlinkFromTodo, fetchPR, searchPRs, syncAll) in `TaskManagement/Services/BitbucketService.swift`
- [ ] T035 [US3] Extend SyncService to include Bitbucket sync alongside Jira in the scheduled background task in `TaskManagement/Services/SyncService.swift`
- [ ] T036 [P] [US3] Create BitbucketConfigView with server URL, username, token fields, test connection button, and sync interval picker in `TaskManagement/Views/Settings/BitbucketConfigView.swift`
- [ ] T037 [US3] Add Bitbucket tab to SettingsView in `TaskManagement/Views/Settings/SettingsView.swift`
- [ ] T038 [US3] Create BitbucketLinkView displaying cached PR title, status, author, reviewers, last synced time, staleness indicator, and broken-link badge in `TaskManagement/Views/TodoDetail/BitbucketLinkView.swift`
- [ ] T039 [US3] Add Bitbucket linking actions to TodoDetailView: "Link Bitbucket PR" (search/enter repo+number), "Unlink" in `TaskManagement/Views/TodoDetail/TodoDetailView.swift`
- [ ] T040 [US3] Add "has open PR" filter option to TodoListView filtering in `TaskManagement/Views/TodoList/TodoListView.swift`

**Checkpoint**: User Story 3 fully functional — Bitbucket credentials stored, PRs linked to todos with synced data, combined Jira+Bitbucket background sync runs on schedule

---

## Phase 6: User Story 4 — Time Tracking per Todo (Priority: P4)

**Goal**: Start/stop/pause timers per todo, manually add/edit time entries, daily time review with per-todo and daily totals, auto-save/crash recovery, midnight splitting, and basic Timension export

**Independent Test**: Start a timer on a todo, wait 2+ minutes, stop it. Verify time entry recorded with correct duration. Start timer on another todo — first timer pauses. Open daily time review — see entries grouped by todo with totals. Manually add/edit an entry. Force-quit app while timer running, reopen — timer recovers. Export daily summary as formatted text.

### Implementation for User Story 4

- [ ] T041 [P] [US4] Create `@Model TimeEntry` entity with all fields, `todo` relationship (cascade delete), validation rules, and isInProgress constraint in `TaskManagement/Models/TimeEntry.swift`
- [ ] T042 [US4] Implement TimerService (start, pause, stop, getActive, autoSave every 60s via Timer.publish, recoverOnLaunch, midnight splitting) as `@Observable` class in `TaskManagement/Services/TimerService.swift`
- [ ] T043 [US4] Implement TimeEntryService (create, update, delete, listForDate, markReviewed, markExported, dailySummary) in `TaskManagement/Services/TimeEntryService.swift`
- [ ] T044 [US4] Create MenuBarView with timer display, active todo name, start/stop/pause controls, and quick todo switcher in `TaskManagement/Views/MenuBar/MenuBarView.swift`
- [ ] T045 [P] [US4] Create TimerDisplay component showing elapsed time (HH:MM:SS) with 1-second updates via Timer.publish in `TaskManagement/Views/MenuBar/TimerDisplay.swift`
- [ ] T046 [US4] Create DailyTimeView with date picker, entries grouped by todo, per-todo duration totals, daily total, review/export actions in `TaskManagement/Views/TimeTracking/DailyTimeView.swift`
- [ ] T047 [P] [US4] Create TimeEntryRow displaying start/end times, duration, notes, booking status badge, and edit/delete actions in `TaskManagement/Views/TimeTracking/TimeEntryRow.swift`
- [ ] T048 [US4] Create TimeEntriesView showing time entries for a specific todo with add manual entry action in `TaskManagement/Views/TodoDetail/TimeEntriesView.swift`
- [ ] T049 [US4] Add timer start/stop/pause controls to TodoDetailView and TodoRow in `TaskManagement/Views/TodoDetail/TodoDetailView.swift` and `TaskManagement/Views/TodoList/TodoRow.swift`
- [ ] T050 [US4] Wire MenuBarExtra in TaskManagementApp.swift to display MenuBarView with shared TimerService, showing running timer text in menu bar label
- [ ] T051 [US4] Implement basic Timension export: generate copy-ready formatted text summary (per-todo with Jira ticket ID if linked, duration, notes) with copy-to-clipboard action in `TaskManagement/Services/TimeEntryService.swift`

**Checkpoint**: User Story 4 fully functional — timers work with auto-save/recovery, daily review with export, menu bar shows active timer, midnight splitting works

---

## Phase 7: User Story 5 — Automatic App Time Detection (Priority: P5)

**Goal**: Monitor active browser window, detect Jira ticket IDs and Bitbucket PR numbers from window titles, match to linked todos, and suggest time attribution after 30+ seconds

**Independent Test**: Link a todo to Jira ticket "PROJ-123". Open that ticket in browser. Wait 30+ seconds. App suggests attributing time to the linked todo. Dismiss and open an unlinked ticket — app offers to create/link a new todo. Idle for 5+ minutes — idle time excluded. Disable detection in settings — no monitoring occurs.

### Implementation for User Story 5

- [ ] T052 [US5] Implement WindowDetectionService with NSWorkspace.didActivateApplicationNotification listener, Accessibility API for window titles, ScriptingBridge for Safari/Chrome tab titles, IOKit HIDIdleTime idle detection (30s check interval), 30-second dwell threshold, and enable/disable toggle in `TaskManagement/Services/WindowDetectionService.swift`
- [ ] T053 [US5] Add pattern matching logic to WindowDetectionService: extract Jira ticket IDs (`[A-Z]+-\d+`) and Bitbucket PR identifiers from browser window titles, match against linked JiraLink.ticketID and BitbucketLink entries
- [ ] T054 [US5] Create notification/suggestion UI: when match found after 30s dwell, show notification offering to attribute time; when no match, offer to create todo + link or dismiss; idle detection prompts
- [ ] T055 [US5] Add automatic detection toggle to SettingsView with `AXIsProcessTrusted()` permission check and prompt in `TaskManagement/Views/Settings/SettingsView.swift`
- [ ] T056 [US5] Wire WindowDetectionService start/stop to app lifecycle in `TaskManagementApp.swift`, respecting user enable/disable preference

**Checkpoint**: User Story 5 fully functional — automatic detection works for Jira and Bitbucket in browser, respects idle and 30s dwell, can be toggled off

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Refinements affecting multiple user stories

- [ ] T057 [P] Add credential expiry detection and re-authentication notification for Jira and Bitbucket in `TaskManagement/Services/SyncService.swift`
- [ ] T058 [P] Add broken-link handling: visual indicator on todos when linked Jira ticket or Bitbucket PR is deleted/unreachable in `TaskManagement/Views/TodoDetail/JiraLinkView.swift` and `TaskManagement/Views/TodoDetail/BitbucketLinkView.swift`
- [ ] T059 Implement purgeExpired scheduled task: auto-purge trashed todos older than 30 days on app launch in `TaskManagement/Services/TodoService.swift`
- [ ] T060 Performance validation: verify <2s launch, <200ms search over 500+ todos, 1s timer updates per plan.md performance goals
- [ ] T061 Run quickstart.md verification checklist: todo persistence after restart, menu bar timer, projects/tags filtering, keyboard shortcuts

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — no dependencies on other stories
- **US2 (Phase 4)**: Depends on Phase 2 — independent of US1 (but benefits from US1 views existing)
- **US3 (Phase 5)**: Depends on Phase 2 + Phase 4 (reuses HTTPClient, KeychainService, SyncService, SettingsView)
- **US4 (Phase 6)**: Depends on Phase 2 — independent of US2/US3 (but Timension export includes Jira ticket ID if linked)
- **US5 (Phase 7)**: Depends on Phase 2 + Phase 4 + Phase 5 + Phase 6 (needs Jira links, Bitbucket links, and time tracking to match and attribute)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no story dependencies
- **US2 (P2)**: Can start after Phase 2 — no story dependencies (introduces shared networking/keychain infra)
- **US3 (P3)**: Depends on US2 completion (reuses HTTPClient, KeychainService, SyncService, SettingsView)
- **US4 (P4)**: Can start after Phase 2 — no story dependencies (optional enrichment from US2 for Jira ticket ID in export)
- **US5 (P5)**: Depends on US2 + US3 + US4 (needs all integration links and time tracking)

### Within Each User Story

- Models before services
- Services before views
- Core views before integration/wiring views
- Wiring and keyboard shortcuts last

### Parallel Opportunities

- **Phase 2**: T005, T006, T007 (all models) can run in parallel after T004 (enums)
- **Phase 3 (US1)**: T010, T011, T012 (all services) can run in parallel; T013, T014, T016, T017 (independent view components) can run in parallel
- **Phase 4 (US2)**: T021, T022, T023, T024 (models + infra) can run in parallel; T028, T029 (config views) can run in parallel
- **Phase 5 (US3)**: T032, T036 can run in parallel
- **Phase 6 (US4)**: T041, T045, T047 can run in parallel
- **Cross-story**: US1 and US2 can proceed in parallel after Phase 2; US1 and US4 can proceed in parallel after Phase 2

---

## Parallel Example: User Story 1

```bash
# Launch all services for US1 together:
Task: "Implement TodoService in TaskManagement/Services/TodoService.swift"
Task: "Implement ProjectService in TaskManagement/Services/ProjectService.swift"
Task: "Implement TagService in TaskManagement/Services/TagService.swift"

# Launch independent view components for US1 together:
Task: "Create SidebarView in TaskManagement/Views/Sidebar/SidebarView.swift"
Task: "Create ProjectRow in TaskManagement/Views/Sidebar/ProjectRow.swift"
Task: "Create TodoRow in TaskManagement/Views/TodoList/TodoRow.swift"
Task: "Create SearchBar in TaskManagement/Views/TodoList/SearchBar.swift"
```

## Parallel Example: User Story 2

```bash
# Launch models + shared infra for US2 together:
Task: "Create JiraLink model in TaskManagement/Models/JiraLink.swift"
Task: "Create IntegrationConfig model in TaskManagement/Models/IntegrationConfig.swift"
Task: "Implement KeychainService in TaskManagement/Services/KeychainService.swift"
Task: "Implement HTTPClient in TaskManagement/Networking/HTTPClient.swift"

# Launch config views for US2 together:
Task: "Create JiraConfigView in TaskManagement/Views/Settings/JiraConfigView.swift"
Task: "Create SettingsView in TaskManagement/Views/Settings/SettingsView.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test todo management independently — create, edit, complete, delete, filter, search, persist
5. App is usable as a standalone native macOS todo manager

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US1 (Todo Management) → Test independently → **MVP!**
3. Add US2 (Jira Linking) → Test independently → Jira integration live
4. Add US3 (Bitbucket PR Linking) → Test independently → Full integration suite
5. Add US4 (Time Tracking) → Test independently → Time tracking with export
6. Add US5 (Automatic Detection) → Test independently → Full automation
7. Each story adds value without breaking previous stories

### Recommended Parallel Path

With sequential single-developer execution:

1. Phase 1 + Phase 2 (Setup + Foundation)
2. Phase 3 (US1 — MVP, must be first)
3. Phase 4 (US2 — Jira, introduces shared networking)
4. Phase 5 (US3 — Bitbucket, builds on US2 infra)
5. Phase 6 (US4 — Time Tracking, can interleave with US2/US3 but benefits from Jira link for export)
6. Phase 7 (US5 — Detection, needs all prior stories)
7. Phase 8 (Polish)

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks in the same phase
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable (except US3 depends on US2 infra, US5 depends on US2+US3+US4)
- Commit after each task or logical group
- Stop at any checkpoint to validate the story independently
- Timension booking integration (FR-020) is deferred per clarification — T051 provides basic copy-ready text export only
- No test tasks generated (not explicitly requested) — add per-story test phases if TDD desired
