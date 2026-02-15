# Tasks: Ticket-Centric Plugin System

**Input**: Design documents from `/specs/006-time-tracking-plugins/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/plugin-protocol.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Create directory structure for plugin system

- [x] T001 Create `Sources/Plugins/` directory for plugin protocol and implementations

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Plugin infrastructure that MUST be complete before ANY user story

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 [P] Add `PluginStatus` enum and `chrome`/`firefox` cases to `EntrySource` in `Sources/Models/Enums.swift` — PluginStatus has cases: active, inactive, error(String), permissionRequired, unavailable. EntrySource gets `chrome` and `firefox` cases with appropriate icons and display names. Add `SourceDuration` struct (pluginID, pluginDisplayName, duration, entryCount) and `TicketAggregate` struct (ticketID, totalDuration, rawDuration, entries, sourceBreakdown) for computed ticket aggregation.
- [x] T003 [P] Extend `TimeEntry` model with `sourcePluginID: String?`, `ticketID: String?`, `contextMetadata: String?` in `Sources/Models/TimeEntry.swift` — all fields optional with `nil` default for lightweight migration. Add `= nil` on stored property declarations (required for SwiftData migration). Update init to accept new parameters with nil defaults.
- [x] T004 [P] Extend `TicketOverride` with `urlPattern: String?`, `appNamePattern: String?`, `priority: Int = 0` in `Sources/Models/TicketOverride.swift` — add fields with defaults for migration. Update init to accept new parameters.
- [x] T005 [P] Define `TimeTrackingPlugin` protocol and `PluginManager` class in `Sources/Plugins/TimeTrackingPlugin.swift` — Protocol: `AnyObject, Identifiable` with `id: String`, `displayName: String`, `status: PluginStatus`, `isAvailable() -> Bool`, `start() async throws`, `stop() async throws`. PluginManager: `@Observable @MainActor final class` with register(), startAll(), stopAll(), enable(pluginID:), disable(pluginID:), isEnabled(pluginID:) using UserDefaults key `"plugin.{id}.enabled"`. Default enabled: true for "app-tracking" and "wakatime", false for "chrome" and "firefox".
- [x] T006 Create `TicketAggregationService` in `Sources/Services/TicketAggregationService.swift` — struct with static methods: `aggregate(entries: [TimeEntry]) -> [TicketAggregate]` groups entries by ticketID, computes deduplicated wall-clock time per ticket, builds per-source breakdown. `deduplicatedDuration(entries: [TimeEntry]) -> TimeInterval` for a single ticket group. `mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)]` implements sweep-line merge algorithm (sort by start, merge overlapping). Handle in-progress entries (nil endTime → use Date()). Return tickets sorted by totalDuration descending. Unassigned entries (ticketID == nil) grouped under special ticketID "unassigned".
- [x] T007 Update `TimeEntryService` for plugin-aware entry creation in `Sources/Services/TimeEntryService.swift` — extend `create()` method to accept `sourcePluginID: String?`, `ticketID: String?`, `contextMetadata: String?` parameters (all optional, nil default). Set these fields on the new TimeEntry. No changes to existing method signatures needed — add new parameters with defaults.
- [x] T008 Build verification — run `swift build` and resolve any errors. Pay attention to SwiftData `#Predicate` issues with new enum cases (extract to local variables if needed).

**Checkpoint**: Plugin infrastructure ready — protocol defined, models extended, aggregation service built. User story implementation can begin.

---

## Phase 3: User Story 2 — Plugin-Based Source Contribution (Priority: P2)

**Goal**: Migrate app tracking and WakaTime to the plugin interface so both produce TimeEntry records through the same pipeline. This phase comes before US1 because the dashboard needs plugins producing data with ticketIDs.

**Independent Test**: After this phase, both AppTrackingPlugin and WakaTimePlugin create TimeEntry records with `sourcePluginID` set. WakaTime entries have `ticketID` resolved from branch names. All existing functionality preserved — app tracking pause/resume, idle detection, WakaTime branch fetching, ticket inference, manual overrides, excluded projects.

