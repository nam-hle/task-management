# Data Model: Application & Browser Time Tracking

**Feature**: 005-app-time-tracking | **Date**: 2026-02-14

## Entity Overview

```
┌─────────────────┐     ┌──────────────┐     ┌───────────────┐
│  TrackedApp     │     │    Todo       │     │  JiraLink     │
│  (allowlist)    │     │  (existing)   │◄────│  (existing)   │
└─────────────────┘     └──────┬───────┘     └───────────────┘
                               │
                               │ 1:N
                               ▼
┌─────────────────┐     ┌──────────────┐     ┌───────────────┐
│ BrowserContext  │     │  TimeEntry   │     │ BitbucketLink │
│   Rule          │     │  (extended)  │◄────│  (existing)   │
└─────────────────┘     └──────┬───────┘     └───────────────┘
                               │ N:1
                               ▼
                        ┌──────────────┐     ┌───────────────┐
                        │ ExportRecord │     │LearnedPattern │
                        └──────────────┘     └───────────────┘
```

## Existing Models (from 004, no changes)

### Todo
Already defined. Relevant relationships for 005:
- `timeEntries: [TimeEntry]` — cascade delete
- `jiraLink: JiraLink?` — used for auto-linking detected Jira tickets
- `bitbucketLink: BitbucketLink?` — used for auto-linking detected PRs

### JiraLink
Already defined. Fields used by 005 for auto-matching:
- `ticketID: String` — matched against extracted Jira IDs from browser tabs
- `cachedSummary: String?`, `cachedStatus: String?`, `cachedAssignee: String?`

### BitbucketLink
Already defined. Fields used by 005 for auto-matching:
- `repositorySlug: String`, `prNumber: Int` — matched against extracted PR info
- `cachedTitle: String?`, `cachedStatus: String?`

### IntegrationConfig
Already defined. Used by 005 for API credentials:
- `type: IntegrationType` (jira/bitbucket)
- `serverURL: String`, `username: String`
- Auth tokens stored in Keychain (keyed by integration ID)

## Extended Model

### TimeEntry (extended)

Existing fields preserved. New fields added for automatic tracking context.

| Field | Type | New? | Description |
|-------|------|------|-------------|
| id | UUID | existing | Primary key |
| startTime | Date | existing | Entry start |
| endTime | Date? | existing | Entry end (nil if in-progress) |
| duration | TimeInterval | existing | Computed or stored duration |
| notes | String? | existing | User notes |
| bookingStatus | BookingStatus | existing | unreviewed/reviewed/exported/booked |
| source | EntrySource | existing | manual/timer/autoDetected/wakatime |
| isInProgress | Bool | existing | Active tracking flag |
| createdAt | Date | existing | Creation timestamp |
| todo | Todo? | existing | Linked todo (inverse of Todo.timeEntries) |
| applicationName | String? | **NEW** | Name of tracked application (e.g., "Google Chrome") |
| applicationBundleID | String? | **NEW** | Bundle identifier for reliable app matching |
| browserContext | BrowserContextData? | **NEW** | Codable struct with Jira/BB/generic browser context |
| wakatimeContext | WakatimeContextData? | **NEW** | Codable struct with WakaTime project/file/branch |
| label | String? | **NEW** | User-provided label for manual timer entries |
| isAutoApproved | Bool | **NEW** | True if approved via learned pattern (not manual review) |
| learnedPattern | LearnedPattern? | **NEW** | The pattern that auto-approved this entry (if any) |

**Codable embedded structs** (stored as JSON in SwiftData):

```
BrowserContextData {
    contextType: String        // "jira", "bitbucket", "generic"
    ticketID: String?          // e.g., "PROJ-123"
    ticketSummary: String?     // e.g., "Fix login bug"
    prNumber: Int?             // e.g., 42
    repositorySlug: String?    // e.g., "my-repo"
    prTitle: String?           // e.g., "Fix login flow"
    rawTabTitle: String        // Original tab title for fallback
    tabURL: String?            // URL if available (Chrome only)
    browserName: String        // "Google Chrome" or "Firefox"
}

WakatimeContextData {
    project: String            // WakaTime project name
    branch: String?            // Git branch
    language: String?          // Programming language
    file: String?              // Last active file path
    category: String?          // "coding", "debugging", etc.
}
```

**State transitions for bookingStatus**:

```
                  ┌─── learned pattern match ───┐
                  ▼                              │
unreviewed ──► reviewed ──► exported ──► booked
    │              ▲
    └── manual ────┘
        review
```

- `unreviewed` → `reviewed`: User confirms in review view, OR learned pattern auto-approves
- `reviewed` → `exported`: User triggers export action
- `exported` → `booked`: User confirms booking in Timension

## New Models

### TrackedApplication

