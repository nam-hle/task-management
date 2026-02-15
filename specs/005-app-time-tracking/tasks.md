# Tasks: Application & Browser Time Tracking

**Input**: Design documents from `/specs/005-app-time-tracking/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested — test tasks omitted. Add test phases if needed.

**Organization**: Tasks grouped by user story. MVP = US1 (Active App Tracking) + manual timer only.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- All paths relative to `Sources/`

---

## Phase 1: Setup

**Purpose**: Create directory structure for new feature areas

- [x] T001 Create directory structure: `Views/TimeTracking/`, `Views/Settings/`, `Views/Permissions/`, `Networking/` under `Sources/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Models, enums, and permission infrastructure that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Extend TimeEntry model with `applicationName: String?`, `applicationBundleID: String?`, and `label: String?` fields in `Sources/Models/TimeEntry.swift`
- [x] T003 [P] Create TrackedApplication `@Model` with id, name, bundleIdentifier (unique), isBrowser, isPreConfigured, isEnabled, sortOrder, createdAt in `Sources/Models/TrackedApplication.swift`
- [x] T004 [P] Extend `Sources/Models/Enums.swift`: add `BookingStatus.booked` case, `EntrySource.wakatime` case, new `TrackingState` enum (idle/tracking/paused/permissionRequired), new `PauseReason` enum (userPaused/systemIdle/systemSleep/screenLocked/manualTimerActive)
- [x] T005 Register TrackedApplication in ModelContainer schema array in `Sources/TaskManagementApp.swift`
- [x] T006 [P] Create AccessibilityPermissionView in `Sources/Views/Permissions/AccessibilityPermissionView.swift` — check `AXIsProcessTrusted()`, explain why permission is needed, "Open System Settings" button deep-linking to `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`, poll every 1s until granted, add `NSAccessibilityUsageDescription` to Info.plist

**Checkpoint**: Foundation ready — US1 implementation can begin

---

## Phase 3: User Story 1 — Active Application Time Tracking (Priority: P1) MVP

**Goal**: Automatically track which application is active, record time entries per app, handle idle/sleep/lock, display daily usage, support manual timer. This is the complete MVP.

**Independent Test**: Start tracker, switch between 3-4 apps for 10 minutes, verify time segments recorded with correct durations and app names. Let computer idle >5min and verify idle time excluded. Start/stop a manual timer and verify entry created.

### Core Services

- [x] T007 [P] [US1] Implement WindowMonitorService in `Sources/Services/WindowMonitorService.swift` — observe `NSWorkspace.didActivateApplicationNotification` for app switches, use `AXUIElementCreateApplication(pid)` + `kAXFocusedWindowAttribute` + `kAXTitleAttribute` to read window title, expose `onApplicationChanged` callback with ApplicationInfo (name, bundleID, pid, windowTitle, timestamp). Confine all AX calls to a dedicated actor for Swift 6 concurrency safety.
- [x] T008 [P] [US1] Implement IdleDetectionService in `Sources/Services/IdleDetectionService.swift` — poll IOKit `HIDIdleTime` every 30s via `IOServiceMatching("IOHIDSystem")` (use `kIOMainPortDefault`), observe `NSWorkspace.willSleepNotification`/`didWakeNotification`, observe `DistributedNotificationCenter` for `com.apple.screenIsLocked`/`com.apple.screenIsUnlocked` and screensaver notifications, expose callbacks: onIdleStarted, onIdleEnded, onSleepStarted, onWakeUp, onScreenLocked, onScreenUnlocked. Configurable idle threshold (default 5 min).
- [x] T009 [US1] Implement TimeEntryService in `Sources/Services/TimeEntryService.swift` — use `@ModelActor` for background SwiftData writes. Methods: `create(todoID:, applicationName:, bundleID:, source:, startTime:)`, `finalize(entryID:, endTime:)`, `autoSave(entryID:, currentTime:)` (persist duration every 60s), `splitAtMidnight(entryID:)` (split entries crossing midnight into two), `entries(for date:)` (fetch by date). Always use `PersistentIdentifier` across actor boundaries, never pass model objects. Use `Task.detached` for true background execution.
- [x] T010 [US1] Implement TrackingCoordinator in `Sources/Services/TrackingCoordinator.swift` — `@Observable` class that orchestrates WindowMonitorService, IdleDetectionService, and TimeEntryService. State machine: idle → tracking → paused(reason) → tracking. On app switch: check 30s minimum threshold (configurable), if exceeded finalize previous entry and create new one, if under threshold ignore switch. On idle start: pause current entry. On wake/unlock: resume. Auto-save timer every 60s. Midnight split check. Manual timer mode: suppress auto-tracking, create manual entry with label. Enforce single active timer.
- [x] T011 [US1] Wire TimerManager to TrackingCoordinator in `Sources/TaskManagementApp.swift` — replace stub TimerManager with real TrackingCoordinator. Pass ModelContainer to coordinator. Update `@State private var timerManager` to use coordinator's state for menu bar display (active app name, elapsed time, isRunning).

