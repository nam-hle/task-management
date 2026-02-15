# Data Model: Ticket-Centric Plugin System

**Branch**: `006-time-tracking-plugins` | **Date**: 2026-02-15

## Entity Changes

### TimeEntry (MODIFY — existing @Model)

**New fields** (added to existing model, all optional with defaults for migration):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `sourcePluginID` | `String?` | `nil` | Plugin identifier that created this entry (e.g., "app-tracking", "wakatime", "chrome", "firefox"). `nil` for legacy entries created before plugin system. |
| `ticketID` | `String?` | `nil` | Resolved ticket ID (e.g., "PROJ-123"). `nil` means unassigned. Set by plugin ticket resolution or manual assignment. |
| `contextMetadata` | `String?` | `nil` | JSON-encoded contextual data from the source plugin. Schema varies by plugin (see below). |

**Existing fields preserved** (no changes):
- `id`, `startTime`, `endTime`, `duration`, `notes`, `bookingStatus`, `source`, `isInProgress`, `createdAt`
- `applicationName`, `applicationBundleID`, `label`
- `isAutoApproved`, `learnedPattern`
- `todo` relationship

**Context metadata schemas** (JSON string, per plugin):

```json
// App Tracking Plugin
{ "windowTitle": "MyProject — IntelliJ IDEA" }

// WakaTime Plugin
{ "project": "my-project", "branch": "feature/PROJ-123-login" }

// Chrome Plugin
{ "pageTitle": "PROJ-123: Fix login bug - Jira", "pageURL": "https://jira.example.com/browse/PROJ-123" }

// Firefox Plugin
{ "pageTitle": "Pull request #42: Add feature - Bitbucket", "parsedFrom": "windowTitle" }
```

**Migration**: All new fields are optional with `nil` default — SwiftData lightweight migration handles this automatically. No explicit migration code needed.

---

### TicketOverride (MODIFY — existing @Model)

**New fields**:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `urlPattern` | `String?` | `nil` | Regex pattern to match against page URLs (for browser plugins). |
| `appNamePattern` | `String?` | `nil` | Regex pattern to match against application names (for app tracking plugin). |
| `priority` | `Int` | `0` | Resolution priority — higher values take precedence when multiple rules match. |

**Existing fields preserved**:
- `id`, `project`, `branch`, `ticketID`, `createdAt`

**Usage**: During ticket resolution, override rules are checked in priority order. A rule matches if any of its patterns (branch, URL, app name) match the activity context. First match wins.

---

### PluginStatus (NEW — enum, not persisted)

```
enum PluginStatus: Equatable {
    case active          // Running and collecting data
    case inactive        // Disabled by user
    case error(String)   // Failed with message
    case permissionRequired  // Needs accessibility or other permission
    case unavailable     // App not installed or dependency missing
}
```

Not a SwiftData model — exists only in memory as plugin runtime state.

---

### Ticket (COMPUTED — not persisted)

```
struct TicketAggregate {
    let ticketID: String          // e.g., "PROJ-123" or "unassigned"
    let totalDuration: TimeInterval   // Wall-clock deduplicated
    let rawDuration: TimeInterval     // Sum of all source durations (before dedup)
    let entries: [TimeEntry]          // All contributing entries
    let sourceBreakdown: [SourceDuration]  // Per-plugin durations
}

struct SourceDuration {
    let pluginID: String          // e.g., "wakatime"
    let pluginDisplayName: String // e.g., "WakaTime"
    let duration: TimeInterval    // Raw duration from this source
    let entryCount: Int
}
```

Computed at query time by `TicketAggregationService`. Never stored in database.

---

### EntrySource (MODIFY — existing enum)

**Updated cases**:

| Case | Description | Usage |
|------|-------------|-------|
| `manual` | User-created manual entry | Core (not plugin) |
| `timer` | User-started manual timer | Core (not plugin) |
| `autoDetected` | App tracking plugin | `sourcePluginID = "app-tracking"` |
| `wakatime` | WakaTime plugin | `sourcePluginID = "wakatime"` |
| `edited` | User-edited entry | Preserves original source in `sourcePluginID` |
| `chrome` | Chrome browser plugin | `sourcePluginID = "chrome"` — **NEW** |
| `firefox` | Firefox browser plugin | `sourcePluginID = "firefox"` — **NEW** |

