// Service Protocol Contracts for 005-app-time-tracking
// These define the public interfaces for all new services.
// Implementation details are deferred to task execution.

import Foundation
import SwiftData

// MARK: - Window Monitoring

/// Monitors the active application window and emits context changes.
protocol WindowMonitoring {
    /// Whether the monitor is currently active
    var isTracking: Bool { get }

    /// Start monitoring active window changes.
    /// Requires Accessibility permission.
    func startMonitoring() throws

    /// Stop monitoring.
    func stopMonitoring()

    /// Returns the currently active application info, or nil if unavailable.
    func currentApplication() -> ApplicationInfo?

    /// Callback invoked when the focused application changes.
    /// Only fires after the minimum switch duration threshold (default 30s).
    var onApplicationChanged: ((ApplicationInfo) -> Void)? { get set }
}

struct ApplicationInfo {
    let name: String
    let bundleIdentifier: String
    let pid: pid_t
    let windowTitle: String?
    let timestamp: Date
}

// MARK: - Browser Context Detection

/// Extracts contextual information from browser tabs.
protocol BrowserContextDetecting {
    /// Extract context from the currently active browser tab.
    /// - Parameter app: The browser application info
    /// - Returns: Extracted context, or nil if not a recognized page
    func extractContext(from app: ApplicationInfo) async -> BrowserContextData?
}

// MARK: - Idle Detection

/// Detects user idle state and system sleep/lock events.
protocol IdleDetecting {
    /// Current idle duration in seconds
    var currentIdleSeconds: TimeInterval { get }

    /// Whether the system is currently idle (exceeds threshold)
    var isIdle: Bool { get }

    /// Start monitoring idle state and system events.
    func startMonitoring()

    /// Stop monitoring.
    func stopMonitoring()

    /// Callbacks
    var onIdleStarted: (() -> Void)? { get set }
    var onIdleEnded: (() -> Void)? { get set }
    var onSleepStarted: (() -> Void)? { get set }
    var onWakeUp: (() -> Void)? { get set }
    var onScreenLocked: (() -> Void)? { get set }
    var onScreenUnlocked: (() -> Void)? { get set }
}

// MARK: - Time Entry Management

/// CRUD operations for time entries with merge, split, and review capabilities.
protocol TimeEntryManaging {
    /// Create a new time entry (automatic or manual).
    func create(
        todoID: PersistentIdentifier?,
        applicationName: String?,
        browserContext: BrowserContextData?,
        source: String,
        startTime: Date
    ) throws -> PersistentIdentifier

    /// Finalize an in-progress entry with an end time.
    func finalize(entryID: PersistentIdentifier, endTime: Date) throws

    /// Merge multiple entries into one (combined duration, earliest start, latest end).
    func merge(entryIDs: [PersistentIdentifier]) throws -> PersistentIdentifier

    /// Split an entry at a given timestamp into two entries.
    func split(entryID: PersistentIdentifier, at splitTime: Date) throws
        -> (PersistentIdentifier, PersistentIdentifier)

    /// Update entry fields (start/end time, notes, todo link, booking status).
    func update(entryID: PersistentIdentifier, changes: TimeEntryChanges) throws

    /// Mark entries as reviewed (individually or bulk).
    func markReviewed(entryIDs: [PersistentIdentifier]) throws

    /// Fetch entries for a specific date, optionally filtered by status.
    func entries(for date: Date, status: String?) throws -> [PersistentIdentifier]

    /// Auto-save: persist the current in-progress entry's duration.
    func autoSave(entryID: PersistentIdentifier, currentTime: Date) throws

    /// Purge booked entries older than the retention period.
    func purgeExpired(retentionDays: Int) throws -> Int
}

struct TimeEntryChanges {
    var startTime: Date?
    var endTime: Date?
    var notes: String?
    var todoID: PersistentIdentifier?
    var bookingStatus: String?
    var label: String?
}

// MARK: - WakaTime Integration

/// Imports coding activity data from WakaTime.
protocol WakaTimeIntegrating {
    /// Whether WakaTime is configured (API key available).
    var isConfigured: Bool { get }

    /// Fetch heartbeats for a given date and convert to time entry data.
    func fetchActivity(for date: Date) async throws -> [WakatimeActivityRecord]

    /// Deduplicate WakaTime records against existing auto-detected entries.
    func deduplicateAndImport(
        records: [WakatimeActivityRecord],
        existingEntries: [PersistentIdentifier]
    ) throws -> [PersistentIdentifier]
}

