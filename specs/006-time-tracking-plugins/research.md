# Research: Ticket-Centric Plugin System

**Branch**: `006-time-tracking-plugins` | **Date**: 2026-02-15

## Research Tasks & Findings

### R1: Reading Chrome Tab Titles/URLs via AppleScript on macOS

**Decision**: Use AppleScript via `NSAppleScript` to read Chrome's active tab.

**Rationale**: Chrome exposes full tab information (title, URL) through its AppleScript dictionary. This is the standard approach for macOS automation of Chrome and requires no additional permissions beyond what the app already has.

**Script**:
```applescript
tell application "Google Chrome"
    set tabTitle to title of active tab of front window
    set tabURL to URL of active tab of front window
    return tabTitle & "\n" & tabURL
end tell
```

**Alternatives considered**:
- Accessibility API (AXUIElement): Can read window title but not the URL. Less reliable for tab-specific data.
- Chrome DevTools Protocol: Requires launching Chrome with debugging port. Intrusive and fragile.
- Browser extension: Out-of-scope per spec (no runtime extension loading).

**Constraints**:
- Chrome must be running and have at least one window open.
- AppleScript calls are blocking — run on background thread.
- If Chrome is not installed, `NSAppleScript` returns an error immediately — use this for availability detection (FR-014).

---

### R2: Reading Firefox Tab Titles on macOS

**Decision**: Parse Firefox window title via AXUIElement accessibility API.

**Rationale**: Firefox does not expose an AppleScript dictionary. The window title is the only reliable source. Firefox's default title format includes the page title: `"Page Title — Mozilla Firefox"` or `"Page Title - Mozilla Firefox"`.

**Extraction approach**:
1. Get frontmost Firefox window via AXUIElement
2. Read `kAXTitleAttribute`
3. Strip the ` — Mozilla Firefox` / ` - Mozilla Firefox` suffix
4. Extract ticket/PR patterns from the remaining page title

**Alternatives considered**:
- Firefox AppleScript: Firefox has minimal AppleScript support — only `activate` and `open location`. Cannot read tab title or URL.
- Firefox Extension (Native Messaging): Out-of-scope per spec.
- Accessibility title via NSWorkspace: Only gives app name, not window title.

**Constraints**:
- Cannot read the URL — only the window/tab title is available.
- Requires Accessibility permission (already granted for app tracking).
- Firefox must be the frontmost application when queried.
- If Firefox is not installed, the AXUIElement call fails — use for availability detection.

---

### R3: Interval Merging Algorithm for Deduplication (FR-003)

**Decision**: Standard sweep-line interval merge, O(n log n).

**Rationale**: Well-known algorithm with predictable performance. For ~500 entries/day, sorting + merging takes negligible time.

**Algorithm**:
```
Input: [(start: Date, end: Date)] intervals for a single ticket
1. Sort by start ascending
2. Initialize merged = [first interval]
3. For each remaining interval:
   a. If interval.start <= merged.last.end:
      merged.last.end = max(merged.last.end, interval.end)
   b. Else:
      Append interval to merged
4. Wall-clock total = sum of (end - start) for each merged interval
```

**Edge cases**:
- In-progress entries (endTime == nil): Use current time as end for deduplication.
- Entries with zero duration: Skip in aggregation.
- Single entry per ticket: No merging needed, return as-is.

**Alternatives considered**:
- Segment tree: Overkill for ~500 entries. O(n log n) sweep is sufficient.
- Real-time incremental merge: More complex, no performance benefit at this scale.

---

### R4: Plugin Protocol Design Patterns in Swift

**Decision**: Use Swift protocol with associated lifecycle methods. PluginManager holds `[any TimeTrackingPlugin]` using existential types.

**Rationale**: Swift's protocol system with existential containers (`any Protocol`) is the natural fit for in-process plugins. No need for dynamic loading — all plugins are compiled in and registered at startup.

**Pattern**:
```swift
protocol TimeTrackingPlugin: AnyObject, Identifiable where ID == String {
    var id: String { get }
    var displayName: String { get }
    var status: PluginStatus { get }

    func start() async throws
    func stop() async throws
    func isAvailable() -> Bool
}
```

**Plugin lifecycle**:
1. App startup: PluginManager creates all known plugin instances
2. Each plugin checks `isAvailable()` — if false, status = `.unavailable`
3. PluginManager reads UserDefaults for enabled state
4. Enabled + available plugins get `start()` called
5. On disable: `stop()` called, future data collection stops
6. On app quit: `stopAll()` called