### Data Seeding

- [x] T012 [P] [US1] Implement first-launch seed for TrackedApplication defaults in `Sources/Services/TimeEntryService.swift` or a dedicated seeder — on first launch (no TrackedApplication records exist), insert: Google Chrome (`com.google.Chrome`, isBrowser: true, isPreConfigured: true, isEnabled: true), Firefox (`org.mozilla.firefox`, isBrowser: true, isPreConfigured: true, isEnabled: true). Insert suggested but disabled: IntelliJ IDEA (`com.jetbrains.intellij`), Xcode (`com.apple.dt.Xcode`), VS Code (`com.microsoft.VSCode`), Terminal (`com.apple.Terminal`), Slack (`com.tinyspeck.slackmacgap`).

### UI

- [x] T013 [P] [US1] Create TimeTrackingDashboard in `Sources/Views/TimeTracking/TimeTrackingDashboard.swift` — `@Query` time entries for today, group by applicationName, show per-app total duration with app icon/name, daily total at top, live-updating current entry with running timer. Use `@Observable` TrackingCoordinator for real-time elapsed time. Sort apps by total time descending.
- [x] T014 [P] [US1] Create TimeEntryRow in `Sources/Views/TimeTracking/TimeEntryRow.swift` — compact row displaying: app name, duration (formatted HH:MM:SS), start-end time range, source indicator (auto/manual), in-progress indicator for active entry.
- [x] T015 [US1] Create TrackedAppsSettingsView in `Sources/Views/Settings/TrackedAppsSettingsView.swift` — list all TrackedApplication records, toggle isEnabled per app, "Add Application" button to pick from running apps (via `NSWorkspace.shared.runningApplications`), show pre-configured apps (Chrome/Firefox) with non-removable badge, suggested apps section.
- [x] T016 [P] [US1] Create TrackingSettingsView in `Sources/Views/Settings/TrackingSettingsView.swift` — configurable: idle timeout (default 300s), minimum switch duration (default 30s), auto-save interval (default 60s). Use Stepper or Slider controls. Persist to UserDefaults or a settings model.
- [x] T017 [US1] Create SettingsView container in `Sources/Views/Settings/SettingsView.swift` — TabView with tabs: "Tracked Apps" (TrackedAppsSettingsView), "Tracking" (TrackingSettingsView). Register as Settings scene in TaskManagementApp.swift.
- [x] T018 [US1] Extend ContentView in `Sources/Views/ContentView.swift` — add "Time Tracking" item to sidebar navigation, selecting it shows TimeTrackingDashboard in the detail area. Add appropriate SF Symbol icon.
- [x] T019 [US1] Wire MenuBarView in `Sources/Views/MenuBar/MenuBarView.swift` — replace stub start/stop buttons with real actions calling TrackingCoordinator.startTracking()/stopTracking(). Show current app name and elapsed time when tracking. Show "Start Tracking" button when idle. Add "Manual Timer" quick action with label input.

### Manual Timer & Recovery

