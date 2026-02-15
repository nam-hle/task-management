# Research: Application & Browser Time Tracking

**Feature**: 005-app-time-tracking | **Date**: 2026-02-14

## R1: Active Window Detection on macOS

**Decision**: NSWorkspace notifications for app-switch events + AXUIElement for window title extraction

**Rationale**: NSWorkspace.didActivateApplicationNotification is energy-efficient (event-driven, no polling) and provides the NSRunningApplication with PID. AXUIElement then reads the focused window title on demand. This two-layer approach avoids constant polling while giving accurate window-level context.

**Alternatives considered**:
- CGWindowListCopyWindowInfo: Lists all windows but cannot determine which is focused. Supplementary use only.
- Pure polling with Timer: Wastes CPU. Event-driven is better for a background service.
- AXSwift library: Nice wrapper but adds an external dependency. Apple's C API is sufficient and avoids dependency per constitution Principle IV.

**Key APIs**:
- `NSWorkspace.shared.notificationCenter` → `didActivateApplicationNotification`
- `AXUIElementCreateApplication(pid)` → `kAXFocusedWindowAttribute` → `kAXTitleAttribute`
- Requires Accessibility permission (AXIsProcessTrusted)

**Gotchas**:
- AXUIElement is not Sendable in Swift 6 strict concurrency. Confine all AX calls to a dedicated actor.
- Some Electron apps may not expose window titles consistently.

## R2: Browser Tab Detection (Chrome vs Firefox)

**Decision**: Chrome uses AppleScript (NSAppleScript) for title + URL. Firefox uses AX API window title parsing (no AppleScript support for tabs).

**Rationale**: Chrome has a full scripting dictionary exposing `title of active tab` and `URL of active tab`. Firefox removed AppleScript tab support in v3.6. Firefox's window title format is `"Page Title - Mozilla Firefox"` which is parseable for the page title but not the URL.

**Alternatives considered**:
- Firefox AX tree traversal for address bar: Possible but requires `accessibility.force_disabled = -1` in Firefox config. Too fragile and poor UX.
- Browser extensions: Would provide full access but requires maintaining extensions for two browsers. Out of scope per YAGNI.
- Safari support: Feasible (has AppleScript) but not requested. Can be added later via adapter pattern.

**Chrome pattern**:
```swift
let script = NSAppleScript(source: """
    tell application "Google Chrome"
        set tabTitle to title of active tab of front window
        set tabURL to URL of active tab of front window
        return tabTitle & "\\n" & tabURL
    end tell
""")
```

**Firefox pattern**: Parse window title by stripping ` - Mozilla Firefox` or ` - Firefox` suffix.

**Gotchas**:
- Chrome AppleScript requires Automation permission (separate from Accessibility).
- Firefox URL is NOT available from window title — only the page title. For Jira/Bitbucket matching, the page title contains ticket IDs (e.g., "[PROJ-123] Fix bug") which is sufficient.
- For Bitbucket PRs in Firefox, the PR number is in the title (e.g., "Pull request #42: Fix login - my-repo").

## R3: Idle and Sleep Detection

**Decision**: IOKit HIDIdleTime polled every 30 seconds for idle detection. NSWorkspace notifications for sleep/wake. DistributedNotificationCenter for screen lock/unlock.

**Rationale**: IOKit HIDIdleTime is the most reliable measure of actual keyboard/mouse inactivity. Polling every 30 seconds is cheap and aligns with the 30-second minimum switch threshold. NSWorkspace sleep/wake notifications are official, documented APIs. Screen lock/unlock via DistributedNotificationCenter is undocumented but stable for 10+ years.

**Alternatives considered**:
- CGEventSource.secondsSinceLastEventType: Simpler but less reliable (can reset on system events).
- EventTap for HID events: More granular but requires additional permissions and is overkill for idle detection.

**Key APIs**:
- `IOServiceMatching("IOHIDSystem")` → `HIDIdleTime` (nanoseconds)
- `NSWorkspace.willSleepNotification` / `didWakeNotification`
- `DistributedNotificationCenter` → `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`
- `NSWorkspace.screensaverDidLaunchNotification` / `screensaverDidDismissNotification`

**Gotchas**:
- `kIOMasterPortDefault` is deprecated in macOS 12+; use `kIOMainPortDefault`.
- IOKit idle time requires no special permissions — available to all apps.
- Screen lock/unlock notifications are undocumented Apple APIs but have been stable.

## R4: WakaTime Data Access

**Decision**: Use WakaTime cloud API (`GET /api/v1/heartbeats?date=YYYY-MM-DD`) with API key from `~/.wakatime.cfg`. Fall back gracefully when WakaTime is not configured.

**Rationale**: The local offline data is stored in Go's BoltDB format which has no native Swift reader. The cloud API provides structured heartbeat data (project, file, language, branch) and is straightforward to call with the API key already stored locally in `~/.wakatime.cfg`.