**Dependency**: Requires Phase 2 (Foundational) complete.

### Implementation for User Story 2

- [x] T009 [P] [US2] Create `AppTrackingPlugin` in `Sources/Plugins/AppTrackingPlugin.swift` — `@MainActor final class` implementing `TimeTrackingPlugin`. id="app-tracking", displayName="App Tracking". Owns `WindowMonitorService` and `IdleDetectionService` instances. `isAvailable()` checks Accessibility permission via AXIsProcessTrusted(). `start()` initializes monitors, sets up app switch handler that creates/finalizes TimeEntry records via TimeEntryService with `sourcePluginID="app-tracking"`. `stop()` stops monitors. Expose: `state: TrackingState`, `currentAppName: String?`, `currentEntryID: PersistentIdentifier?`, `elapsedSeconds: Int`, `pause(reason:)`, `resume()`. Handle idle callbacks (pause on idle, resume on wake). Handle app switch debouncing (minimumSwitchDuration from UserDefaults). Move the entry creation/finalization logic from TrackingCoordinator into this plugin. Include auto-save timer, midnight split calls, crash recovery. Set `contextMetadata` JSON with windowTitle when available.
- [x] T010 [US2] Refactor `TrackingCoordinator` to delegate to `PluginManager` in `Sources/Services/TrackingCoordinator.swift` — Remove WindowMonitorService and IdleDetectionService ownership (moved to AppTrackingPlugin). Add `pluginManager: PluginManager` property. `startTracking()` calls `pluginManager.startAll()`. `stopTracking()` calls `pluginManager.stopAll()`. Keep manual timer functionality (startManualTimer, stopManualTimer) — these create entries with sourcePluginID=nil (core, not plugin). Expose computed properties that delegate to AppTrackingPlugin (state, currentAppName, elapsedSeconds) by looking up plugin via `pluginManager.plugin(id: "app-tracking")`. Keep `recoverFromCrash()` as core functionality. Keep elapsed display timer for UI.
- [x] T011 [US2] Wire `PluginManager` and `AppTrackingPlugin` in `Sources/TaskManagementApp.swift` — Create PluginManager as `@State` property. Create AppTrackingPlugin with ModelContainer. Register plugin with PluginManager. Pass PluginManager to TrackingCoordinator. Inject PluginManager into environment. Update `.task {}` block to call `pluginManager.startAll()` instead of `coordinator.startTracking()` directly (coordinator delegates anyway). Ensure app quit calls `pluginManager.stopAll()`.
- [x] T012 [US2] Build and verify app tracking works — run `swift build`. Verify no regressions: app launches, detects active applications, creates TimeEntry records with sourcePluginID="app-tracking", pause/resume works, idle detection works.
- [x] T013 [P] [US2] Create `WakaTimePlugin` in `Sources/Plugins/WakaTimePlugin.swift` — `@MainActor final class` implementing `TimeTrackingPlugin`. id="wakatime", displayName="WakaTime". Uses existing `WakaTimeService` internally. `isAvailable()` checks WakaTimeConfigReader.readAPIKey() != nil. `start()` does initial fetch + starts periodic timer (e.g., every 5 minutes). `stop()` cancels timer. `fetchAndSync(for: Date)` fetches branches via WakaTimeService, runs TicketInferenceService to resolve tickets, then creates TimeEntry records via TimeEntryService with sourcePluginID="wakatime", ticketID from inference, contextMetadata JSON with project+branch. Must deduplicate: check for existing wakatime entries overlapping same time period before inserting (avoid duplicate entries on repeated fetches). Expose `isLoading`, `error` for UI observation.
- [x] T014 [US2] Update `TicketInferenceService` for unified resolution in `Sources/Services/TicketInferenceService.swift` — Add a new static method `resolveTicketID(branch: String?, pageTitle: String?, pageURL: String?, appName: String?, overrides: [TicketOverride]) -> String?` that tries resolution in order: (1) match overrides by branch, URL pattern, or app name pattern (priority order), (2) extract Jira ticket from branch name via regex `[A-Z][A-Z0-9]+-\d+`, (3) extract Jira ticket from page title, (4) extract from URL. Return nil if no resolution. Existing `inferTickets(from:)` method remains for backward compatibility during transition.
- [x] T015 [US2] Register `WakaTimePlugin` in `Sources/TaskManagementApp.swift` — Create WakaTimePlugin with ModelContainer. Register with PluginManager. Ensure both plugins (app-tracking + wakatime) produce entries visible in the entries list.
- [x] T016 [US2] Build verification — run `swift build`. Verify WakaTime plugin fetches data and creates TimeEntry records with sourcePluginID="wakatime" and ticketID set.

