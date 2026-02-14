# Tasks: Application & Browser Time Tracking

**Input**: Design documents from `/specs/005-app-time-tracking/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested — test tasks omitted. Add test phases if needed.

**Organization**: Tasks grouped by user story. MVP = US1 (Active App Tracking) + manual timer only.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- All paths relative to `TaskManagement/Sources/`

---

## Phase 1: Setup

**Purpose**: Create directory structure for new feature areas

- [x] T001 Create directory structure: `Views/TimeTracking/`, `Views/Settings/`, `Views/Permissions/`, `Networking/` under `TaskManagement/Sources/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Models, enums, and permission infrastructure that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Extend TimeEntry model with `applicationName: String?`, `applicationBundleID: String?`, and `label: String?` fields in `TaskManagement/Sources/Models/TimeEntry.swift`
- [x] T003 [P] Create TrackedApplication `@Model` with id, name, bundleIdentifier (unique), isBrowser, isPreConfigured, isEnabled, sortOrder, createdAt in `TaskManagement/Sources/Models/TrackedApplication.swift`
- [x] T004 [P] Extend `TaskManagement/Sources/Models/Enums.swift`: add `BookingStatus.booked` case, `EntrySource.wakatime` case, new `TrackingState` enum (idle/tracking/paused/permissionRequired), new `PauseReason` enum (userPaused/systemIdle/systemSleep/screenLocked/manualTimerActive)
- [x] T005 Register TrackedApplication in ModelContainer schema array in `TaskManagement/Sources/TaskManagementApp.swift`
- [x] T006 [P] Create AccessibilityPermissionView in `TaskManagement/Sources/Views/Permissions/AccessibilityPermissionView.swift` — check `AXIsProcessTrusted()`, explain why permission is needed, "Open System Settings" button deep-linking to `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`, poll every 1s until granted, add `NSAccessibilityUsageDescription` to Info.plist

**Checkpoint**: Foundation ready — US1 implementation can begin

---

## Phase 3: User Story 1 — Active Application Time Tracking (Priority: P1) MVP

**Goal**: Automatically track which application is active, record time entries per app, handle idle/sleep/lock, display daily usage, support manual timer. This is the complete MVP.

**Independent Test**: Start tracker, switch between 3-4 apps for 10 minutes, verify time segments recorded with correct durations and app names. Let computer idle >5min and verify idle time excluded. Start/stop a manual timer and verify entry created.

### Core Services

- [x] T007 [P] [US1] Implement WindowMonitorService in `TaskManagement/Sources/Services/WindowMonitorService.swift` — observe `NSWorkspace.didActivateApplicationNotification` for app switches, use `AXUIElementCreateApplication(pid)` + `kAXFocusedWindowAttribute` + `kAXTitleAttribute` to read window title, expose `onApplicationChanged` callback with ApplicationInfo (name, bundleID, pid, windowTitle, timestamp). Confine all AX calls to a dedicated actor for Swift 6 concurrency safety.
- [x] T008 [P] [US1] Implement IdleDetectionService in `TaskManagement/Sources/Services/IdleDetectionService.swift` — poll IOKit `HIDIdleTime` every 30s via `IOServiceMatching("IOHIDSystem")` (use `kIOMainPortDefault`), observe `NSWorkspace.willSleepNotification`/`didWakeNotification`, observe `DistributedNotificationCenter` for `com.apple.screenIsLocked`/`com.apple.screenIsUnlocked` and screensaver notifications, expose callbacks: onIdleStarted, onIdleEnded, onSleepStarted, onWakeUp, onScreenLocked, onScreenUnlocked. Configurable idle threshold (default 5 min).
- [x] T009 [US1] Implement TimeEntryService in `TaskManagement/Sources/Services/TimeEntryService.swift` — use `@ModelActor` for background SwiftData writes. Methods: `create(todoID:, applicationName:, bundleID:, source:, startTime:)`, `finalize(entryID:, endTime:)`, `autoSave(entryID:, currentTime:)` (persist duration every 60s), `splitAtMidnight(entryID:)` (split entries crossing midnight into two), `entries(for date:)` (fetch by date). Always use `PersistentIdentifier` across actor boundaries, never pass model objects. Use `Task.detached` for true background execution.
- [x] T010 [US1] Implement TrackingCoordinator in `TaskManagement/Sources/Services/TrackingCoordinator.swift` — `@Observable` class that orchestrates WindowMonitorService, IdleDetectionService, and TimeEntryService. State machine: idle → tracking → paused(reason) → tracking. On app switch: check 30s minimum threshold (configurable), if exceeded finalize previous entry and create new one, if under threshold ignore switch. On idle start: pause current entry. On wake/unlock: resume. Auto-save timer every 60s. Midnight split check. Manual timer mode: suppress auto-tracking, create manual entry with label. Enforce single active timer.
- [x] T011 [US1] Wire TimerManager to TrackingCoordinator in `TaskManagement/Sources/TaskManagementApp.swift` — replace stub TimerManager with real TrackingCoordinator. Pass ModelContainer to coordinator. Update `@State private var timerManager` to use coordinator's state for menu bar display (active app name, elapsed time, isRunning).

