# Data Model: Terminal Task Manager

**Feature**: 001-terminal-task-manager
**Date**: 2026-02-13

## Entities

### Task (unified)

The normalized representation of any work item from any source.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | Composite key: `{source_type}:{source_item_id}` |
| `source_type` | `enum` | `jira`, `bitbucket`, `email` |
| `source_item_id` | `string` | Original ID in source system |
| `source_id` | `string` | Reference to configured Source |
| `title` | `string` | Display title (issue summary, PR title, email subject) |
| `description` | `string` | Body text (rendered as plain text / markdown) |
| `status` | `string` | Normalized status (Open, In Progress, Review, Done, etc.) |
| `priority` | `int` | Normalized priority (1=Critical, 2=High, 3=Medium, 4=Low, 5=Lowest) |
| `assignee` | `string` | Display name of assignee |
| `author` | `string` | Display name of creator |
| `source_url` | `string` | URL to view in browser |
| `created_at` | `datetime` | Creation timestamp |
| `updated_at` | `datetime` | Last update timestamp |
| `fetched_at` | `datetime` | When this item was last synced |
| `raw_data` | `json` | Full source-specific data (preserved for detail view) |
| `cross_refs` | `[]string` | Related item IDs from other sources |

**Status normalization mapping**:

| Source | Source Status | Normalized Status |
|--------|-------------|-------------------|
| Jira | To Do | Open |
| Jira | In Progress | In Progress |
| Jira | In Review | Review |
| Jira | Done / Closed | Done |
| Bitbucket | OPEN | Open |
| Bitbucket | MERGED | Done |
| Bitbucket | DECLINED | Done |
| Email | Unread | Open |
| Email | Read | In Progress |
| Email | Archived | Done |
| Email | Flagged | High Priority (priority override) |

**Priority normalization mapping**:

| Source | Source Priority | Normalized (1-5) |
|--------|---------------|-------------------|
| Jira | Blocker / Critical | 1 |
| Jira | High | 2 |
| Jira | Medium | 3 |
| Jira | Low | 4 |
| Jira | Lowest | 5 |
| Bitbucket | Changes Requested | 2 |
| Bitbucket | Needs Review | 3 |
| Bitbucket | Approved | 4 |
| Email | Flagged + Unread | 2 |
| Email | Unread | 3 |
| Email | Read | 5 |

### Source

A configured external service connection.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | UUID |
| `type` | `enum` | `jira`, `bitbucket`, `email` |
| `name` | `string` | User-defined label (e.g., "Work Jira") |
| `base_url` | `string` | Service URL (Jira/BB base, IMAP host) |
| `enabled` | `bool` | Whether to include in polling |
| `poll_interval_sec` | `int` | Polling interval override (default: 120) |
| `last_sync_at` | `datetime` | Last successful sync |
| `last_error` | `string` | Last sync error message (null if healthy) |
| `config` | `json` | Source-specific configuration |

**Source-specific config shapes**:

```
Jira: { personal_access_token: "cred:jira-token", default_jql: "assignee=currentUser()" }
Bitbucket: { personal_access_token: "cred:bb-token" }
Email: { imap_host, imap_port, smtp_host, smtp_port, username, password: "cred:email-pass", tls }
```

Note: Credential values prefixed with `cred:` are keyring references, not stored in SQLite.

### Notification

An alert for new or changed items.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | UUID |
| `task_id` | `string` | Reference to Task |
| `source_type` | `enum` | Source type for quick filtering |
| `message` | `string` | Human-readable notification text |
| `read` | `bool` | Whether user has seen this |
| `created_at` | `datetime` | When the notification was generated |

### AI Conversation (in-memory only)

Session-scoped, not persisted to SQLite.

| Field | Type | Description |
|-------|------|-------------|
| `messages` | `[]Message` | Sequence of user queries and AI responses |
| `started_at` | `datetime` | Session start time |

**Message**:

| Field | Type | Description |
|-------|------|-------------|
| `role` | `enum` | `user`, `assistant` |
| `content` | `string` | Message text |
| `task_refs` | `[]string` | Task IDs referenced in this message |
| `timestamp` | `datetime` | When sent |

## SQLite Schema

```sql
CREATE TABLE sources (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK(type IN ('jira', 'bitbucket', 'email')),
    name TEXT NOT NULL,
    base_url TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    poll_interval_sec INTEGER NOT NULL DEFAULT 120,
    last_sync_at TEXT,
    last_error TEXT,
    config TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    source_type TEXT NOT NULL,
    source_item_id TEXT NOT NULL,
    source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'Open',
    priority INTEGER NOT NULL DEFAULT 3,
    assignee TEXT DEFAULT '',
    author TEXT DEFAULT '',
    source_url TEXT DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    fetched_at TEXT NOT NULL,
    raw_data TEXT DEFAULT '{}',
    cross_refs TEXT DEFAULT '[]',
    UNIQUE(source_id, source_item_id)
);

CREATE INDEX idx_tasks_source_id ON tasks(source_id);
CREATE INDEX idx_tasks_source_type ON tasks(source_type);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_priority ON tasks(priority);
CREATE INDEX idx_tasks_updated_at ON tasks(updated_at);

CREATE TABLE notifications (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    source_type TEXT NOT NULL,
    message TEXT NOT NULL,
    read INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_notifications_read ON notifications(read);
CREATE INDEX idx_notifications_created ON notifications(created_at);

CREATE TABLE schema_version (
    version INTEGER PRIMARY KEY
);
```

## Relationships

```
Source 1---* Task        (one source has many tasks)
Task   1---* Notification (one task can have many notifications)
Task   *---* Task        (cross-references via cross_refs JSON array)
```

## State Transitions

### Task Status Lifecycle

```
Open -> In Progress -> Review -> Done
  ^         |            |
  |         v            v
  +-------- Open <-------+  (re-opened / changes requested)
```

### Source Sync States

```
Idle -> Syncing -> Success -> Idle (normal cycle)
                -> Error -> Idle (retry on next poll)
```