**Checkpoint**: Two plugins producing TimeEntry records through the plugin interface. App tracking entries have sourcePluginID="app-tracking". WakaTime entries have sourcePluginID="wakatime" and ticketID resolved from branches. All existing functionality preserved.

---

## Phase 4: User Story 1 — Ticket-Centric Dashboard (Priority: P1)

**Goal**: Redesign the dashboard so the primary view is organized by tickets. Each ticket shows aggregated time from all active plugins with per-source breakdown. Overlapping time from multiple sources is deduplicated to show wall-clock time.

**Independent Test**: Open dashboard, see tickets sorted by total time descending. Expand a ticket to see per-source breakdown (WakaTime: Xm, App Tracking: Ym). Unassigned time appears in a separate group. Manually assign unassigned time to a ticket in under 3 clicks.

**Dependency**: Requires Phase 3 (US2) complete — needs plugins producing entries with ticketIDs.

### Implementation for User Story 1

- [x] T017 [US1] Redesign `TicketsView` to use `TicketAggregationService` in `Sources/Views/TimeTracking/TicketsView.swift` — Replace direct WakaTimeService consumption with `@Query` of TimeEntry records for the selected date. Use `TicketAggregationService.aggregate(entries:)` to compute ticket groups. Display ticket list sorted by totalDuration descending. Each row shows: ticket ID, total deduplicated duration, source count indicator. Separate "Unassigned" group at the bottom for entries with no ticketID. Keep the TicketTimelineChartView but feed it from aggregated data instead of WakaTimeService. Add date picker for day selection. Remove direct WakaTimeService dependency (plugin handles fetching). Keep refresh button that triggers all plugin re-sync.
- [x] T018 [P] [US1] Create `TicketDetailView` in `Sources/Views/TimeTracking/TicketDetailView.swift` — Expandable disclosure view for a single ticket. Shows: ticket ID as header, total wall-clock duration (deduplicated), raw source duration sum (for comparison). Per-source breakdown table: plugin display name, duration from that source, entry count. List of individual TimeEntry records contributing to this ticket (tap to open TimeEntryDetailView). Visual timeline showing segments from each source (reuse TimelineChartView pattern, colored by source).
- [x] T019 [P] [US1] Create `UnassignedTimeView` in `Sources/Views/TimeTracking/UnassignedTimeView.swift` — Shows entries where ticketID is nil. Each row displays: source plugin name, application name or page title (from contextMetadata), time range, duration. "Assign" button per entry → opens popover with: text field for ticket ID (validates Jira pattern), recent tickets list for quick selection, existing todo list for linking. On assignment: update entry's ticketID via TimeEntryService. Bulk assign: multi-select entries → assign all to same ticket.
- [x] T020 [US1] Redesign `TimeTrackingDashboard` tab layout in `Sources/Views/TimeTracking/TimeTrackingDashboard.swift` — "Tickets" tab as default and primary (already is). Remove or consolidate "Branches" tab (WakaTime-specific, now redundant — branch info available via ticket detail source breakdown). Keep "Applications" tab (useful for raw app tracking data). Keep "Entries" tab. Keep "Export" tab. Update dashboard header to show combined ticket count + total deduplicated time across all sources. Remove WakaTimeService `@State` property (plugins handle fetching). Add PluginManager from environment for refresh triggers.
- [x] T021 [US1] Add plugin status indicators to dashboard in `Sources/Views/TimeTracking/TimeTrackingDashboard.swift` — In the dashboard header or status bar, show small indicators for each registered plugin: green dot for active, orange for error/permission, gray for inactive/unavailable. Tapping an error indicator shows the error message. Non-blocking — dashboard still shows data from healthy plugins when one fails (FR-009, SC-007).
- [x] T022 [US1] Build verification — run `swift build`. Verify dashboard shows ticket-centric view with aggregated data from multiple plugins.