### Data Seeding

- [x] T012 [P] [US1] Implement first-launch seed for TrackedApplication defaults in `TaskManagement/Sources/Services/TimeEntryService.swift` or a dedicated seeder — on first launch (no TrackedApplication records exist), insert: Google Chrome (`com.google.Chrome`, isBrowser: true, isPreConfigured: true, isEnabled: true), Firefox (`org.mozilla.firefox`, isBrowser: true, isPreConfigured: true, isEnabled: true). Insert suggested but disabled: IntelliJ IDEA (`com.jetbrains.intellij`), Xcode (`com.apple.dt.Xcode`), VS Code (`com.microsoft.VSCode`), Terminal (`com.apple.Terminal`), Slack (`com.tinyspeck.slackmacgap`).

### UI

- [x] T013 [P] [US1] Create TimeTrackingDashboard in `TaskManagement/Sources/Views/TimeTracking/TimeTrackingDashboard.swift` — `@Query` time entries for today, group by applicationName, show per-app total duration with app icon/name, daily total at top, live-updating current entry with running timer. Use `@Observable` TrackingCoordinator for real-time elapsed time. Sort apps by total time descending.
- [x] T014 [P] [US1] Create TimeEntryRow in `TaskManagement/Sources/Views/TimeTracking/TimeEntryRow.swift` — compact row displaying: app name, duration (formatted HH:MM:SS), start-end time range, source indicator (auto/manual), in-progress indicator for active entry.
- [x] T015 [US1] Create TrackedAppsSettingsView in `TaskManagement/Sources/Views/Settings/TrackedAppsSettingsView.swift` — list all TrackedApplication records, toggle isEnabled per app, "Add Application" button to pick from running apps (via `NSWorkspace.shared.runningApplications`), show pre-configured apps (Chrome/Firefox) with non-removable badge, suggested apps section.
- [x] T016 [P] [US1] Create TrackingSettingsView in `TaskManagement/Sources/Views/Settings/TrackingSettingsView.swift` — configurable: idle timeout (default 300s), minimum switch duration (default 30s), auto-save interval (default 60s). Use Stepper or Slider controls. Persist to UserDefaults or a settings model.
- [x] T017 [US1] Create SettingsView container in `TaskManagement/Sources/Views/Settings/SettingsView.swift` — TabView with tabs: "Tracked Apps" (TrackedAppsSettingsView), "Tracking" (TrackingSettingsView). Register as Settings scene in TaskManagementApp.swift.
- [x] T018 [US1] Extend ContentView in `TaskManagement/Sources/Views/ContentView.swift` — add "Time Tracking" item to sidebar navigation, selecting it shows TimeTrackingDashboard in the detail area. Add appropriate SF Symbol icon.
- [x] T019 [US1] Wire MenuBarView in `TaskManagement/Sources/Views/MenuBar/MenuBarView.swift` — replace stub start/stop buttons with real actions calling TrackingCoordinator.startTracking()/stopTracking(). Show current app name and elapsed time when tracking. Show "Start Tracking" button when idle. Add "Manual Timer" quick action with label input.

### Manual Timer & Recovery

- [x] T020 [US1] Implement manual timer in TrackingCoordinator — `startManualTimer(label:, todoID:)` creates a new TimeEntry with source `.manual` and the given label, suppresses WindowMonitorService callbacks until stopped. `stopManualTimer()` finalizes the entry and resumes auto-tracking. Starting a new timer while one runs stops the current one first.
- [x] T021 [US1] Add accessibility permission check on app launch in `TaskManagement/Sources/TaskManagementApp.swift` — on appear, check `AXIsProcessTrusted()`. If false, show AccessibilityPermissionView as an overlay/sheet on ContentView. Once granted, dismiss and enable tracking. Manual timers remain functional regardless of permission state.
- [x] T022 [US1] Implement crash recovery in TrackingCoordinator — on init, query TimeEntry where `isInProgress == true`. For each, calculate duration from startTime to last auto-save timestamp (or createdAt), finalize with that end time. Log recovered entries count.