- [x] T020 [US1] Implement manual timer in TrackingCoordinator — `startManualTimer(label:, todoID:)` creates a new TimeEntry with source `.manual` and the given label, suppresses WindowMonitorService callbacks until stopped. `stopManualTimer()` finalizes the entry and resumes auto-tracking. Starting a new timer while one runs stops the current one first.
- [x] T021 [US1] Add accessibility permission check on app launch in `Sources/TaskManagementApp.swift` — on appear, check `AXIsProcessTrusted()`. If false, show AccessibilityPermissionView as an overlay/sheet on ContentView. Once granted, dismiss and enable tracking. Manual timers remain functional regardless of permission state.
- [x] T022 [US1] Implement crash recovery in TrackingCoordinator — on init, query TimeEntry where `isInProgress == true`. For each, calculate duration from startTime to last auto-save timestamp (or createdAt), finalize with that end time. Log recovered entries count.

**Checkpoint**: MVP complete. User can start tracking, see daily app breakdown, use manual timer, configure tracked apps. Verify all 5 acceptance scenarios from US1 pass.

---

## Phase 4: User Story 2 — Browser Tab Context Detection (Priority: P2) [SKIPPED]

**Status**: SKIPPED — replaced by WakaTime ticket inference (TicketInferenceService). WakaTime integration provides richer context (project, branch, language) and ticket ID extraction from branch names, making browser scraping unnecessary.

~~**Goal**: When Firefox or Chrome is active, extract Jira ticket IDs and Bitbucket PR numbers from tabs and attach to time entries. Auto-link to matching todos.~~

- [SKIPPED] T023 [P] [US2] Create BrowserContextRule `@Model`
- [SKIPPED] T024 [P] [US2] Create BrowserContextData Codable struct
- [SKIPPED] T025 [US2] Implement BrowserContextService
- [SKIPPED] T026 [US2] Integrate BrowserContextService into TrackingCoordinator
- [SKIPPED] T027 [US2] Implement auto-linking in TrackingCoordinator
- [SKIPPED] T028 [US2] Seed default BrowserContextRules
- [SKIPPED] T029 [P] [US2] Extend TimeEntryRow for browser context
- [SKIPPED] T030 [P] [US2] Extend TimeTrackingDashboard for browser context

### WakaTime Integration (Built Out-of-Order, Replaces Phase 4)

- [x] T050A Create WakaTimeService in `Sources/Services/WakaTimeService.swift` — `@MainActor @Observable`, fetches durations + heartbeats from WakaTime API, aggregates by (project, branch) pairing, annotates with nearest heartbeat data
- [x] T050B Create WakaTimeConfigReader in `Sources/Services/WakaTimeConfigReader.swift` — parses `~/.wakatime.cfg` INI format, extracts api_key from [settings] section
- [x] T050C Create TicketInferenceService in `Sources/Services/TicketInferenceService.swift` — static methods: `inferTickets(from:overrides:excludedProjects:unknownPatterns:)`, extracts ticket IDs from branch names via regex `[A-Z][A-Z0-9]+-\d+`, supports manual overrides, excluded projects, custom unknown patterns
- [x] T050D Create TicketOverride `@Model` in `Sources/Models/TicketOverride.swift` — fields: id, project, branch, ticketID, createdAt. For manual ticket assignments to git branches.
- [x] T050E Register TicketOverride in ModelContainer schema in `Sources/TaskManagementApp.swift`
- [x] T050F Create TicketsView in `Sources/Views/TimeTracking/TicketsView.swift` — ticket inference from WakaTime branches, manual assignment, excluded projects, unknown patterns, TicketTimelineChartView
- [x] T050G Create BranchesView in `Sources/Views/TimeTracking/BranchesView.swift` — project/branch grouping, BranchTimelineChartView
- [x] T050H Create TicketSettingsView in `Sources/Views/TimeTracking/TicketSettingsView.swift` — excluded projects toggles, unknown pattern regex input
- [x] T050I Create TicketTimelineChartView + BranchTimelineChartView in `Sources/Views/TimeTracking/`

---

## Phase 5: User Story 3 — Review and Edit Tracked Time Entries (Priority: P3)

**Goal**: Review daily entries, merge short entries, split long ones, adjust times, add notes, mark as reviewed.