**Checkpoint**: Dashboard is ticket-first. Users see tickets sorted by time with multi-source breakdown. Unassigned time is visible and assignable. Deduplication shows wall-clock time.

---

## Phase 5: User Story 3 — Browser Activity Plugins (Priority: P3)

**Goal**: Chrome and Firefox contribute time tracking data by detecting active tab context and extracting Jira tickets and Bitbucket PRs.

**Independent Test**: Open Jira ticket PROJ-123 in Chrome for 3 minutes. Verify the dashboard shows PROJ-123 with source "Chrome" contributing 3m. Open a Bitbucket PR in Firefox for 2 minutes. Verify it appears in the dashboard (resolved to ticket if pattern matches, otherwise unassigned with PR title as context).

**Dependency**: Requires Phase 2 (Foundational) complete. Can run in parallel with US1 dashboard work if needed.

### Implementation for User Story 3

- [x] T023 [P] [US3] Create `BrowserTabService` in `Sources/Services/BrowserTabService.swift` — Struct with static methods. `readChromeTab() async -> (title: String, url: String)?`: runs AppleScript `tell application "Google Chrome" to return {title of active tab of front window, URL of active tab of front window}` via NSAppleScript on a background thread. Returns nil if Chrome not running or no windows. `readFirefoxWindowTitle() async -> String?`: reads AXUIElement title attribute for Firefox's frontmost window (reuse pattern from WindowMonitorService). Strips " — Mozilla Firefox" / " - Mozilla Firefox" suffix. Returns nil if Firefox not running. `extractTicketID(from text: String) -> String?`: regex `[A-Z][A-Z0-9]+-\d+` match. `extractBitbucketPR(from url: String) -> (workspace: String, repo: String, prNumber: Int)?`: match against Bitbucket Server and Cloud URL patterns. `isAppInstalled(bundleID: String) -> Bool`: check via NSWorkspace.shared.urlForApplication(withBundleIdentifier:).
- [x] T024 [US3] Create `ChromePlugin` in `Sources/Plugins/ChromePlugin.swift` — `@MainActor final class` implementing `TimeTrackingPlugin`. id="chrome", displayName="Chrome". `isAvailable()` checks `BrowserTabService.isAppInstalled(bundleID: "com.google.Chrome")`. On `start()`: registers to receive app activation notifications (NSWorkspace). When Chrome becomes active, starts a polling timer that reads tab info via BrowserTabService.readChromeTab() every few seconds. On tab change (title/URL different from last read): finalize previous entry, create new entry with sourcePluginID="chrome", ticketID from extractTicketID(title or URL), contextMetadata JSON with pageTitle+pageURL. Respects minimum duration threshold (same UserDefaults key as app tracking). On Chrome deactivation: finalize current entry. `stop()` removes observers and cancels timer. Handle permission errors gracefully — if AppleScript fails with permission error, set status to .permissionRequired.
- [x] T025 [US3] Create `FirefoxPlugin` in `Sources/Plugins/FirefoxPlugin.swift` — `@MainActor final class` implementing `TimeTrackingPlugin`. id="firefox", displayName="Firefox". `isAvailable()` checks `BrowserTabService.isAppInstalled(bundleID: "org.mozilla.firefox")`. Same activation pattern as ChromePlugin but uses BrowserTabService.readFirefoxWindowTitle(). On Firefox active: poll window title, detect changes, create/finalize entries with sourcePluginID="firefox". Extract ticket from title, extract PR info if Bitbucket page detected. contextMetadata JSON with pageTitle and parsedFrom="windowTitle". Cannot read URL (Firefox limitation per research.md) — ticket resolution based on title only. Minimum duration threshold. Permission status from AXUIElement access.
- [x] T026 [US3] Register browser plugins in `Sources/TaskManagementApp.swift` — Create ChromePlugin and FirefoxPlugin instances with ModelContainer. Register both with PluginManager. Default enabled state: false (user opts in via settings). Plugins check isAvailable() at startup — "unavailable" if browser not installed.
- [x] T027 [US3] Build verification — run `swift build`. Verify browser plugins initialize correctly, detect browser availability, and produce entries when enabled.