**Alternatives considered**:
- Reading BoltDB locally: Requires a C-compatible BoltDB library or a Go helper binary. Too complex per Principle IV.
- Parsing wakatime.log: Fragile, not structured, and misses data.
- Ignoring WakaTime entirely: Loses valuable IDE context (project, branch, files).

**API key location**: `~/.wakatime.cfg` under `[settings]` section as `api_key = waka_...`

**Heartbeat fields used**: `entity` (file path), `project`, `branch`, `language`, `time` (Unix timestamp), `category` (coding/debugging/etc.)

**Gotchas**:
- Cloud API requires internet. When offline, WakaTime entries are simply not available — fall back to window-title tracking for IDEs.
- API has rate limits. Batch fetch heartbeats once per sync interval (e.g., every 15 minutes) rather than per-event.
- WakaTime does NOT track browser activity — it only tracks editor/IDE activity. Browser tracking is handled separately by our AX/AppleScript approach.

## R5: SwiftData Background Processing

**Decision**: Use `@ModelActor` for all background SwiftData writes. Pass `PersistentIdentifier` across actor boundaries. Auto-save timer runs on a background actor every 60 seconds.

**Rationale**: @ModelActor provides a properly isolated ModelContext on a background queue. This is the Apple-recommended pattern for SwiftData concurrency. Using PersistentIdentifier ensures no data races from passing model objects across contexts.

**Alternatives considered**:
- ModelContext on main thread: Blocks UI during writes. Unacceptable for a background tracker.
- Core Data (NSManagedObjectContext): Would work but adds complexity alongside existing SwiftData. No reason to mix.
- File-based persistence: Loses query capabilities and relationship modeling.

**Key patterns**:
- `@ModelActor actor TimeTrackingActor { ... }` — owns its own ModelContext
- `Task.detached { let actor = TimeTrackingActor(modelContainer: container) }` — ensures background queue
- `modelContext.save()` explicitly after critical writes (don't rely on autosave)
- Background saves auto-merge into SwiftUI `@Query` results

**Gotchas**:
- Regular `Task {}` inherits caller's executor. Must use `Task.detached {}` for true background.
- SwiftData models are NOT Sendable. Always pass PersistentIdentifier, never model objects.
- Swift 6 strict concurrency will flag many patterns. @ModelActor handles most isolation.

## R6: Accessibility Permission Flow

**Decision**: Check with `AXIsProcessTrusted()`, prompt with `AXIsProcessTrustedWithOptions`, deep-link to System Settings, poll every 1s until granted.

**Rationale**: This is the standard macOS pattern used by tools like RescueTime and Timing. There is no callback when permission is granted, so polling is the only option. The guided prompt explains why the permission is needed and provides a direct link.

**Key APIs**:
- `AXIsProcessTrusted()` — check current status
- `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` — prompt (first time only)
- `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` — deep-link URL
- Timer polling every 1 second until `AXIsProcessTrusted()` returns true

**App configuration required**:
- `NSAccessibilityUsageDescription` in Info.plist
- App CANNOT use App Sandbox (Accessibility inspection is incompatible)
- Hardened Runtime is fine (no special entitlement needed for Accessibility)

**Gotchas**:
- The system prompt dialog only shows once. Subsequent calls open System Settings silently.
- Changing code signing identity requires removing and re-adding the app in Settings.
- macOS may cache the TCC decision. User must manually toggle in Settings after a denial.

## R7: Existing Codebase Integration Points

**Decision**: Extend existing 004 models and services. No structural changes to existing code.

**Findings from codebase exploration**:

**Already exists (from 004 phases 1-3)**:
- `TimeEntry` model with: id, startTime, endTime, duration, notes, bookingStatus, source, isInProgress, todo relationship
- `BookingStatus` enum: unreviewed, reviewed, exported
- `EntrySource` enum: manual, timer, autoDetected
- `TimerManager` (@Observable): activeEntryID, activeTodoTitle, elapsedSeconds, isRunning — NOT yet wired
- `MenuBarView`: timer display with stub start/stop buttons (comment: "Will be wired in US4")
- `JiraLink`, `BitbucketLink`, `IntegrationConfig` models — ready for API services
- Empty directories: `Networking/`, `Settings/`, `TimeTracking/`

**Extensions needed for 005**:
- `TimeEntry`: Add `applicationName: String?`, `browserContext: BrowserContext?` (codable struct), `wakatimeContext: WakatimeContext?` (codable struct)
- `Enums.swift`: Add `ExportStatus.booked` case, add new context-related types
- `TimerManager`: Wire to actual TrackingCoordinator
- `ModelContainer` in app entry point: Register new model types (TrackedApplication, BrowserContextRule, LearnedPattern, ExportRecord)