The `source` enum provides quick filtering/display. The `sourcePluginID` string provides the authoritative plugin linkage.

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────┐
│                   TimeEntry                      │
│ ─────────────────────────────────────────────── │
│ id: UUID                                         │
│ startTime: Date                                  │
│ endTime: Date?                                   │
│ duration: TimeInterval                           │
│ notes: String                                    │
│ bookingStatus: BookingStatus                     │
│ source: EntrySource                              │
│ isInProgress: Bool                               │
│ createdAt: Date                                  │
│ applicationName: String?                         │
│ applicationBundleID: String?                     │
│ label: String?                                   │
│ isAutoApproved: Bool                             │
│ ─── NEW FIELDS ─────────────────────────────── │
│ sourcePluginID: String?                          │
│ ticketID: String?                                │
│ contextMetadata: String?                         │
│ ─────────────────────────────────────────────── │
│ todo: Todo?              ──────────────────────┐ │
│ learnedPattern: LearnedPattern? ─────────────┐ │ │
└──────────────────────────────────────────────┼─┼─┘
                                               │ │
                    ┌──────────────────────────┘ │
                    │                            │
                    ▼                            ▼
          ┌──────────────┐            ┌──────────────┐
          │LearnedPattern│            │     Todo     │
          └──────────────┘            └──────┬───────┘
                                             │
                              ┌──────────────┼──────────────┐
                              ▼              ▼              ▼
                        ┌──────────┐  ┌──────────┐  ┌────────────┐
                        │ JiraLink │  │BitbucketLk│  │   Project  │
                        └──────────┘  └──────────┘  └────────────┘

┌─────────────────────────────────────────────────┐
│               TicketOverride                     │
│ ─────────────────────────────────────────────── │
│ id: UUID                                         │
│ project: String                                  │
│ branch: String                                   │
│ ticketID: String                                 │
│ createdAt: Date                                  │
│ ─── NEW FIELDS ─────────────────────────────── │
│ urlPattern: String?                              │
│ appNamePattern: String?                          │
│ priority: Int                                    │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│          TicketAggregate (computed)               │
│ ─────────────────────────────────────────────── │
│ ticketID: String                                 │
│ totalDuration: TimeInterval (deduplicated)       │
│ rawDuration: TimeInterval                        │
│ entries: [TimeEntry]                             │
│ sourceBreakdown: [SourceDuration]                │
└─────────────────────────────────────────────────┘
```

## Validation Rules

| Entity | Rule | Source |
|--------|------|--------|
| TimeEntry.sourcePluginID | Must be a registered plugin ID or nil (legacy) | FR-010 |
| TimeEntry.ticketID | Must match `[A-Z][A-Z0-9]+-\d+` pattern or nil | FR-001, Assumptions |
| TimeEntry.contextMetadata | Must be valid JSON string or nil | Internal |
| TicketOverride.urlPattern | Must be valid regex or nil | FR-005 |
| TicketOverride.appNamePattern | Must be valid regex or nil | FR-005 |
| TicketOverride.priority | Non-negative integer | FR-005 |

## State Transitions

### TimeEntry.ticketID Lifecycle

```
nil (created) ──→ "PROJ-123" (auto-resolved by plugin)
nil (created) ──→ "PROJ-123" (manually assigned by user)
"PROJ-123"    ──→ "PROJ-456" (reassigned by user)
"PROJ-123"    ──→ nil (unassigned by user)
```

### PluginStatus Transitions

```
unavailable ──→ (no transitions — app not installed)

inactive ──→ active (user enables)
active   ──→ inactive (user disables)
active   ──→ error("message") (runtime failure)
active   ──→ permissionRequired (permission revoked)
error    ──→ active (auto-retry succeeds)
permissionRequired ──→ active (permission granted + restart)
```