**Checkpoint**: Chrome and Firefox plugins contribute time tracking data. Jira ticket IDs extracted from tab titles/URLs. Bitbucket PRs detected from titles. Unresolved time goes to Unassigned with page context.

---

## Phase 6: User Story 4 — Plugin Settings & Ticket Management (Priority: P4)

**Goal**: Users can manage plugins and ticket resolution rules from settings — enable/disable sources, configure credentials, define override rules.

**Independent Test**: Open Settings → Plugins. See all 4 plugins with status. Disable WakaTime — verify no new WakaTime data fetched. Re-enable — data returns. Add a ticket override rule for a URL pattern → verify browser entries matching that URL resolve to the specified ticket.

**Dependency**: Requires Phase 2 (Foundational) complete. Best after Phase 5 (US3) so all plugins exist.

### Implementation for User Story 4

- [x] T028 [P] [US4] Create `PluginSettingsView` in `Sources/Views/Settings/PluginSettingsView.swift` — SwiftUI view showing all registered plugins from PluginManager (via @Environment). For each plugin: display name, status badge (colored dot + text: Active/Inactive/Error/Permission Required/Unavailable), toggle to enable/disable. When toggled: call pluginManager.enable/disable. For plugins with credentials (WakaTime): show configuration section with status of API key. For plugins requiring permissions: show "Grant Permission" button linking to System Preferences. Group by: Active plugins, Inactive plugins, Unavailable plugins. Show error messages for plugins in error state.
- [x] T029 [US4] Add "Plugins" tab to `SettingsView` in `Sources/Views/Settings/SettingsView.swift` — Add new tab with Label("Plugins", systemImage: "puzzlepiece.extension"). Position after existing tabs (Tracked Apps, Tracking, Integrations, Patterns). PluginSettingsView as tab content. May consolidate with or replace the existing IntegrationSettingsView (WakaTime status is now in Plugins).
- [x] T030 [US4] Add URL/app pattern override management to `TicketSettingsView` in `Sources/Views/TimeTracking/TicketSettingsView.swift` — Extend existing override management with new fields: URL pattern (TextField, regex validated), app name pattern (TextField, regex validated), priority (Stepper or Picker). When creating/editing an override, user can specify: branch pattern (existing), URL pattern (new, for browser plugins), app name pattern (new, for app tracking), target ticket ID (existing), priority (new). List existing overrides sorted by priority descending. Delete button per override. Validate regex patterns on input (show error if invalid).
- [x] T031 [US4] Build verification — run `swift build`. Verify settings UI shows all plugins with correct status and toggle functionality.

**Checkpoint**: Full plugin management from Settings. Enable/disable works. Override rules with URL/app patterns. Previously-recorded entries survive plugin disable (FR-018).

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, consolidation, and final verification