**Alternatives considered**:
- Generic protocol with associated types: Complicates heterogeneous collection. Existential `any` is simpler.
- Runtime plugin loading (dylib/bundle): Out of scope per spec assumption.
- Delegate pattern: Less clean for multiple independent plugins.

---

### R5: App Tracking Plugin Migration Strategy

**Decision**: Create `AppTrackingPlugin` that owns WindowMonitorService and IdleDetectionService. TrackingCoordinator becomes a thin orchestrator that delegates to PluginManager.

**Rationale**: The current TrackingCoordinator does three things: (1) manages WindowMonitor + IdleDetection lifecycle, (2) handles app switch events to create/finalize TimeEntries, (3) manages manual timers and UI state. Items 1-2 become the AppTrackingPlugin. Item 3 stays on TrackingCoordinator since manual timers are core, not plugin-specific.

**Migration plan**:
1. AppTrackingPlugin takes ownership of WindowMonitorService and IdleDetectionService
2. App switch handling (debounce, entry creation, finalization) moves to AppTrackingPlugin
3. TrackingCoordinator retains: manual timer, elapsed display, state observation, PluginManager reference
4. TrackingCoordinator delegates `startTracking()`/`stopTracking()` to PluginManager
5. AppTrackingPlugin sets `sourcePluginID = "app-tracking"` on created entries
6. Auto-save, midnight split, crash recovery remain in TimeEntryService (shared infrastructure)

**Risk**: Largest refactor — must preserve all existing behavior (pause/resume, idle detection, crash recovery).

---

### R6: WakaTime Plugin Data Flow Change

**Decision**: WakaTimePlugin fetches data and creates TimeEntry records directly, replacing the current BranchActivity intermediate model.

**Rationale**: Currently, WakaTimeService produces `[BranchActivity]` which views consume directly. With the plugin system, WakaTime data should flow through the same TimeEntry → TicketAggregation pipeline as all other sources.

**Data flow change**:
```
BEFORE: WakaTimeService → [BranchActivity] → TicketsView (direct)
AFTER:  WakaTimePlugin → TimeEntryService → [TimeEntry] → TicketAggregationService → TicketsView
```

**Migration details**:
1. WakaTimePlugin calls existing WakaTimeService.fetchBranches() internally
2. For each BranchSegment, creates a TimeEntry with:
   - `sourcePluginID = "wakatime"`
   - `ticketID` = inferred via TicketInferenceService
   - `contextMetadata` = JSON with project, branch name
   - `startTime`/`endTime` from segment
3. Deduplication with existing entries: check for overlapping wakatime entries before inserting
4. BranchActivity/BranchSegment types remain internal to WakaTimeService
5. TicketsView and BranchesView switch from consuming WakaTimeService directly to reading TimeEntries

**Impact**: BranchesView may need rethinking — it currently shows WakaTime-specific branch grouping. Could become a "source detail" view that any plugin can populate, or be removed in favor of the ticket-centric dashboard.

---

### R7: Browser Ticket Extraction Patterns

**Decision**: Use regex-based extraction with configurable patterns. Default patterns for Jira and Bitbucket.

**Jira ticket from page title**:
- Pattern: `([A-Z][A-Z0-9]+-\d+)` — same as existing TicketInferenceService
- Example: `"PROJ-123: Fix login bug - Jira"` → `PROJ-123`
- Example: `"[PROJ-456] Dashboard update - Jira"` → `PROJ-456`

**Bitbucket PR from page title/URL**:
- Title pattern: `Pull request #(\d+)` or `PR-(\d+)`
- URL pattern: `/projects/([^/]+)/repos/([^/]+)/pull-requests/(\d+)` (Bitbucket Server)
- URL pattern: `bitbucket.org/([^/]+)/([^/]+)/pull-requests/(\d+)` (Bitbucket Cloud)
- Resolution: PR → ticket requires either branch name in PR title or a ticket override rule

**Confluence/other work pages**:
- Detect known work domains (configurable) and track as unassigned with page title as context

**Alternatives considered**:
- ML-based extraction: Overkill for structured patterns. Regex is sufficient for Jira/Bitbucket.
- Browser extension for richer data: Out of scope.
