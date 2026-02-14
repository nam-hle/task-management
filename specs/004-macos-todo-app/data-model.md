# Data Model: Native macOS Todo App

**Feature**: `004-macos-todo-app`
**Date**: 2026-02-14
**Storage**: SwiftData (macOS 14+)

## Entity Relationship Diagram

```text
Project 1──* Todo *──* Tag
                |
                ├── 0..1 JiraLink
                ├── 0..1 BitbucketLink
                └── 0..* TimeEntry
```

## Entities

### Todo

Central entity. All integrations link back to a Todo.

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| id | UUID | Yes | auto | Primary key |
| title | String | Yes | — | Max 500 chars |
| descriptionText | String | No | "" | Markdown-capable |
| priority | Priority (enum) | Yes | .medium | high/medium/low |
| dueDate | Date | No | nil | Optional deadline |
| isCompleted | Bool | Yes | false | Completion status |
| completedAt | Date | No | nil | Set when completed |
| createdAt | Date | Yes | now | Creation timestamp |
| updatedAt | Date | Yes | now | Last modified |
| deletedAt | Date | No | nil | Soft delete (purge after 30 days) |
| sortOrder | Int | Yes | 0 | Manual ordering within project |

**Relationships**:
- `project: Project?` — belongs to one project (optional)
- `tags: [Tag]` — many-to-many
- `jiraLink: JiraLink?` — optional 1:1
- `bitbucketLink: BitbucketLink?` — optional 1:1
- `timeEntries: [TimeEntry]` — one-to-many, cascade delete

**State transitions**:
```text
Active ──(complete)──> Completed
Completed ──(reopen)──> Active
Active/Completed ──(delete)──> Trashed (deletedAt set)
Trashed ──(restore)──> Active (deletedAt cleared)
Trashed ──(30 days)──> Purged (hard delete)
```

**Validation rules**:
- `title` must not be empty or whitespace-only
- `completedAt` must be set when `isCompleted` is true, nil when false
- `deletedAt` when set, todo is excluded from normal queries

### Project

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| id | UUID | Yes | auto | Primary key |
| name | String | Yes | — | Max 100 chars, unique |
| color | String | Yes | "#007AFF" | Hex color code |
| descriptionText | String | No | "" | |
| sortOrder | Int | Yes | 0 | Display ordering |
| createdAt | Date | Yes | now | |

**Relationships**:
- `todos: [Todo]` — one-to-many (inverse of `Todo.project`)

**Validation rules**:
- `name` must not be empty, must be unique across projects

### Tag

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| id | UUID | Yes | auto | Primary key |
| name | String | Yes | — | Max 50 chars, unique |
| color | String | Yes | "#8E8E93" | Hex color code |

**Relationships**:
- `todos: [Tag]` — many-to-many (inverse of `Todo.tags`)

**Validation rules**:
- `name` must not be empty, must be unique across tags

### JiraLink

Optional 1:1 connection between a Todo and a Jira ticket.

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| id | UUID | Yes | auto | Primary key |
| ticketID | String | Yes | — | e.g., "PROJ-123" |
| serverURL | String | Yes | — | Jira instance base URL |
| cachedSummary | String | No | nil | Last fetched summary |
| cachedStatus | String | No | nil | Last fetched status |
| cachedAssignee | String | No | nil | Last fetched assignee name |
| lastSyncedAt | Date | No | nil | When last successfully synced |
| isBroken | Bool | Yes | false | True if ticket deleted/unreachable |

**Relationships**:
- `todo: Todo` — belongs to one todo (inverse of `Todo.jiraLink`)

**Validation rules**:
- `ticketID` must match pattern `[A-Z]+-\d+`
- `serverURL` must be a valid URL

### BitbucketLink

Optional 1:1 connection between a Todo and a Bitbucket PR.

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| id | UUID | Yes | auto | Primary key |
| repositorySlug | String | Yes | — | e.g., "my-repo" |
| prNumber | Int | Yes | — | PR number |
| serverURL | String | Yes | — | Bitbucket instance base URL |
| cachedTitle | String | No | nil | Last fetched PR title |
| cachedStatus | String | No | nil | open/merged/declined |
| cachedAuthor | String | No | nil | PR author display name |
| cachedReviewers | String | No | nil | Comma-separated reviewer names |
| lastSyncedAt | Date | No | nil | When last successfully synced |
| isBroken | Bool | Yes | false | True if PR deleted/unreachable |

**Relationships**:
- `todo: Todo` — belongs to one todo (inverse of `Todo.bitbucketLink`)

**Validation rules**:
- `repositorySlug` must not be empty
- `prNumber` must be > 0
- `serverURL` must be a valid URL

### TimeEntry

A recorded period of work on a todo.

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| id | UUID | Yes | auto | Primary key |
| startTime | Date | Yes | — | When work started |
| endTime | Date | No | nil | nil while timer running |
| duration | TimeInterval | Yes | 0 | Seconds. Computed when endTime set |
| notes | String | No | "" | User-added description |
| bookingStatus | BookingStatus (enum) | Yes | .unreviewed | unreviewed/reviewed/exported |
| source | EntrySource (enum) | Yes | .manual | manual/timer/autoDetected |
| isInProgress | Bool | Yes | false | True while timer running |
| createdAt | Date | Yes | now | |

**Relationships**:
- `todo: Todo` — belongs to one todo (inverse of `Todo.timeEntries`,
  cascade delete from todo)

**State transitions**:
```text
(timer start) ──> InProgress (isInProgress=true, endTime=nil)
(timer stop)  ──> Unreviewed (isInProgress=false, endTime set)
(user review) ──> Reviewed
(user export) ──> Exported
```

**Validation rules**:
- `startTime` must be before `endTime` (when endTime is set)
- `duration` must equal `endTime - startTime` (when endTime is set)
- Only one TimeEntry across all todos may have `isInProgress = true`

### IntegrationConfig

Stored credentials and settings for external integrations.

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| id | UUID | Yes | auto | Primary key |
| type | IntegrationType (enum) | Yes | — | jira/bitbucket |
| serverURL | String | Yes | — | Instance base URL |
| username | String | Yes | — | Email or username |
| syncInterval | TimeInterval | Yes | 900 | Seconds (default 15 min) |
| isEnabled | Bool | Yes | true | Can disable without deleting |
| lastSyncedAt | Date | No | nil | Last successful sync |

**Note**: Authentication token stored in macOS Keychain, not in
SwiftData. Keyed by `type + serverURL`.

## Enums

```text
Priority: high, medium, low
BookingStatus: unreviewed, reviewed, exported
EntrySource: manual, timer, autoDetected
IntegrationType: jira, bitbucket
```

## Indexes

- `Todo.deletedAt` — fast soft-delete filtering
- `Todo.isCompleted` — filter active vs completed
- `Todo.createdAt` — default sort order
- `TimeEntry.startTime` — chronological ordering
- `TimeEntry.isInProgress` — find active timer quickly
- `JiraLink.ticketID` — match detected window titles
- `BitbucketLink.prNumber + repositorySlug` — match detected window titles