**Checkpoint**: MVP complete. User can start tracking, see daily app breakdown, use manual timer, configure tracked apps. Verify all 5 acceptance scenarios from US1 pass.

---

## Phase 4: User Story 2 — Browser Tab Context Detection (Priority: P2)

**Goal**: When Firefox or Chrome is active, extract Jira ticket IDs and Bitbucket PR numbers from tabs and attach to time entries. Auto-link to matching todos.

**Independent Test**: Open Jira ticket in Firefox and Bitbucket PR in Chrome, track for 2+ minutes each, verify entries include ticket ID and PR number.

- [ ] T023 [P] [US2] Create BrowserContextRule `@Model` in `TaskManagement/Sources/Models/BrowserContextRule.swift` — fields per data-model.md: id, name, contextType, titlePattern, urlPattern?, extractionGroup, isEnabled, isBuiltIn, sortOrder. Register in ModelContainer.
- [ ] T024 [P] [US2] Create BrowserContextData Codable struct in `TaskManagement/Sources/Models/BrowserContextData.swift` — fields: contextType, ticketID?, ticketSummary?, prNumber?, repositorySlug?, prTitle?, rawTabTitle, tabURL?, browserName. Add `browserContext: BrowserContextData?` field to TimeEntry model.
- [ ] T025 [US2] Implement BrowserContextService in `TaskManagement/Sources/Services/BrowserContextService.swift` — Chrome: use NSAppleScript to get `title of active tab of front window` and `URL of active tab of front window`. Firefox: parse window title by stripping ` - Mozilla Firefox` / ` - Firefox` suffix. Apply BrowserContextRule patterns (regex) against title/URL to extract identifiers. Return BrowserContextData or nil.
- [ ] T026 [US2] Integrate BrowserContextService into TrackingCoordinator — when active app is a browser (TrackedApplication.isBrowser == true), call BrowserContextService to extract context. Attach BrowserContextData to the TimeEntry. When tab changes (different context detected), treat as app switch subject to 30s threshold.
- [ ] T027 [US2] Implement auto-linking in TrackingCoordinator — when BrowserContextData contains a Jira ticketID, query all Todos with JiraLink.ticketID matching. If found, set timeEntry.todo to that todo. Same for Bitbucket: match prNumber + repositorySlug against BitbucketLink. If no match, leave timeEntry.todo nil (unlinked).
- [ ] T028 [US2] Seed default BrowserContextRules on first launch — Jira: titlePattern `([A-Z][A-Z0-9]+-\\d+)`, contextType "jira", extractionGroup 1, isBuiltIn true. Bitbucket: titlePattern `Pull request #(\\d+)`, urlPattern `pull-requests/(\\d+)`, contextType "bitbucket", extractionGroup 1, isBuiltIn true.
- [ ] T029 [P] [US2] Extend TimeEntryRow in `TaskManagement/Sources/Views/TimeTracking/TimeEntryRow.swift` — when browserContext is present, show ticket ID badge (e.g., "PROJ-123") or PR badge (e.g., "PR #42 · my-repo") instead of generic app name. Show linked todo title if auto-linked.
- [ ] T030 [P] [US2] Extend TimeTrackingDashboard — group entries by browser context when available (group by Jira ticket or Bitbucket PR), not just by app name. Show context-specific totals.

**Checkpoint**: Browser context detection working. Jira/Bitbucket identifiers extracted and displayed. Auto-linking to matching todos functional.

---

## Phase 5: User Story 3 — Review and Edit Tracked Time Entries (Priority: P3)

**Goal**: Review daily entries, merge short entries, split long ones, adjust times, add notes, mark as reviewed.

**Independent Test**: Generate sample entries, merge two, split one, adjust a duration, add a note — verify all changes persist.