**Independent Test**: Generate sample entries, merge two, split one, adjust a duration, add a note — verify all changes persist.

- [x] T031 [US3] Add `edited` case to `EntrySource` in `Sources/Models/Enums.swift` + create `TimeEntryChanges` struct
- [x] T032 [US3] Extend TimeEntryService with merge in `Sources/Services/TimeEntryService.swift` — `merge(entryIDs:)`: combine N entries into one with summed duration, earliest startTime, latest endTime, concatenated notes. Delete merged entries, return new entry ID.
- [x] T033 [US3] Extend TimeEntryService with split — `split(entryID:, at splitTime:)`: create two entries from one, first entry ends at splitTime, second starts at splitTime. Both retain original context (applicationName, todo link).
- [x] T034 [US3] Extend TimeEntryService with edit — `update(entryID:, changes:)`: update startTime, endTime (recalculate duration), notes, todo link, bookingStatus. Mark source as `.edited` if times changed.
- [x] T035 [US3] Extend TimeEntryService with review — `markReviewed(entryIDs:)`: bulk update bookingStatus from `.unreviewed` to `.reviewed`.
- [x] T036 [P] [US3] Create TimeEntryListView in `Sources/Views/TimeTracking/TimeEntryListView.swift` — list all entries for selected date, support multi-selection. Toolbar actions: "Merge Selected", "Mark Reviewed", "Mark All Reviewed". Date picker to navigate days. Show review status badges.
- [x] T037 [P] [US3] Create TimeEntryDetailView in `Sources/Views/TimeTracking/TimeEntryDetailView.swift` — edit form: start time picker, end time picker (auto-recalculates duration), notes TextEditor, todo picker (link/unlink), booking status display. "Split at Time" action with time picker. Source indicator (auto/manual/edited).
- [x] T038 [US3] Add review status badges to TimeEntryRow in `Sources/Views/TimeTracking/TimeEntryRow.swift` — reviewed (green checkmark), exported (blue arrow), booked (seal). Handle `.edited` source case.
- [x] T039 [US3] Add "Entries" tab to TimeTrackingDashboard in `Sources/Views/TimeTracking/TimeTrackingDashboard.swift`

**Checkpoint**: Full review workflow functional. Merge, split, edit, mark reviewed all working.

---

## Phase 6: User Story 5 — Export Formatted Time Summary (Priority: P5)

**Goal**: Generate copy-ready formatted summary of reviewed entries for Timension booking.

**Independent Test**: Prepare reviewed entries, trigger export, verify formatted output is correct and copyable.

- [x] T040 [P] [US5] Create ExportRecord `@Model` in `Sources/Models/ExportRecord.swift` — fields: id, exportedAt, formattedOutput, entryCount, totalDuration, isBooked, bookedAt?, timeEntryIDs (UUID array). Register in ModelContainer.
- [x] T041 [US5] Implement ExportService in `Sources/Services/ExportService.swift` — `@ModelActor`, `generateExport(for date:)`: fetch reviewed entries for date, group by todo/app/label, format as text with per-group durations and daily total. `checkDuplicates()`, `confirmExport()`, `markBooked()`.
- [x] T042 [P] [US5] Create ExportView in `Sources/Views/TimeTracking/ExportView.swift` — date picker, Generate button, monospace preview, Copy to Clipboard, Mark as Booked. Duplicate warning alert.
- [x] T043 [US5] Add "Export" tab to TimeTrackingDashboard in `Sources/Views/TimeTracking/TimeTrackingDashboard.swift`

**Checkpoint**: Export workflow complete. Copy-ready text generated, duplicates prevented, booking tracked.

---

## Phase 7 Remainder: Keychain & Integration Settings

**Purpose**: Credential management and integration configuration UI. (HTTPClient, JiraAPI, BitbucketAPI, API enrichment deferred — not needed without browser context.)