Defines which applications are in the monitoring allowlist.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| name | String | Display name (e.g., "Google Chrome") |
| bundleIdentifier | String | macOS bundle ID (e.g., "com.google.Chrome"). Unique constraint. |
| isBrowser | Bool | Whether browser context detection is enabled |
| isPreConfigured | Bool | True for Firefox/Chrome (cannot be removed, only disabled) |
| isEnabled | Bool | Whether currently being tracked |
| sortOrder | Int | Display order in settings |
| createdAt | Date | When added to allowlist |

**Pre-configured entries** (seeded on first launch):
- Google Chrome (`com.google.Chrome`, isBrowser: true)
- Firefox (`org.mozilla.firefox`, isBrowser: true)

**Suggested additions** (shown in settings but not enabled by default):
- IntelliJ IDEA (`com.jetbrains.intellij`)
- Xcode (`com.apple.dt.Xcode`)
- Visual Studio Code (`com.microsoft.VSCode`)
- Terminal (`com.apple.Terminal`)
- Slack (`com.tinyspeck.slackmacgap`)

### BrowserContextRule

Configurable patterns for extracting context from browser tab titles/URLs.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| name | String | Display name (e.g., "Jira Tickets") |
| contextType | String | "jira", "bitbucket", or custom identifier |
| titlePattern | String | Regex applied to tab title (e.g., `[A-Z]+-\\d+`) |
| urlPattern | String? | Regex applied to URL (Chrome only, e.g., `bitbucket\\.org/.+/pull-requests/\\d+`) |
| extractionGroup | Int | Regex capture group index for the primary identifier |
| isEnabled | Bool | Whether this rule is active |
| isBuiltIn | Bool | True for Jira/Bitbucket defaults (cannot be deleted) |
| sortOrder | Int | Evaluation priority (lower = higher priority) |

**Built-in rules** (seeded on first launch):
1. Jira: titlePattern `([A-Z][A-Z0-9]+-\\d+)`, contextType "jira"
2. Bitbucket PR: titlePattern `Pull request #(\\d+)`, urlPattern `pull-requests/(\\d+)`, contextType "bitbucket"

### LearnedPattern

Validated associations between detected contexts and todos, used for auto-approval.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| contextType | String | "jira", "bitbucket", "wakatime", "custom" |
| identifierValue | String | The specific identifier (e.g., "PROJ-123", "42", "my-project") |
| linkedTodo | Todo? | The todo this pattern maps to |
| confirmationCount | Int | Times user has confirmed this pattern (starts at 1) |
| lastConfirmedAt | Date | Last time user reviewed and confirmed |
| isActive | Bool | False if user has revoked the pattern |
| createdAt | Date | When first learned |

**Validation rules**:
- Unique constraint on (contextType, identifierValue)
- Pattern is created on first manual review confirmation
- confirmationCount increments on each subsequent manual confirmation
- When linkedTodo is deleted/trashed, pattern remains but entries are flagged for manual review (staleness)

### ExportRecord

Tracks export batches for duplicate prevention.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| exportedAt | Date | When the export was generated |
| formattedOutput | String | The copy-ready text that was generated |
| entryCount | Int | Number of time entries included |
| totalDuration | TimeInterval | Sum of all entry durations |
| isBooked | Bool | True after user confirms booking in Timension |
| bookedAt | Date? | When user confirmed booking |
| timeEntries | [TimeEntry] | Many-to-many: entries included in this export |

## Enum Extensions

### BookingStatus (extend existing)

Add `booked` case to existing enum:

```
unreviewed → reviewed → exported → booked
```

### EntrySource (extend existing)

Add `wakatime` case:

```
manual | timer | autoDetected | wakatime
```

### New: TrackingState

Runtime state for the tracking coordinator (not persisted):

```
idle | tracking | paused(reason: PauseReason) | permissionRequired
```

### New: PauseReason

```
userPaused | systemIdle | systemSleep | screenLocked | manualTimerActive
```

## Data Retention

- Time entries: 90 days. Booked entries older than 90 days are purged. Unbooked entries older than 90 days are flagged as overdue.
- Learned patterns: Indefinite (until user revokes or linked todo is permanently deleted).
- Export records: 90 days (same as time entries).
- Tracked applications and browser context rules: Indefinite (user configuration).

## Migration Notes

The existing 004 schema includes: Todo, Project, Tag, TimeEntry, JiraLink, BitbucketLink, IntegrationConfig.

For 005, the schema migration adds:
1. New fields on TimeEntry (applicationName, applicationBundleID, browserContext, wakatimeContext, label, isAutoApproved, learnedPattern relationship)
2. New models: TrackedApplication, BrowserContextRule, LearnedPattern, ExportRecord
3. New enum case: BookingStatus.booked, EntrySource.wakatime

SwiftData handles lightweight migrations automatically for additive changes. The new fields are all optional, so existing TimeEntry records remain valid.
