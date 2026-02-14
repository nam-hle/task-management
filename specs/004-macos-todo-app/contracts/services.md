# Service Contracts: Native macOS Todo App

**Feature**: `004-macos-todo-app`
**Date**: 2026-02-14

This is a native macOS app — no REST API endpoints. Instead, contracts
define the internal service layer that views interact with.

## TodoService

Manages todo CRUD operations.

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| create | title, priority?, project?, tags?, dueDate? | Todo | Default priority: medium |
| update | Todo, fields to update | Todo | Sets updatedAt |
| complete | Todo | Todo | Sets isCompleted, completedAt |
| reopen | Todo | Todo | Clears isCompleted, completedAt |
| softDelete | Todo | Todo | Sets deletedAt |
| restore | Todo | Todo | Clears deletedAt |
| purgeExpired | — | Int (count purged) | Delete where deletedAt < 30 days ago |
| list | filters (project?, tag?, priority?, isCompleted?, search?) | [Todo] | Excludes soft-deleted by default |
| listTrashed | — | [Todo] | Only deletedAt != nil |
| reorder | Todo, newSortOrder | Todo | Update sortOrder |

## ProjectService

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| create | name, color?, description? | Project | Name must be unique |
| update | Project, fields | Project | |
| delete | Project | — | Nullifies project on associated todos |
| list | — | [Project] | Ordered by sortOrder |

## TagService

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| create | name, color? | Tag | Name must be unique |
| update | Tag, fields | Tag | |
| delete | Tag | — | Removes tag from associated todos |
| list | — | [Tag] | Ordered by name |

## JiraService

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| configure | serverURL, username, token | IntegrationConfig | Token stored in Keychain |
| linkToTodo | Todo, ticketID | JiraLink | Fetches and caches ticket data |
| unlinkFromTodo | Todo | — | Removes JiraLink |
| fetchTicket | ticketID, config | JiraTicketDTO | REST API call |
| searchTickets | query (JQL), config | [JiraTicketDTO] | REST API call |
| syncAll | — | SyncResult | Updates all linked tickets |
| importAsTodo | ticketID, project? | Todo | Creates todo + JiraLink |

**JiraTicketDTO**: `{ ticketID, summary, status, assignee }`
**SyncResult**: `{ updated: Int, failed: Int, errors: [String] }`

### Jira REST Endpoints Used

| Action | Cloud (v3) | Server/DC (v2) |
|--------|-----------|-----------------|
| Get ticket | `GET /rest/api/3/issue/{key}?fields=summary,status,assignee` | `GET /rest/api/2/issue/{key}?fields=summary,status,assignee` |
| Search | `GET /rest/api/3/search?jql={query}&fields=summary,status,assignee` | `GET /rest/api/2/search?jql={query}&fields=summary,status,assignee` |

**Auth**: Cloud = Basic (email:apiToken), Server = Bearer PAT

## BitbucketService

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| configure | serverURL, username, token | IntegrationConfig | Token stored in Keychain |
| linkToTodo | Todo, repoSlug, prNumber | BitbucketLink | Fetches and caches PR data |
| unlinkFromTodo | Todo | — | Removes BitbucketLink |
| fetchPR | repoSlug, prNumber, config | BitbucketPRDTO | REST API call |
| searchPRs | repoSlug, state?, config | [BitbucketPRDTO] | REST API call |
| syncAll | — | SyncResult | Updates all linked PRs |

**BitbucketPRDTO**: `{ prNumber, title, status, author, reviewers }`

### Bitbucket REST Endpoints Used

| Action | Cloud (v2.0) | Server/DC (v1.0) |
|--------|-------------|-------------------|
| Get PR | `GET /2.0/repositories/{workspace}/{repo}/pullrequests/{id}` | `GET /rest/api/1.0/projects/{project}/repos/{repo}/pull-requests/{id}` |
| List PRs | `GET /2.0/repositories/{workspace}/{repo}/pullrequests?state={state}` | `GET /rest/api/1.0/projects/{project}/repos/{repo}/pull-requests?state={state}` |

**Auth**: Cloud = Basic (username:apiToken), Server = Bearer PAT

## TimerService

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| start | Todo | TimeEntry | Pauses any running timer first |
| pause | — | TimeEntry | Sets endTime on active entry |
| stop | — | TimeEntry | Finalizes active entry |
| getActive | — | TimeEntry? | The currently running entry |
| autoSave | — | — | Called every 60s, persists in-progress state |
| recoverOnLaunch | — | TimeEntry? | Recovers crashed in-progress entry |

**Constraints**:
- Only one TimeEntry with `isInProgress = true` at any time
- Starting a new timer auto-pauses the running one
- Midnight crossing splits the entry

## TimeEntryService

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| create | todo, startTime, endTime, notes?, source | TimeEntry | Manual entry creation |
| update | TimeEntry, fields | TimeEntry | Edit duration, notes |
| delete | TimeEntry | — | Hard delete |
| listForDate | Date | [TimeEntry] | Grouped by todo |
| markReviewed | [TimeEntry] | — | Batch status update |
| markExported | [TimeEntry] | — | Batch status update |
| dailySummary | Date | DailySummary | Per-todo totals + daily total |

**DailySummary**: `{ date, entries: [{ todo, totalDuration, entries }], dailyTotal }`

## WindowDetectionService (P5)

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| start | — | — | Begin monitoring active window |
| stop | — | — | Stop monitoring |
| isEnabled | — | Bool | User preference |
| setEnabled | Bool | — | Toggle in settings |

**Events emitted**:
- `detectedJiraTicket(ticketID, matchedTodo?)` — when Jira ticket found
  in browser title for 30+ seconds
- `detectedBitbucketPR(repoSlug, prNumber, matchedTodo?)` — when PR
  found in browser title for 30+ seconds
- `idleDetected(duration)` — when idle > threshold

**Dependencies**:
- NSWorkspace notifications (app activation)
- Accessibility API (window titles)
- ScriptingBridge (browser tab titles for Safari/Chrome)
- IOKit HIDIdleTime (idle detection)

## KeychainService

| Operation | Input | Output | Notes |
|-----------|-------|--------|-------|
| saveToken | service, account, token | Bool | Overwrites existing |
| getToken | service, account | String? | nil if not found |
| deleteToken | service, account | Bool | |

**Service identifiers**: `com.taskmanagement.jira`, `com.taskmanagement.bitbucket`
