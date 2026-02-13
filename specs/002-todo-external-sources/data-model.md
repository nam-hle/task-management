# Data Model: Todo List with External Source Connections

**Feature Branch**: `002-todo-external-sources`
**Date**: 2026-02-13

## Entity Relationship Overview

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Project    │1───*│     Todo     │*───*│     Tag      │
│              │     │              │     │              │
│ id           │     │ id           │     │ id           │
│ name         │     │ title        │     │ name         │
│ description  │     │ description  │     │ color        │
│ color        │     │ status       │     └──────────────┘
│ icon         │     │ priority     │           │
│ archived     │     │ due_date     │      (todo_tags)
│ sort_order   │     │ sort_order   │
└──────────────┘     │ project_id   │     ┌──────────────┐
                     │ created_at   │     │ChecklistItem │
                     │ completed_at │1───*│              │
                     │ updated_at   │     │ id           │
                     └──────┬───────┘     │ todo_id      │
                            │             │ text         │
                           1│             │ checked      │
                            │             │ sort_order   │
                     ┌──────┴───────┐     └──────────────┘
                     │    Link      │
                     │              │
                     │ id           │
                     │ todo_id ─────┤
                     │ task_id ─────┼──── Task (existing)
                     │ link_type    │
                     └──────────────┘
```

## Entities

### Todo (NEW)

Local task item created and managed by the user.

| Field         | Type     | Constraints                          | Description                           |
|---------------|----------|--------------------------------------|---------------------------------------|
| id            | TEXT     | PK, UUID                            | Unique identifier                     |
| title         | TEXT     | NOT NULL, min 1 char                | Todo title                            |
| description   | TEXT     | DEFAULT ''                          | Optional longer description           |
| status        | TEXT     | DEFAULT 'open', CHECK(open/complete)| Current state                         |
| priority      | INTEGER  | DEFAULT 3, CHECK(1-5)              | 1=highest, 5=lowest                   |
| due_date      | DATETIME | NULLABLE                            | Optional deadline                     |
| sort_order    | INTEGER  | DEFAULT 0                           | Custom ordering position              |
| project_id    | TEXT     | FK→projects(id) ON DELETE SET NULL  | Optional project assignment           |
| created_at    | DATETIME | DEFAULT CURRENT_TIMESTAMP           | Creation timestamp                    |
| completed_at  | DATETIME | NULLABLE                            | When status changed to complete       |
| updated_at    | DATETIME | DEFAULT CURRENT_TIMESTAMP           | Last modification timestamp           |

**Indexes**: status, priority, due_date, project_id, sort_order, updated_at

**Validation Rules**:
- Title must be non-empty (trimmed length >= 1)
- Priority must be 1-5
- Status must be 'open' or 'complete'
- completed_at is set automatically when status changes to 'complete', cleared when reverted to 'open'
- updated_at is set automatically on every modification
- sort_order defaults to max(sort_order) + 1 for new items

**State Transitions**:

```text
┌───────┐   mark complete   ┌──────────┐
│ open  │ ───────────────► │ complete  │
│       │ ◄─────────────── │           │
└───────┘   reopen          └──────────┘
    │                            │
    ▼                            ▼
 [delete]                    [delete]
```

---

### ChecklistItem (NEW)

Simple sub-entry within a todo. Not an independent entity — lifecycle is bound to parent todo.

| Field      | Type     | Constraints                             | Description                    |
|------------|----------|-----------------------------------------|--------------------------------|
| id         | TEXT     | PK, UUID                               | Unique identifier              |
| todo_id    | TEXT     | FK→todos(id) ON DELETE CASCADE, NOT NULL| Parent todo                    |
| text       | TEXT     | NOT NULL, min 1 char                   | Checklist item text            |
| checked    | INTEGER  | DEFAULT 0, CHECK(0/1)                  | 0=unchecked, 1=checked         |
| sort_order | INTEGER  | DEFAULT 0                              | Display order within the todo  |
| created_at | DATETIME | DEFAULT CURRENT_TIMESTAMP              | Creation timestamp             |

**Indexes**: todo_id, todo_id+sort_order

**Validation Rules**:
- Text must be non-empty (trimmed length >= 1)
- checked must be 0 or 1
- Deleting the parent todo cascades to all checklist items

---

### Project (NEW)

Grouping container for related todos.

| Field       | Type     | Constraints                | Description                        |
|-------------|----------|----------------------------|------------------------------------|
| id          | TEXT     | PK, UUID                  | Unique identifier                  |
| name        | TEXT     | NOT NULL, UNIQUE, min 1    | Project name                       |
| description | TEXT     | DEFAULT ''                | Optional description               |
| color       | TEXT     | DEFAULT ''                | Display color (hex or named)       |
| icon        | TEXT     | DEFAULT ''                | Optional icon/emoji                |
| archived    | INTEGER  | DEFAULT 0, CHECK(0/1)    | 0=active, 1=archived              |
| sort_order  | INTEGER  | DEFAULT 0                 | Display order in project list      |
| created_at  | DATETIME | DEFAULT CURRENT_TIMESTAMP | Creation timestamp                 |
| updated_at  | DATETIME | DEFAULT CURRENT_TIMESTAMP | Last modification timestamp        |

**Indexes**: name, archived, sort_order

**Validation Rules**:
- Name must be non-empty and unique (case-insensitive)
- Archiving a project does NOT affect its todos (they remain visible in "All" view)
- Deleting a project sets project_id to NULL on all associated todos (moves them to Inbox)

**State Transitions**:

```text
┌────────┐   archive   ┌──────────┐
│ active │ ──────────► │ archived │
│        │ ◄────────── │          │
└────────┘   restore   └──────────┘
    │
    ▼
 [delete] → todos.project_id SET NULL
