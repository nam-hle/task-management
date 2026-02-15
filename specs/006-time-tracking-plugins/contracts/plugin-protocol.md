# Plugin Protocol Contract

**Branch**: `006-time-tracking-plugins` | **Date**: 2026-02-15

## TimeTrackingPlugin Protocol

```swift
/// Protocol that all time tracking sources must implement.
/// Each plugin independently collects activity data and optionally resolves it to tickets.
protocol TimeTrackingPlugin: AnyObject, Identifiable where ID == String {
    /// Unique identifier (e.g., "app-tracking", "wakatime", "chrome", "firefox")
    var id: String { get }

    /// Human-readable display name (e.g., "App Tracking", "WakaTime")
    var displayName: String { get }

    /// Current runtime status
    var status: PluginStatus { get }

    /// Check if this plugin's dependencies are available (app installed, etc.)
    /// Called once at startup before attempting to start.
    func isAvailable() -> Bool

    /// Begin collecting data. Called when plugin is enabled and available.
    /// For real-time plugins: starts monitoring.
    /// For periodic plugins: starts fetch timer.
    func start() async throws

    /// Stop collecting data. Called on disable or app quit.
    /// Must be idempotent (safe to call when already stopped).
    func stop() async throws
}
```

## PluginManager

```swift
/// Manages all registered plugins. Handles lifecycle, enable/disable, error isolation.
@Observable
@MainActor
final class PluginManager {
    /// All registered plugins (in registration order)
    private(set) var plugins: [any TimeTrackingPlugin]

    /// Register a plugin instance. Called once at app startup.
    func register(_ plugin: any TimeTrackingPlugin)

    /// Start all enabled and available plugins.
    func startAll() async

    /// Stop all running plugins.
    func stopAll() async

    /// Enable a plugin by ID. Starts it if available.
    func enable(pluginID: String) async

    /// Disable a plugin by ID. Stops data collection.
    func disable(pluginID: String) async

    /// Check if a plugin is enabled (reads from UserDefaults).
    func isEnabled(pluginID: String) -> Bool

    /// Get a plugin by ID.
    func plugin(id: String) -> (any TimeTrackingPlugin)?
}
```

**Enabled state storage**: `UserDefaults` key `"plugin.{id}.enabled"`, default `true` for app-tracking and wakatime, `false` for browser plugins.

## TicketAggregationService

```swift
/// Computes ticket aggregations from TimeEntry records.
/// Stateless — computes on demand from current data.
struct TicketAggregationService {
    /// Aggregate all entries for a given date into ticket groups.
    /// Returns tickets sorted by total (deduplicated) duration descending.
    /// Entries with no ticketID are grouped under a special "unassigned" ticket.
    static func aggregate(entries: [TimeEntry]) -> [TicketAggregate]

    /// Deduplicate overlapping intervals within a set of entries.
    /// Returns wall-clock duration (merged intervals).
    static func deduplicatedDuration(entries: [TimeEntry]) -> TimeInterval

    /// Merge overlapping time intervals.
    /// Input: unsorted array of (start, end) pairs.
    /// Output: sorted, non-overlapping merged intervals.
    static func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)]
}
```

## Plugin Implementations

### AppTrackingPlugin

```swift
/// Wraps WindowMonitorService + IdleDetectionService.
/// Creates TimeEntry records on app switches with sourcePluginID = "app-tracking".
@MainActor
final class AppTrackingPlugin: TimeTrackingPlugin {
    let id = "app-tracking"
    let displayName = "App Tracking"

    /// Requires Accessibility permission
    func isAvailable() -> Bool

    /// Starts WindowMonitorService + IdleDetectionService
    /// Sets up app switch handler that creates/finalizes TimeEntries
    func start() async throws

    /// Stops monitoring services
    func stop() async throws

    // Delegate methods from TrackingCoordinator:
    func pause(reason: PauseReason)
    func resume()
    var state: TrackingState { get }
    var currentAppName: String? { get }
    var currentEntryID: PersistentIdentifier? { get }
    var elapsedSeconds: Int { get }
}
```

### WakaTimePlugin

```swift
/// Wraps WakaTimeService. Periodically fetches WakaTime data and creates TimeEntries.
@MainActor
final class WakaTimePlugin: TimeTrackingPlugin {
    let id = "wakatime"
    let displayName = "WakaTime"

    /// Checks for ~/.wakatime.cfg API key
    func isAvailable() -> Bool

    /// Starts periodic fetch timer (fetches on start + every syncInterval)
    func start() async throws

    /// Stops fetch timer
    func stop() async throws

    /// Fetch and create entries for a specific date
    func fetchAndSync(for date: Date) async throws
}
```

### ChromePlugin

```swift
/// Reads Chrome active tab title/URL via AppleScript.
/// Detects Jira tickets and Bitbucket PRs from tab context.
@MainActor
final class ChromePlugin: TimeTrackingPlugin {
    let id = "chrome"
    let displayName = "Chrome"

    /// Checks if Google Chrome is installed
    func isAvailable() -> Bool

    /// Starts monitoring — when Chrome becomes active app, reads tab info
    func start() async throws

    /// Stops monitoring
    func stop() async throws
}
```

### FirefoxPlugin

```swift
/// Reads Firefox window title via AXUIElement accessibility API.
/// Detects Jira tickets and Bitbucket PRs from title.
@MainActor
final class FirefoxPlugin: TimeTrackingPlugin {
    let id = "firefox"
    let displayName = "Firefox"

    /// Checks if Firefox is installed
    func isAvailable() -> Bool

    /// Starts monitoring — when Firefox becomes active app, reads window title
    func start() async throws

    /// Stops monitoring
    func stop() async throws
}
```

### BrowserTabService (shared)

```swift
/// Shared utilities for browser plugins.
struct BrowserTabService {
    /// Read Chrome active tab title and URL via AppleScript.
    /// Returns nil if Chrome is not running or has no windows.
    static func readChromeTab() async -> (title: String, url: String)?

    /// Read Firefox window title via AXUIElement.
    /// Returns nil if Firefox is not running or has no windows.
    static func readFirefoxWindowTitle() async -> String?

    /// Extract Jira ticket ID from text (title or URL).
    /// Pattern: [A-Z][A-Z0-9]+-\d+
    static func extractTicketID(from text: String) -> String?

    /// Extract Bitbucket PR info from URL.
    /// Returns (workspace, repo, prNumber) if matched.
    static func extractBitbucketPR(from url: String) -> (workspace: String, repo: String, prNumber: Int)?

    /// Check if an application bundle exists on the system.
    static func isAppInstalled(bundleID: String) -> Bool
}
```
