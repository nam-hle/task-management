# Quickstart: 005 — Application & Browser Time Tracking

**Branch**: `005-app-time-tracking`

## Prerequisites

- macOS 14+ (Sonoma) — required for SwiftData
- Xcode 16+ with Swift 6.0
- Existing 004 codebase built and running (`TaskManagement/` SPM package)

## Build & Run

```bash
cd TaskManagement
swift build
swift test
open Package.swift  # Opens in Xcode
```

Run from Xcode: Cmd+R. The app opens a main window + menu bar icon.

## First-Run Flow

1. App launches → checks `AXIsProcessTrusted()`
2. If Accessibility not granted → shows `AccessibilityPermissionView` overlay
3. User clicks "Open System Settings" → deep-links to Privacy & Security > Accessibility
4. User toggles the app on → app detects via polling (1s interval)
5. Tracking becomes available. Manual timers work without Accessibility permission.

## Key Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Active window detection | NSWorkspace notifications + AXUIElement | Event-driven (energy efficient), AX for title |
| Chrome tab context | AppleScript via NSAppleScript | Chrome exposes full scripting dictionary |
| Firefox tab context | AX API window title parsing | Firefox removed AppleScript tab support in v3.6 |
| Idle detection | IOKit HIDIdleTime (polled 30s) | Most reliable; no extra permissions |
| Sleep/wake/lock | NSWorkspace + DistributedNotificationCenter | Official + stable undocumented APIs |
| WakaTime data | Cloud API with local API key | BoltDB (Go format) unreadable from Swift |
| Background SwiftData | @ModelActor + Task.detached | Apple-recommended concurrency pattern |
| Sandbox | Disabled | Accessibility API requires non-sandboxed app |

## Service Dependency Graph

```
TrackingCoordinator (orchestrator)
├── WindowMonitorService (AX API)
│   └── BrowserContextService (AppleScript/title parsing)
│       ├── JiraAPIService (enrichment, optional)
│       └── BitbucketAPIService (enrichment, optional)
├── IdleDetectionService (IOKit + notifications)
├── TimeEntryService (SwiftData CRUD)
│   └── LearnedPatternService (auto-approval)
├── WakaTimeService (cloud API, optional)
└── ExportService (formatted output)

Supporting:
├── KeychainService (credentials)
└── AccessibilityPermissionService (permission check/prompt)
```

## File Locations

| What | Where |
|------|-------|
| Spec | `specs/005-app-time-tracking/spec.md` |
| Plan | `specs/005-app-time-tracking/plan.md` |
| Data model | `specs/005-app-time-tracking/data-model.md` |
| Service protocols | `specs/005-app-time-tracking/contracts/service-protocols.swift` |
| Existing models | `TaskManagement/Sources/Models/` |
| Existing services | `TaskManagement/Sources/Services/` |
| New time tracking views | `TaskManagement/Sources/Views/TimeTracking/` (to create) |
| New settings views | `TaskManagement/Sources/Views/Settings/` (to create) |
| New networking | `TaskManagement/Sources/Networking/` (to create) |

## Implementation Phases (Summary)

### MVP — Application Time Tracking Only

The MVP delivers **User Story 1** (P1): automatic tracking of which application
is active, with idle/sleep detection, basic time entries, and a simple dashboard.
No browser context, no WakaTime, no learned patterns, no export.

1. **Models & Data Layer (MVP)** — Extend TimeEntry with applicationName and
   applicationBundleID. Add TrackedApplication model. Extend enums. Register
   new models in ModelContainer.
2. **Accessibility Permission** — AccessibilityPermissionView with guided
   prompt, deep-link to System Settings, polling until granted.
3. **Core Tracking Loop (MVP)** — WindowMonitorService (NSWorkspace +
   AXUIElement), IdleDetectionService (IOKit + sleep/wake/lock), and a
   minimal TrackingCoordinator that orchestrates them.
4. **Time Entry Service (MVP)** — Basic CRUD: create, finalize, auto-save
   every 60s. Midnight splitting. Wire TimerManager to real tracking.
5. **UI (MVP)** — TimeTrackingDashboard (daily app usage breakdown),
   TrackedAppsSettingsView (app allowlist), TrackingSettingsView (idle
   threshold, min switch duration). Wire MenuBarView start/stop.
6. **Manual Timer (MVP)** — Start/stop manual timer with label. Suppresses
   auto-tracking while active.

### Post-MVP Phases

7. **Browser Context Detection** — BrowserContextService (Chrome AppleScript
   + Firefox title parsing), BrowserContextRule model, Jira/Bitbucket
   pattern extraction. Auto-link to matching todos (FR-011a/b).
8. **API Integrations** — KeychainService, JiraAPIService,
   BitbucketAPIService. Context enrichment from APIs.
9. **WakaTime Integration** — WakaTimeService (cloud API). Import, deduplicate,
   merge with window-monitoring entries.
10. **Review & Edit** — TimeEntryListView with merge/split/edit. Review
    workflow (unreviewed → reviewed). Bulk operations.
11. **Learned Patterns & Auto-Approval** — LearnedPatternService. Create
    patterns from confirmed reviews. Auto-approve on subsequent days.
12. **Export & Booking** — ExportService. Formatted output grouped by
    context. Duplicate prevention. Booking status tracking.

## Testing Strategy

- **Unit tests**: TimeEntryService (CRUD, auto-save, midnight split), BrowserContextService (regex extraction), LearnedPatternService (matching), ExportService (formatting)
- **Integration tests**: TrackingCoordinator lifecycle (start → track → idle → resume → stop)
- **Manual testing**: Window monitoring across real apps, Chrome/Firefox tab detection, idle timeout, sleep/wake recovery