- [x] T044 [P] Implement KeychainService in `Sources/Services/KeychainService.swift` — Security framework wrapper: `store(key:, value:, service:)`, `retrieve(key:, service:)`, `delete(key:, service:)` using `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`.
- [x] T045 [P] Create IntegrationSettingsView in `Sources/Views/Settings/IntegrationSettingsView.swift` — configure Jira (URL, username, token), Bitbucket (URL, username, token), WakaTime status display. Store tokens in Keychain via KeychainService.
- [x] T046 Add "Integrations" tab to SettingsView in `Sources/Views/Settings/SettingsView.swift`

**Checkpoint**: Keychain storage working, integration credentials configurable.

---

## Phase 8: Learned Patterns & Auto-Approval

**Purpose**: Learn from user reviews to auto-approve recurring patterns on subsequent days

- [x] T047 [P] Create LearnedPattern `@Model` in `Sources/Models/LearnedPattern.swift` — fields: id, contextType, identifierValue, linkedTodo?, confirmationCount, lastConfirmedAt, isActive, createdAt. Register in ModelContainer.
- [x] T048 Add `isAutoApproved: Bool` and `learnedPattern: LearnedPattern?` fields to TimeEntry in `Sources/Models/TimeEntry.swift`
- [x] T049 Implement LearnedPatternService in `Sources/Services/LearnedPatternService.swift` — `@ModelActor`, `findMatch(contextType:, identifier:)`, `learnFromReview(contextType:, identifier:, todoID:)`, `revoke(patternID:)`, `flagStalePatterns()`, `linkedTodoID(for:)`
- [x] T050 Integrate auto-approval into TimeEntryService — `applyAutoApproval(entryID:, patternID:, todoID:)` in `Sources/Services/TimeEntryService.swift`
- [x] T051 Integrate auto-approval into TimeEntryService — after creating entry, check LearnedPattern for matching bundleID in `Sources/Services/TimeEntryService.swift`
- [x] T052 Trigger learning on manual review in TimeEntryListView — when user marks reviewed + entry has todo + bundleID → `learnFromReview()`
- [x] T053 [P] Create LearnedPatternsView in `Sources/Views/Settings/LearnedPatternsView.swift` — list patterns, show context/identifier/todo/count, Revoke button, stale warnings
- [x] T054 Add "Learned Patterns" tab to SettingsView in `Sources/Views/Settings/SettingsView.swift`
- [x] T055 Add auto-approved badge (sparkle icon) to TimeEntryRow for `isAutoApproved` entries in `Sources/Views/TimeTracking/TimeEntryRow.swift`

**Checkpoint**: Learned patterns functional. Confirmed reviews create patterns, subsequent matching entries auto-approved.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final quality pass across all features

- [x] T056 Implement data retention in TimeEntryService — `purgeExpired(retentionDays: 90)`: delete booked entries older than 90 days. Run on app launch via `Sources/TaskManagementApp.swift`.
- [x] T057 [P] Add keyboard shortcuts — Cmd+T: toggle tracking, Cmd+Shift+T: manual timer. Register via `.commands {}` on WindowGroup in `Sources/TaskManagementApp.swift`.
- [x] T058 Run `swift build` with zero warnings, resolve all strict concurrency issues for Swift 6

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — BLOCKS all user stories
- **Phase 3 (US1 MVP)**: Depends on Phase 2 — delivers complete MVP
- **Phase 4 (US2)**: SKIPPED — replaced by WakaTime ticket inference
- **Phase 5 (US3)**: Depends on Phase 3 (extends TimeEntryService)
- **Phase 6 (US5)**: Depends on Phase 5 (needs review workflow for export)
- **Phase 7 (Keychain/Settings)**: Independent — can start anytime after Phase 3
- **Phase 8 (Learned Patterns)**: Depends on Phase 5 (review workflow)
- **Phase 9 (Polish)**: Depends on all previous phases

### Within Each Phase

- Models before services
- Services before coordinator integration
- Coordinator integration before UI

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- Each checkpoint validates the story independently before moving on
- US4 (Manual Timer) is folded into US1 MVP — not a separate phase
- All paths relative to `Sources/` (package root)
- Phase 4 was SKIPPED — WakaTime integration provides ticket inference without browser scraping
- WakaTime tasks (T050A-T050I) were built out-of-order alongside Phase 3