- [ ] T031 [US3] Extend TimeEntryService with merge in `TaskManagement/Sources/Services/TimeEntryService.swift` — `merge(entryIDs:)`: combine N entries into one with summed duration, earliest startTime, latest endTime, concatenated notes. Delete merged entries, return new entry ID.
- [ ] T032 [US3] Extend TimeEntryService with split — `split(entryID:, at splitTime:)`: create two entries from one, first entry ends at splitTime, second starts at splitTime. Both retain original context (browserContext, applicationName, todo link).
- [ ] T033 [US3] Extend TimeEntryService with edit — `update(entryID:, changes:)`: update startTime, endTime (recalculate duration), notes, todo link, bookingStatus. Mark source as `.edited` if times changed.
- [ ] T034 [US3] Extend TimeEntryService with review — `markReviewed(entryIDs:)`: bulk update bookingStatus from `.unreviewed` to `.reviewed`.
- [ ] T035 [P] [US3] Create TimeEntryListView in `TaskManagement/Sources/Views/TimeTracking/TimeEntryListView.swift` — list all entries for selected date, grouped by context (app/ticket/PR). Support multi-selection. Toolbar actions: "Merge Selected", "Mark Reviewed", "Mark All Reviewed". Date picker to navigate days. Show review status badges.
- [ ] T036 [P] [US3] Create TimeEntryDetailView in `TaskManagement/Sources/Views/TimeTracking/TimeEntryDetailView.swift` — edit form: start time picker, end time picker (auto-recalculates duration), notes TextEditor, todo picker (link/unlink), booking status display. "Split at Time" action with time picker. Source indicator (auto/manual/edited).
- [ ] T037 [US3] Add review status indicators across views — unreviewed: no badge. reviewed: checkmark badge. auto-approved: robot/sparkle badge. exported: export badge. booked: double-check badge. Apply to TimeEntryRow, TimeEntryListView, TimeTrackingDashboard.

**Checkpoint**: Full review workflow functional. Merge, split, edit, mark reviewed all working.

---

## Phase 6: User Story 5 — Export Formatted Time Summary (Priority: P5)

**Goal**: Generate copy-ready formatted summary of reviewed entries for Timension booking.

**Independent Test**: Prepare reviewed entries, trigger export, verify formatted output is correct and copyable.

- [ ] T038 [P] [US5] Create ExportRecord `@Model` in `TaskManagement/Sources/Models/ExportRecord.swift` — fields per data-model.md: id, exportedAt, formattedOutput, entryCount, totalDuration, isBooked, bookedAt?, timeEntries relationship. Register in ModelContainer.
- [ ] T039 [US5] Implement ExportService in `TaskManagement/Sources/Services/ExportService.swift` — `generateExport(for date:)`: fetch reviewed entries for date, group by context (Jira ticket > Bitbucket PR > app name > manual label), format as text with per-group durations and daily total. Include ticket IDs and PR numbers in descriptions. Return ExportResult (formattedText, entries, totalDuration).
- [ ] T040 [US5] ExportService duplicate detection — `checkDuplicates(entryIDs:)`: check if any entries are already in status `.exported` or `.booked`, return duplicates. Warn before re-export.
- [ ] T041 [US5] ExportService booking workflow — `confirmExport(entryIDs:)`: create ExportRecord, transition entries to `.exported` status. `markBooked(exportID:)`: transition entries to `.booked`, set bookedAt timestamp.
- [ ] T042 [P] [US5] Create ExportView in `TaskManagement/Sources/Views/TimeTracking/ExportView.swift` — show formatted export preview in a monospace text view. "Copy to Clipboard" button (NSPasteboard). "Mark as Booked" button after copying. Duplicate warning alert if re-exporting. Date picker to select export date.
- [ ] T043 [US5] Integrate export into navigation — add "Export" button to TimeTrackingDashboard and TimeEntryListView toolbar. Navigate to ExportView with selected date.

**Checkpoint**: Export workflow complete. Copy-ready text generated, duplicates prevented, booking tracked.

---

## Phase 7: API Integrations & WakaTime

**Purpose**: External service adapters for context enrichment and coding activity import

