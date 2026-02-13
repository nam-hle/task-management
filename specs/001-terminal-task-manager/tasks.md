# Tasks: Terminal Task Manager

**Input**: Design documents from `/specs/001-terminal-task-manager/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/, research.md, quickstart.md

**Tests**: Not explicitly requested in the feature specification. Test tasks are omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. US5 (Keyboard Navigation) is merged into US1 (Unified Dashboard) as they are inseparable — the dashboard IS keyboard-driven.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize Go project with module, dependencies, and directory skeleton

- [x] T001 Initialize Go 1.22+ module with `go mod init` and add all dependencies (bubbletea, lipgloss, bubbles, huh, glamour, go-jira, go-imap, go-message, anthropic-sdk-go, keyring, modernc sqlite, sqlx, viper) to go.mod
- [x] T002 Create directory structure per plan.md: cmd/taskmanager/, internal/app/, internal/ui/tasklist/, internal/ui/detail/, internal/ui/config/, internal/ui/ai/, internal/ui/help/, internal/ui/command/, internal/source/jira/, internal/source/bitbucket/, internal/source/email/, internal/model/, internal/store/, internal/sync/, internal/ai/, internal/credential/, internal/crossref/
- [x] T003 Create minimal main.go entry point with Bubble Tea program initialization (tea.NewProgram with WithAltScreen) and Viper config loading in cmd/taskmanager/main.go

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core models, interfaces, store, and TUI scaffold that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 [P] Define unified Task struct with all fields (ID, SourceType, SourceItemID, Title, Status, Priority, Assignee, Author, SourceURL, CreatedAt, UpdatedAt, FetchedAt, RawData, CrossRefs) and status/priority normalization constants per data-model.md in internal/model/task.go
- [x] T005 [P] Define Configuration struct with source list, AI settings, display preferences, and Viper-based YAML loading/saving for ~/.config/taskmanager/config.yaml in internal/model/config.go
- [x] T006 [P] Define Notification struct (ID, TaskID, SourceType, Message, Read, CreatedAt) in internal/model/notification.go
- [x] T007 [P] Define Source interface (Type, ValidateConnection, FetchItems, GetItemDetail, GetActions, ExecuteAction, Search) and shared types (FetchOptions, FetchResult, ItemDetail, Action, Comment) per contracts/source.go in internal/source/source.go
- [x] T008 [P] Implement system keyring credential wrapper with Get, Set, Delete operations using 99designs/keyring with encrypted-file fallback in internal/credential/keyring.go
- [x] T009 [P] Define Lip Gloss theme constants and style functions for list items, detail panels, status badges (Open/In Progress/Review/Done), priority colors (1-5), source labels, and borders in internal/app/theme.go
- [x] T010 Implement SQLite store initialization with schema migrations (sources, tasks, notifications, schema_version tables with indexes) using modernc.org/sqlite + sqlx per data-model.md DDL in internal/store/sqlite.go and internal/store/migrations.go
- [x] T011 Implement store interface with CRUD operations: UpsertTasks, GetTasks (with filters), GetTaskByID, UpsertSource, GetSources, DeleteSource, CreateNotification, GetUnreadNotifications, MarkNotificationRead in internal/store/store.go
- [x] T012 Implement multi-panel layout manager (header bar with app title + source status, main content area, status bar with keybinding hints) with terminal resize handling via tea.WindowSizeMsg in internal/ui/layout.go
- [x] T013 Create root Bubble Tea model with view state enum (List, Detail, Config, AI, Help, Command) and basic Init/Update/View routing skeleton in internal/app/app.go

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 + 5 — Unified Task Dashboard + Keyboard Navigation (Priority: P1) 🎯 MVP

**Goal**: Display all tasks from configured sources in a single navigable list with vim-style keyboard shortcuts, filtering, sorting, detail view, help overlay, and command palette

**Independent Test**: Launch the app with at least one configured source, verify tasks appear in a flat list, navigate with j/k, open detail with Enter, filter by source with 1-3, search with /, use : for command palette, press ? for help, press r for manual refresh

### Implementation

- [x] T014 [US1] Define global keybinding map using bubbles/key (j/k navigate, Enter select, Esc/q back, / search, : command, ? help, r refresh, 1-3 source filter, a AI, c comment, t transition, p approve, Tab sort cycle) in internal/app/keys.go
- [x] T015 [P] [US1] Implement task list item renderer with source icon/label (JIRA/BB/EMAIL), truncated title, status badge with color, priority indicator, assignee, and relative timestamp using Lip Gloss styles in internal/ui/tasklist/item.go
- [x] T016 [US1] Implement task list Bubble Tea model with vim navigation (j/k), item selection (Enter dispatches to detail), and back (Esc) using bubbles/list in internal/ui/tasklist/model.go
- [x] T017 [US1] Implement filtering: source type (keys 1-3 toggle), status filter, priority filter, and free-text search (/ enters search mode with bubbles/textinput) in internal/ui/tasklist/model.go
- [x] T018 [US1] Implement sort cycling (Tab key) through: updated date desc, priority asc, source type, status in internal/ui/tasklist/model.go
- [x] T019 [US1] Implement task detail view with glamour-rendered body, metadata key-value pairs (project, type, labels, due date), comments list with author/timestamp, and available actions list in internal/ui/detail/model.go
- [x] T020 [P] [US1] Implement help overlay showing context-sensitive keybindings for current view using bubbles/help with key.Binding descriptions in internal/ui/help/model.go
- [x] T021 [P] [US1] Implement command palette (: trigger) as filtered action list overlay using bubbles/list with fuzzy matching for commands (refresh, configure, quit, filter, sort) in internal/ui/command/model.go
- [x] T022 [US1] Implement background polling orchestrator: per-source goroutines with configurable tick intervals, manual refresh trigger (r key), sync results dispatched as tea.Msg, source sync state tracking (Idle/Syncing/Error) in internal/sync/poller.go
- [x] T023 [US1] Wire all views into root model: list ↔ detail navigation, help overlay toggle (?), command palette toggle (:), search mode (/), and view-specific key delegation in internal/app/app.go
- [x] T024 [US1] Implement empty state view with guidance when no tasks exist ("No tasks found") and when no sources are configured ("Press : then 'configure' to add a source") in internal/ui/tasklist/model.go
- [x] T025 [US1] Implement staleness indicator (dimmed text or warning icon) on task list items when source last_sync_at exceeds poll_interval_sec in internal/ui/tasklist/item.go

**Checkpoint**: Core TUI shell is functional — navigable task list, detail view, filtering, sorting, help, command palette. Ready for real source data.

---

## Phase 4: User Story 2 — Jira Integration (Priority: P1)

**Goal**: Connect to Jira Server/DC, fetch assigned issues, view issue details with rendered descriptions, transition issue statuses, and add comments

**Independent Test**: Configure a Jira Server/DC PAT, launch the app, verify assigned issues appear in the list filtered by Jira source, open an issue to see rendered description and comments, perform a status transition, and add a comment

### Implementation

- [x] T026 [P] [US2] Define Jira response types (SearchResponse, Issue, IssueFields, Status, StatusCategory, Priority, IssueType, User, Transition, TransitionFields, Comment, Project) matching REST API v2 JSON in internal/source/jira/types.go
- [x] T027 [US2] Initialize go-jira v2 (andygrunwald/go-jira) client with base URL and Bearer PAT auth, wrap with rate limiting middleware (429 + Retry-After + exponential backoff, max 3 retries), configurable timeout (30s default) in internal/source/jira/client.go
- [x] T028 [US2] Implement Jira FetchItems: POST /rest/api/2/search with configurable default JQL (assignee=currentUser()), field selection (summary, status, priority, assignee, issuetype, project, created, updated), startAt/maxResults pagination in internal/source/jira/adapter.go
- [x] T029 [US2] Implement Jira status normalization (first check status name for "review" keyword→Review, then fall back to statusCategory.key: new→Open, indeterminate→In Progress, done→Done) and priority normalization (Blocker/Critical→1, High→2, Medium→3, Low→4, Lowest→5) in internal/source/jira/adapter.go
- [x] T030 [US2] Implement Jira GetItemDetail: GET /rest/api/2/issue/{key}?expand=renderedFields,transitions, convert renderedFields HTML to terminal text, extract comments from fields.comment in internal/source/jira/adapter.go
- [x] T031 [US2] Implement Jira GetActions: extract transitions from expanded issue data, map to Action{ID, Name}. Implement ExecuteAction for transitions: POST /rest/api/2/issue/{key}/transitions with transition.id and optional resolution fields in internal/source/jira/adapter.go
- [x] T032 [US2] Implement Jira comment action: POST /rest/api/2/issue/{key}/comment with plain text body in internal/source/jira/adapter.go
- [x] T033 [US2] Implement Jira Search: POST /rest/api/2/search with JQL text~"{query}" AND assignee=currentUser() in internal/source/jira/adapter.go
- [x] T034 [US2] Implement Jira ValidateConnection: GET /rest/api/2/myself, return displayName on success, handle 401 with clear auth error in internal/source/jira/adapter.go
- [x] T035 [US2] Wire Jira adapter into app: register with poller, feed fetched tasks to store, add transition selection UI (list of available transitions) and comment input (textarea popup) to detail view in internal/app/app.go and internal/ui/detail/model.go

**Checkpoint**: Jira integration is complete — the app functions as a terminal Jira client. MVP is deliverable.

---

## Phase 5: User Story 6 — Source Configuration (Priority: P2)

**Goal**: Provide an in-app configuration UI for adding, editing, testing, and removing source connections with secure credential storage

**Independent Test**: Launch the app with no config, verify the first-run setup guide appears, add a Jira source via the form, validate the connection succeeds, verify tasks load after setup, then remove the source and confirm cached data is cleared

### Implementation

- [ ] T036 [US6] Implement source type selection form (Jira, Bitbucket, Email options) with descriptions using huh.NewSelect in internal/ui/config/model.go
- [ ] T037 [US6] Implement Jira configuration form fields (base URL with URL validation, personal access token as password input, optional default JQL) using huh.NewForm with field-level validation in internal/ui/config/model.go
- [ ] T038 [P] [US6] Implement Bitbucket configuration form fields (base URL, personal access token) using huh.NewForm in internal/ui/config/model.go
- [ ] T039 [P] [US6] Implement Email configuration form fields (IMAP host, IMAP port, SMTP host, SMTP port, username, password, TLS toggle) using huh.NewForm in internal/ui/config/model.go
- [ ] T040 [US6] Implement connection validation step: show spinner during ValidateConnection call, display success (authenticated user name) or error message with retry option in internal/ui/config/model.go
- [ ] T041 [US6] Implement first-run detection (no sources in config) and automatic entry into guided setup flow, with option to add more sources or start the app in internal/app/app.go
- [ ] T042 [US6] Implement source list management view: list configured sources with status, add new source, edit existing source, remove source (with confirmation), persist changes via Viper config write in internal/ui/config/model.go
- [ ] T043 [US6] Integrate credential storage: save PATs/passwords to system keyring via credential wrapper, store cred: reference prefix in config YAML, load credentials from keyring on source initialization in internal/ui/config/model.go

**Checkpoint**: Users can configure sources entirely within the app. First-run experience guides new users smoothly.

---

## Phase 6: User Story 3 — Bitbucket Integration (Priority: P2)

**Goal**: Connect to Bitbucket Server/DC, fetch authored and review-requested PRs, view PR details with build status and reviewers, approve PRs, and add comments. Cross-reference Jira issues from PR metadata.

**Independent Test**: Configure a Bitbucket Server PAT, launch the app, verify PRs appear filtered by Bitbucket, open a PR to see description, build status, and reviewer status, approve the PR, add a comment, and verify Jira cross-references appear

### Implementation

- [ ] T044 [P] [US3] Define Bitbucket response types (PaginatedResponse, PullRequest, Participant, Ref, Repository, Project, BuildStatus, Activity, Comment, DiffResponse, DiffHunk) with Unix epoch ms timestamp handling in internal/source/bitbucket/types.go
- [ ] T045 [US3] Implement Bitbucket HTTP client: base URL config, Bearer PAT auth, pagination helpers (start/limit/isLastPage/nextPageStart loop), rate limiting (429 + Retry-After), timeout in internal/source/bitbucket/client.go
- [ ] T046 [US3] Implement Bitbucket FetchItems: GET /rest/api/1.0/inbox/pull-requests for role=REVIEWER and role=AUTHOR, merge and deduplicate results, normalize status (OPEN→Open, MERGED→Done, DECLINED→Done) and priority (Changes Requested→2, Needs Review→3, Approved→4) in internal/source/bitbucket/adapter.go
- [ ] T047 [US3] Implement Bitbucket GetItemDetail: GET PR detail + GET activities (comments, approvals) + GET /rest/build-status/1.0/commits/{fromRef.latestCommit} for build status, compose ItemDetail with reviewer list and build results in internal/source/bitbucket/adapter.go
- [ ] T048 [US3] Implement Bitbucket PR diff retrieval via GET /rest/api/1.0/projects/{key}/repos/{slug}/pull-requests/{id}/diff, parse structured diff response (file paths, hunks, added/removed/context segments), render file change summary and diff hunks with syntax coloring in PR detail view in internal/source/bitbucket/adapter.go and internal/ui/detail/model.go
- [ ] T049 [US3] Implement Bitbucket actions: approve (POST .../approve), unapprove (DELETE .../approve), comment (POST .../comments with Markdown text body) in internal/source/bitbucket/adapter.go
- [ ] T050 [US3] Implement Bitbucket ValidateConnection: GET /plugins/servlet/applinks/whoami for username, then GET /rest/api/1.0/users/{username} for display name in internal/source/bitbucket/adapter.go
- [ ] T051 [US3] Implement Jira-Bitbucket cross-reference matcher: extract Jira issue keys from PR fromRef.displayId (branch name), title, and description using regex `([A-Z][A-Z0-9]+-\d+)`, match against cached Jira task IDs, populate CrossRefs field bidirectionally in internal/crossref/crossref.go
- [ ] T052 [US3] Wire Bitbucket adapter into app: register with poller, display build status icons and reviewer approval status in detail view, show cross-reference links to related Jira issues in internal/app/app.go and internal/ui/detail/model.go

**Checkpoint**: Bitbucket PRs appear alongside Jira issues with diff viewing. Cross-references link related items across sources.

---

## Phase 7: User Story 7 — AI Assistant Prompt (Priority: P2)

**Goal**: Open a text prompt to ask Claude natural language questions about tasks across all sources. AI searches, summarizes, and returns results with source references. Streaming responses for real-time display. Read-only — no write operations.

**Independent Test**: Press 'a' to open AI panel, type "show me all high priority Jira issues", verify streaming response with source references, select a result to navigate to its detail view, ask a follow-up question using prior context, ask the AI to perform a write action and verify it declines with a helpful suggestion

### Implementation

- [ ] T053 [P] [US7] Implement conversation context manager: append user/assistant messages, enforce max 20 message history, reset on session close, track task_refs per message in internal/ai/context.go
- [ ] T054 [US7] Implement AI assistant service: initialize Claude client (anthropic-sdk-go), compose system prompt per contracts/ai.go template with task_summary from store, define tool schemas (search_tasks with query/source_type/status/priority params, get_task_detail with task_id param), handle streaming responses via channel in internal/ai/assistant.go
- [ ] T055 [US7] Implement AI panel Bubble Tea model: textarea input at bottom, viewport for scrolling conversation history, streaming token display via tea.Cmd subscription, selectable task references in responses in internal/ui/ai/model.go
- [ ] T056 [US7] Implement AI tool-use handlers: search_tasks queries SQLite store with filters and returns matching task summaries, get_task_detail fetches full task from store and returns formatted detail in internal/ai/assistant.go
- [ ] T057 [US7] Implement read-only guard in system prompt and response handler: detect write-action intent (transition, comment, approve, archive), return polite decline message with specific manual keyboard shortcut suggestion in internal/ai/assistant.go
- [ ] T058 [US7] Wire AI panel into root model: 'a' keybinding opens panel, Esc closes and resets conversation, selecting a task reference in AI results navigates to detail view, handle API key missing with config prompt in internal/app/app.go

**Checkpoint**: AI assistant provides natural language search across all sources. Streaming responses and conversational context work for follow-ups.

---

## Phase 8: User Story 4 — Email Integration (Priority: P3)

**Goal**: Connect to IMAP email, fetch inbox messages, view email content rendered as text, reply via SMTP, archive, flag, and toggle read status

**Independent Test**: Configure an IMAP email account, launch the app, verify inbox emails appear filtered by email source, open an email to read text-rendered content with attachment list, archive an email, flag another, and send a reply

### Implementation

- [ ] T059 [P] [US4] Define email-specific types (Envelope with From/Subject/Date/Flags, ParsedMessage with text body and attachment metadata, SMTPConfig) in internal/source/email/types.go
- [ ] T060 [US4] Implement IMAP client wrapper: connect with TLS/STARTTLS, authenticate (PLAIN/LOGIN/XOAUTH2), SELECT INBOX, SEARCH recent messages (last 7 days or last 100), FETCH envelope data, FETCH full body, IDLE support for push notifications using emersion/go-imap v2 in internal/source/email/client.go
- [ ] T061 [US4] Implement Email FetchItems: SEARCH + FETCH envelopes, map to Task with Subject→Title, From→Author, Unread→Open/Read→In Progress/Archived→Done status, Flagged+Unread→priority 2/Unread→3/Read→5 in internal/source/email/adapter.go
- [ ] T062 [US4] Implement Email GetItemDetail: FETCH BODY[], parse MIME structure with go-message, extract text/plain or convert text/html to text, list attachment filenames and sizes in metadata in internal/source/email/adapter.go
- [ ] T063 [US4] Implement SMTP reply action: connect to configured SMTP server with TLS/STARTTLS, authenticate, compose reply (Re: subject, In-Reply-To + References headers, plain text body, From/To headers) in internal/source/email/client.go
- [ ] T064 [US4] Implement email flag actions: archive (MOVE to Archive folder or STORE +FLAGS \Deleted), flag/unflag (STORE ±FLAGS \Flagged), mark read/unread (STORE ±FLAGS \Seen) in internal/source/email/adapter.go
- [ ] T065 [US4] Implement Email ValidateConnection: IMAP connect, authenticate, SELECT INBOX, return authenticated email address as display name in internal/source/email/adapter.go
- [ ] T066 [US4] Wire Email adapter into app: register with poller, add reply/archive/flag actions to detail view, handle IDLE-based push updates as tea.Msg in internal/app/app.go

**Checkpoint**: Email inbox is unified with Jira and Bitbucket. All three sources work together in the flat list.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and production readiness

- [ ] T067 [P] Implement token expiration detection (401 responses) and in-app re-authentication prompt without restart across all source adapters in internal/source/source.go
- [ ] T068 [P] Implement notification system: detect new/updated items during sync, create Notification records, show unread count badge in header bar in internal/sync/poller.go and internal/ui/layout.go
- [ ] T069 Implement on-demand pagination for large result sets (>50 items) with lazy loading on scroll-to-bottom in internal/ui/tasklist/model.go
- [ ] T070 Performance profiling and optimization: ensure <200ms input-to-render with 1,000+ cached items, optimize SQLite queries with proper index usage in internal/ui/tasklist/model.go and internal/store/sqlite.go
- [ ] T071 Validate quickstart.md end-to-end: follow setup steps on clean machine, verify build, config, and all source connections work as documented
- [ ] T072 Final code cleanup: consistent error messages across sources, edge case handling (empty states, network failures, malformed responses), remove debug logging

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **US1+US5 Dashboard (Phase 3)**: Depends on Foundational (Phase 2)
- **US2 Jira (Phase 4)**: Depends on Phase 3 (needs TUI list/detail views to display data)
- **US6 Config (Phase 5)**: Depends on Phase 2; recommended after Phase 4 so config forms can be tested with Jira
- **US3 Bitbucket (Phase 6)**: Depends on Phase 2; cross-ref (T051) benefits from Jira data being active
- **US7 AI Assistant (Phase 7)**: Depends on Phase 2 + store (T010-T011) for tool-use queries
- **US4 Email (Phase 8)**: Depends on Phase 2; fully independent of other sources
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1+US5 (P1)**: After Foundational — no dependencies on other stories
- **US2 Jira (P1)**: After US1 (needs TUI shell to display data) — first real source validates architecture
- **US6 Config (P2)**: After Foundational — independent but best tested after US2
- **US3 Bitbucket (P2)**: After Foundational — independent, cross-ref best tested with Jira active
- **US7 AI (P2)**: After Foundational — independent, most useful with source data present
- **US4 Email (P3)**: After Foundational — fully independent of all other stories

### Within Each User Story

- Types/models before client implementation
- Client before adapter (adapter uses client)
- Adapter before UI wiring (UI dispatches to adapter)
- Core read operations before write actions

### Parallel Opportunities

**Phase 2 (Foundational)**:
```
Parallel: T004, T005, T006, T007, T008, T009 (all separate files)
Sequential: T010 (store, needs models) → T011 (store interface)
Sequential: T012 (layout) → T013 (root model)
```

**Phase 3 (US1+US5)**:
```
Parallel: T015 (item renderer), T020 (help), T021 (command palette)
Sequential: T014 (keys) → T016 (list model) → T017 (filter) → T018 (sort)
Sequential: T019 (detail) → T023 (wire routing)
Then: T022 (poller), T024 (empty state), T025 (staleness)
```

**Phase 4 (US2 Jira)**:
```
T026 (types) first
Then: T027 (client) → T028-T034 (adapter methods, partially parallelizable)
Then: T035 (wire + UI actions)
```

**Phase 6 (US3 Bitbucket)**:
```
T044 (types) first
Then: T045 (client) → T046-T050 (adapter methods including diff)
Then: T051 (cross-ref) → T052 (wire)
```

**Cross-story parallelism (after Phase 2 completes)**:
```
With 2 developers:
  Dev A: Phase 3 (US1+US5) → Phase 4 (US2) → Phase 8 (US4)
  Dev B: Phase 5 (US6) → Phase 6 (US3) → Phase 7 (US7)
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: US1+US5 (Dashboard + Navigation)
4. Complete Phase 4: US2 (Jira Integration)
5. **STOP and VALIDATE**: Test with a real Jira Server/DC instance
6. The app is a functional terminal Jira client — MVP is deliverable

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. US1+US5 → TUI shell with navigation → Internal demo
3. US2 Jira → First real source → **MVP!**
4. US6 Config → Smooth in-app setup → Usability milestone
5. US3 Bitbucket → Multi-source unified view → Major milestone
6. US7 AI → Smart natural language search → Differentiator
7. US4 Email → Complete unified inbox → Full feature set
8. Polish → Production-ready release

---

## Notes

- [P] tasks = different files, no dependencies within that phase
- [Story] label maps task to specific user story for traceability
- US5 (Keyboard Navigation) is merged into US1 — they are inseparable
- No test tasks generated (not explicitly requested in spec)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