```

---

### Tag (NEW)

Cross-cutting label for categorization.

| Field      | Type     | Constraints                | Description                 |
|------------|----------|----------------------------|-----------------------------|
| id         | TEXT     | PK, UUID                  | Unique identifier           |
| name       | TEXT     | NOT NULL, UNIQUE, min 1    | Tag name                    |
| color      | TEXT     | DEFAULT ''                | Display color               |
| created_at | DATETIME | DEFAULT CURRENT_TIMESTAMP | Creation timestamp          |

**Indexes**: name

**Validation Rules**:
- Name must be non-empty and unique (case-insensitive)
- Deleting a tag removes it from all todo_tags associations (CASCADE on junction)

---

### TodoTag (Junction Table — NEW)

Many-to-many relationship between todos and tags.

| Field   | Type | Constraints                                    | Description |
|---------|------|------------------------------------------------|-------------|
| todo_id | TEXT | FK→todos(id) ON DELETE CASCADE, NOT NULL       | Todo ref    |
| tag_id  | TEXT | FK→tags(id) ON DELETE CASCADE, NOT NULL        | Tag ref     |

**Primary Key**: (todo_id, tag_id)

---

### Link (NEW)

Association between a local todo and an external task.

| Field      | Type     | Constraints                             | Description                        |
|------------|----------|-----------------------------------------|------------------------------------|
| id         | TEXT     | PK, UUID                               | Unique identifier                  |
| todo_id    | TEXT     | FK→todos(id) ON DELETE CASCADE, NOT NULL| Local todo reference               |
| task_id    | TEXT     | NOT NULL                               | External task ID (from tasks table)|
| link_type  | TEXT     | DEFAULT 'manual', CHECK(manual/auto)   | How the link was created           |
| created_at | DATETIME | DEFAULT CURRENT_TIMESTAMP              | Creation timestamp                 |

**Unique Constraint**: (todo_id, task_id)

**Validation Rules**:
- A todo can link to multiple external tasks
- An external task can be linked from multiple todos
- Deleting the todo cascades link removal
- If the external task is removed from sync, the link remains but the task detail shows "removed from source"

---

### Existing Entities (Unchanged)

These entities from Feature 001 remain as-is:

- **Task**: External items from Jira/Bitbucket/Email (id, source_type, source_item_id, title, status, priority, etc.)
- **SourceConfig**: External source connections (id, type, name, base_url, config, poll_interval_sec)
- **Notification**: Alerts for new/updated items (id, task_id, message, read)

---

## ListItem Interface (Virtual)

Not a database entity — a Go interface for the unified list view.

```text
ListItem
├── GetID()         → string
├── GetTitle()      → string
├── GetDescription()→ string
├── GetStatus()     → string     // "open", "complete", "in_progress", "review", "done"
├── GetPriority()   → int        // 1-5
├── GetSource()     → string     // "local", "jira", "bitbucket", "email"
├── GetUpdatedAt()  → time.Time
├── GetDueDate()    → *time.Time // nil if no due date (always nil for external tasks)
├── IsOverdue()     → bool       // due_date < now && status != complete
└── GetSortKey()    → int64      // for custom ordering
```

Both `model.Todo` and `model.Task` implement this interface, enabling the unified list view to operate on `[]ListItem` regardless of item origin.

---

## Migration: v3

```sql
-- New tables for Feature 002 (additive, no changes to v1/v2 tables)

CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT DEFAULT '',
    color TEXT DEFAULT '',
    icon TEXT DEFAULT '',
    archived INTEGER DEFAULT 0 CHECK(archived IN (0, 1)),
    sort_order INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS todos (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    status TEXT DEFAULT 'open' CHECK(status IN ('open', 'complete')),
    priority INTEGER DEFAULT 3 CHECK(priority BETWEEN 1 AND 5),
    due_date DATETIME,
    sort_order INTEGER DEFAULT 0,
    project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_todos_status ON todos(status);
CREATE INDEX IF NOT EXISTS idx_todos_priority ON todos(priority);
CREATE INDEX IF NOT EXISTS idx_todos_due_date ON todos(due_date);
CREATE INDEX IF NOT EXISTS idx_todos_project_id ON todos(project_id);
CREATE INDEX IF NOT EXISTS idx_todos_sort_order ON todos(sort_order);
CREATE INDEX IF NOT EXISTS idx_todos_updated_at ON todos(updated_at);

CREATE TABLE IF NOT EXISTS tags (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    color TEXT DEFAULT '',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS todo_tags (
    todo_id TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (todo_id, tag_id)
);

CREATE TABLE IF NOT EXISTS checklist_items (
    id TEXT PRIMARY KEY,
    todo_id TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    checked INTEGER DEFAULT 0 CHECK(checked IN (0, 1)),
    sort_order INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_checklist_items_todo_id ON checklist_items(todo_id);

CREATE TABLE IF NOT EXISTS links (
    id TEXT PRIMARY KEY,
    todo_id TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
    task_id TEXT NOT NULL,
    link_type TEXT DEFAULT 'manual' CHECK(link_type IN ('manual', 'auto')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(todo_id, task_id)
);

CREATE INDEX IF NOT EXISTS idx_links_todo_id ON links(todo_id);
CREATE INDEX IF NOT EXISTS idx_links_task_id ON links(task_id);
```