- [ ] T044 [P] Implement KeychainService in `TaskManagement/Sources/Services/KeychainService.swift` — wrapper around Security framework: `store(key:, value:, service:)`, `retrieve(key:, service:)`, `delete(key:, service:)` using `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`.
- [ ] T045 [P] Implement HTTPClient in `TaskManagement/Sources/Networking/HTTPClient.swift` — async/await URLSession wrapper with: configurable base URL, auth header injection (Bearer token from Keychain), JSON decoding, error handling (network, auth, server errors), timeout configuration.
- [ ] T046 Implement JiraAPIService in `TaskManagement/Sources/Networking/JiraAPI.swift` — `fetchTicket(id:)`: GET `/rest/api/2/issue/{id}`, return JiraTicketInfo (ticketID, summary, status, assignee). Use IntegrationConfig for server URL, KeychainService for auth token.
- [ ] T047 [P] Implement BitbucketAPIService in `TaskManagement/Sources/Networking/BitbucketAPI.swift` — `fetchPR(repository:, number:)`: GET `/rest/api/latest/projects/{proj}/repos/{repo}/pull-requests/{number}`, return BitbucketPRInfo. Use IntegrationConfig for server URL, KeychainService for auth token.
- [ ] T048 Integrate API enrichment into BrowserContextService — after extracting identifier from tab title, call JiraAPIService/BitbucketAPIService to fetch full details (summary, status, assignee/author). Populate BrowserContextData with enriched fields. Graceful fallback: if API call fails (offline, auth error), use tab title data only.
- [ ] T049 [P] Create IntegrationSettingsView in `TaskManagement/Sources/Views/Settings/IntegrationSettingsView.swift` — configure Jira (server URL, username, token), Bitbucket (server URL, username, token), WakaTime (API key). Store tokens in Keychain via KeychainService. Test connection button. Add tab to SettingsView.
- [ ] T050 [P] Create WakatimeContextData Codable struct in `TaskManagement/Sources/Models/WakatimeContextData.swift` — fields: project, branch?, language?, file?, category?. Add `wakatimeContext: WakatimeContextData?` field to TimeEntry model.
- [ ] T051 Implement WakaTimeService in `TaskManagement/Sources/Services/WakaTimeService.swift` — read API key from `~/.wakatime.cfg` (parse INI `[settings]` section). `fetchActivity(for date:)`: GET `https://api.wakatime.com/api/v1/heartbeats?date=YYYY-MM-DD`, convert heartbeats to WakatimeActivityRecord (group consecutive heartbeats for same project into time blocks).
- [ ] T052 WakaTimeService deduplication and import — `deduplicateAndImport(records:, existingEntries:)`: for each WakaTime time block, check if a window-monitoring entry overlaps the same time period with IntelliJ as the app. If overlap, replace window entry with WakaTime entry (richer context). If no overlap, create new entry with source `.wakatime`.
- [ ] T053 Integrate WakaTimeService into TrackingCoordinator — periodic sync (every 15 minutes, configurable). Fetch today's WakaTime activity, deduplicate and import. Only run if WakaTime is configured (API key exists).

**Checkpoint**: All external integrations working. Jira/Bitbucket enrichment, WakaTime import, credential management.

---

## Phase 8: Learned Patterns & Auto-Approval

**Purpose**: Learn from user reviews to auto-approve recurring patterns on subsequent days

- [ ] T054 [P] Create LearnedPattern `@Model` in `TaskManagement/Sources/Models/LearnedPattern.swift` — fields per data-model.md: id, contextType, identifierValue (unique with contextType), linkedTodo?, confirmationCount, lastConfirmedAt, isActive, createdAt. Register in ModelContainer.
- [ ] T055 Implement LearnedPatternService in `TaskManagement/Sources/Services/LearnedPatternService.swift` — `findMatch(contextType:, identifier:)`: query active patterns matching context+identifier, return linked todo ID. `learnFromReview(contextType:, identifier:, todoID:)`: create new pattern or increment confirmationCount if exists. `revoke(patternID:)`: set isActive to false.
- [ ] T056 LearnedPatternService stale detection — `flagStalePatterns()`: find patterns where linkedTodo.isCompleted or linkedTodo.isTrashed, return count. Entries auto-approved by stale patterns get flagged for manual review.
- [ ] T057 Integrate auto-approval into TimeEntryService — when a new auto-detected entry is created with browser context or WakaTime context, call LearnedPatternService.findMatch. If match found: set bookingStatus to `.reviewed`, set isAutoApproved to true, link to matched todo. Add `isAutoApproved: Bool` and `learnedPattern: LearnedPattern?` fields to TimeEntry if not already present.
- [ ] T058 [P] Create LearnedPatternsView in `TaskManagement/Sources/Views/Settings/LearnedPatternsView.swift` — list all learned patterns: show contextType, identifier, linked todo title, confirmation count, last confirmed date. "Revoke" button per pattern. Stale patterns highlighted. Add tab to SettingsView.
- [ ] T059 Integrate learning into review workflow — when user manually marks an entry as reviewed in TimeEntryListView: if entry has browser context or WakaTime context AND is linked to a todo, call `learnFromReview` to create/reinforce the pattern.