- [x] T032 [P] Clean up legacy code — remove or update `BranchesView` in `Sources/Views/TimeTracking/BranchesView.swift` (WakaTime-specific branch view is redundant now that ticket detail shows source breakdown). If removing: also remove BranchTimelineChartView. If keeping: update to read from TimeEntry records filtered by sourcePluginID="wakatime" instead of direct WakaTimeService. Remove unused WakaTimeService properties from views that no longer need them.
- [x] T033 [P] Verify all existing features preserved — ensure TimeEntryListView, TimeEntryDetailView, ExportView, LearnedPatternsView all work correctly with new TimeEntry fields. Learned patterns should still trigger on app tracking plugin entries (bundleID-based matching). Export should include sourcePluginID and ticketID in formatted output.
- [x] T034 Final build verification — run `swift build` with zero warnings. Run app and walk through quickstart.md verification checklist.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — create directory
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **US2 (Phase 3)**: Depends on Foundational — BLOCKS US1 (dashboard needs plugins producing data)
- **US1 (Phase 4)**: Depends on US2 (needs plugins producing entries with ticketIDs)
- **US3 (Phase 5)**: Depends on Foundational only — can run in parallel with US2/US1 if desired
- **US4 (Phase 6)**: Depends on Foundational — best after US3 so all plugins exist for settings UI
- **Polish (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

```
Phase 1 (Setup)
    │
    ▼
Phase 2 (Foundational) ─────────────────────────┐
    │                                             │
    ▼                                             ▼
Phase 3 (US2: Plugin Migration)          Phase 5 (US3: Browser Plugins)
    │                                             │
    ▼                                             │
Phase 4 (US1: Ticket Dashboard)                   │
    │                                             │
    ▼                                             ▼
Phase 6 (US4: Plugin Settings) ◄──────────────────┘
    │
    ▼
Phase 7 (Polish)
```

**Note**: US1 (P1 priority) is implemented after US2 (P2 priority) because the ticket dashboard requires plugins to be producing data. This is an implementation dependency, not a priority inversion — US1 is still the highest-value user story.

### Within Each User Story

- Models/enums before services
- Services before plugins
- Plugins before views
- Core logic before UI integration
- Build verification at end of each phase

### Parallel Opportunities

**Within Phase 2 (Foundational)**:
```
T002 (Enums.swift) ─┐
T003 (TimeEntry.swift) ─┤── All parallel (different files)
T004 (TicketOverride.swift) ─┤
T005 (Plugin protocol) ─┘
    │
    ▼
T006 (TicketAggregationService) ── depends on T002 (TicketAggregate struct)
T007 (TimeEntryService update) ── depends on T003 (new fields)
```

**Within Phase 3 (US2)**:
```
T009 (AppTrackingPlugin) ─┐── parallel (different files)
T013 (WakaTimePlugin)  ───┘
    │
    ▼
T010 (TrackingCoordinator refactor) ── depends on T009
T014 (TicketInferenceService) ── depends on T013
```

**Within Phase 4 (US1)**:
```
T018 (TicketDetailView) ─┐── parallel (new files)
T019 (UnassignedTimeView) ─┘
    │
    ▼
T017 (TicketsView redesign) ── depends on T018, T019
T020 (Dashboard layout) ── depends on T017
```

**Within Phase 5 (US3)**:
```
T023 (BrowserTabService) ── must be first
    │
    ▼
T024 (ChromePlugin) ─┐── parallel (different files)
T025 (FirefoxPlugin) ─┘
```

---

## Implementation Strategy

### MVP First (Phases 1–4: US2 + US1)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (plugin protocol, model extensions, aggregation)
3. Complete Phase 3: US2 (app tracking + WakaTime as plugins producing entries)
4. Complete Phase 4: US1 (ticket-centric dashboard showing multi-source data)
5. **STOP and VALIDATE**: Ticket dashboard works with 2 sources, deduplication correct, unassigned time assignable
6. This delivers the core value: ticket-centric time tracking with multi-source aggregation

### Incremental Delivery

1. Setup + Foundational → Plugin infrastructure ready
2. Add US2 (plugin migration) → Test: both sources produce entries → Build passes
3. Add US1 (ticket dashboard) → Test: tickets shown with breakdown → **MVP!**
4. Add US3 (browser plugins) → Test: Chrome/Firefox contribute data → Deploy
5. Add US4 (plugin settings) → Test: manage plugins from settings → Deploy
6. Polish → Clean, final verification

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks in same phase
- [Story] label maps task to specific user story for traceability
- US2 before US1 is intentional: plugins must produce data before dashboard can display it
- All new SwiftData fields MUST have default values on stored property declarations (`= nil`, `= 0`) for lightweight migration
- Watch for `#Predicate` issues with new enum cases — extract to local variables before predicate
- Browser plugins default to disabled — user opts in via settings
- Manual timers remain on TrackingCoordinator (core, not plugin)
- Commit after each phase with branch prefix format: `006: Description`