struct WakatimeActivityRecord {
    let project: String
    let branch: String?
    let language: String?
    let file: String?
    let category: String?
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
}

// MARK: - Learned Pattern Management

/// Manages learned context-to-todo associations for auto-approval.
protocol LearnedPatternManaging {
    /// Find a matching pattern for the given context.
    func findMatch(contextType: String, identifier: String) throws
        -> PersistentIdentifier?

    /// Create or reinforce a pattern from a confirmed review.
    func learnFromReview(
        contextType: String,
        identifier: String,
        todoID: PersistentIdentifier
    ) throws -> PersistentIdentifier

    /// Revoke (deactivate) a learned pattern.
    func revoke(patternID: PersistentIdentifier) throws

    /// List all active patterns.
    func activePatterns() throws -> [PersistentIdentifier]

    /// Flag stale patterns (linked todo completed or trashed).
    func flagStalePatterns() throws -> Int
}

// MARK: - Export

/// Generates formatted time summaries for Timension booking.
protocol TimeExporting {
    /// Generate a formatted export for the given date's reviewed entries.
    func generateExport(for date: Date) throws -> ExportResult

    /// Mark entries as exported and create an export record.
    func confirmExport(entryIDs: [PersistentIdentifier]) throws -> PersistentIdentifier

    /// Mark an export record as booked (user confirmed in Timension).
    func markBooked(exportID: PersistentIdentifier) throws

    /// Check for duplicate export attempts.
    func checkDuplicates(entryIDs: [PersistentIdentifier]) throws -> [PersistentIdentifier]
}

struct ExportResult {
    let formattedText: String
    let entries: [ExportEntry]
    let totalDuration: TimeInterval
}

struct ExportEntry {
    let contextLabel: String   // e.g., "PROJ-123: Fix login bug"
    let duration: TimeInterval
    let notes: String?
}

// MARK: - Tracking Coordinator

/// Orchestrates all tracking services into a unified tracking loop.
protocol TrackingCoordinating {
    /// Current tracking state
    var state: TrackingState { get }

    /// Start automatic time tracking (requires Accessibility permission).
    func startTracking() throws

    /// Stop automatic time tracking.
    func stopTracking()

    /// Start a manual timer with an optional label.
    func startManualTimer(label: String?, todoID: PersistentIdentifier?) throws

    /// Stop the active manual timer.
    func stopManualTimer() throws

    /// Pause tracking (user-initiated or system-triggered).
    func pause(reason: String)

    /// Resume tracking after pause.
    func resume()
}

enum TrackingState {
    case idle
    case tracking
    case paused(reason: String)
    case permissionRequired
}

// MARK: - Accessibility Permission

/// Checks and manages macOS Accessibility permission.
protocol AccessibilityPermissionChecking {
    /// Whether Accessibility permission is currently granted.
    var isGranted: Bool { get }

    /// Prompt the user for Accessibility permission.
    func promptForPermission()

    /// Open System Settings > Accessibility directly.
    func openAccessibilitySettings()

    /// Start polling for permission changes (no callback exists).
    func startPolling(interval: TimeInterval, onGranted: @escaping () -> Void)

    /// Stop polling.
    func stopPolling()
}

// MARK: - API Adapters (Jira, Bitbucket)

/// Fetches Jira ticket details for context enrichment.
protocol JiraAPIAdapting {
    /// Fetch ticket details by ID.
    func fetchTicket(id: String) async throws -> JiraTicketInfo

    /// Search tickets by query (for manual linking).
    func searchTickets(query: String) async throws -> [JiraTicketInfo]
}

struct JiraTicketInfo {
    let ticketID: String
    let summary: String
    let status: String
    let assignee: String?
}

/// Fetches Bitbucket PR details for context enrichment.
protocol BitbucketAPIAdapting {
    /// Fetch PR details by repository and number.
    func fetchPR(repository: String, number: Int) async throws -> BitbucketPRInfo
}

struct BitbucketPRInfo {
    let prNumber: Int
    let repositorySlug: String
    let title: String
    let status: String
    let author: String
    let reviewers: [String]
}

// MARK: - Keychain

/// Securely stores and retrieves credentials.
protocol KeychainAccessing {
    func store(key: String, value: String, service: String) throws
    func retrieve(key: String, service: String) throws -> String?
    func delete(key: String, service: String) throws
}