**Checkpoint**: Learned patterns functional. Confirmed reviews create patterns, subsequent matching entries auto-approved.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final quality pass across all features

- [ ] T060 Implement data retention in TimeEntryService — `purgeExpired(retentionDays: 90)`: delete booked entries older than 90 days, flag unbooked entries older than 90 days as overdue (add visual indicator). Purge ExportRecords older than 90 days. Run on app launch.
- [ ] T061 [P] Add keyboard shortcuts — Cmd+T: toggle tracking, Cmd+Shift+T: start manual timer, Cmd+E: open export view. Register in ContentView and MenuBarView.
- [ ] T062 [P] Verify all spec acceptance scenarios pass manual testing — walk through each US1-US5 scenario in the spec, document pass/fail
- [ ] T063 Run `swift build` with zero warnings, resolve all strict concurrency issues for Swift 6

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — BLOCKS all user stories
- **Phase 3 (US1 MVP)**: Depends on Phase 2 — delivers complete MVP
- **Phase 4 (US2)**: Depends on Phase 3 (extends TrackingCoordinator and TimeEntryRow)
- **Phase 5 (US3)**: Depends on Phase 3 (extends TimeEntryService). Can run in parallel with Phase 4.
- **Phase 6 (US5)**: Depends on Phase 5 (needs review workflow for export)
- **Phase 7 (APIs/WakaTime)**: Depends on Phase 4 (enriches browser context). Can start KeychainService/HTTPClient in parallel with Phase 4.
- **Phase 8 (Learned Patterns)**: Depends on Phase 5 (review workflow) and Phase 4 (browser context)
- **Phase 9 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: No dependencies on other stories — standalone MVP
- **US2 (P2)**: Depends on US1 (extends tracking loop)
- **US3 (P3)**: Depends on US1 (operates on time entries). Independent of US2.
- **US5 (P5)**: Depends on US3 (exports reviewed entries)

### Within Each User Story

- Models before services
- Services before coordinator integration
- Coordinator integration before UI
- Seeding before UI (defaults must exist)

### Parallel Opportunities

**Phase 2**: T002, T003, T004, T006 can all run in parallel (different files)
**Phase 3**: T007+T008 in parallel (different services), T013+T014+T016 in parallel (different views)
**Phase 4**: T023+T024 in parallel (different models), T029+T030 in parallel (different views)
**Phase 5**: T035+T036 in parallel (different views)
**Phase 7**: T044+T045 in parallel (Keychain + HTTP), T046+T047 in parallel (Jira + Bitbucket APIs)

---

## Parallel Example: US1 MVP

```
# After Phase 2 completes, launch core services in parallel:
Task: T007 "WindowMonitorService"
Task: T008 "IdleDetectionService"

# After services complete, launch views in parallel:
Task: T013 "TimeTrackingDashboard"
Task: T014 "TimeEntryRow"
Task: T016 "TrackingSettingsView"
```

---

## Implementation Strategy

### MVP First (US1 Only — Phases 1-3)

1. Complete Phase 1: Setup (1 task)
2. Complete Phase 2: Foundational (5 tasks)
3. Complete Phase 3: US1 MVP (16 tasks)
4. **STOP and VALIDATE**: Test all US1 acceptance scenarios
5. App tracks application time, handles idle/sleep, supports manual timer

### Incremental Delivery

1. Phase 1-3 → MVP: App tracks time (22 tasks)
2. Phase 4 → US2: Browser context for Jira/Bitbucket (+8 tasks)
3. Phase 5 → US3: Review and edit entries (+7 tasks)
4. Phase 6 → US5: Export for Timension (+6 tasks)
5. Phase 7 → API enrichment + WakaTime (+10 tasks)
6. Phase 8 → Learned auto-approval (+6 tasks)
7. Phase 9 → Polish (+4 tasks)

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- Each checkpoint validates the story independently before moving on
- Commit after each task or logical group
- US4 (Manual Timer) is folded into US1 MVP — not a separate phase
- All paths assume `TaskManagement/Sources/` as the base
