package store

// migration holds a single schema migration with its target version and SQL.
type migration struct {
	version int
	sql     string
}

// migrations is the ordered list of schema migrations.
// Each migration's version must be sequential starting from 1.
var migrations = []migration{
	{
		version: 1,
		sql: `
CREATE TABLE IF NOT EXISTS schema_version (
	version INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sources (
	id          TEXT PRIMARY KEY,
	type        TEXT NOT NULL,
	name        TEXT NOT NULL,
	base_url    TEXT NOT NULL DEFAULT '',
	enabled     INTEGER NOT NULL DEFAULT 1,
	poll_interval_sec INTEGER NOT NULL DEFAULT 120,
	config      TEXT NOT NULL DEFAULT '{}',
	created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tasks (
	id             TEXT PRIMARY KEY,
	source_type    TEXT NOT NULL,
	source_item_id TEXT NOT NULL,
	source_id      TEXT NOT NULL,
	title          TEXT NOT NULL,
	description    TEXT NOT NULL DEFAULT '',
	status         TEXT NOT NULL DEFAULT 'open',
	priority       INTEGER NOT NULL DEFAULT 3,
	assignee       TEXT NOT NULL DEFAULT '',
	author         TEXT NOT NULL DEFAULT '',
	source_url     TEXT NOT NULL DEFAULT '',
	created_at     DATETIME NOT NULL,
	updated_at     DATETIME NOT NULL,
	fetched_at     DATETIME NOT NULL,
	raw_data       TEXT NOT NULL DEFAULT '',
	cross_refs     TEXT NOT NULL DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS notifications (
	id          TEXT PRIMARY KEY,
	task_id     TEXT NOT NULL,
	source_type TEXT NOT NULL,
	message     TEXT NOT NULL,
	read        INTEGER NOT NULL DEFAULT 0,
	created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tasks_source_id ON tasks(source_id);
CREATE INDEX IF NOT EXISTS idx_tasks_source_type ON tasks(source_type);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority);
CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON tasks(updated_at);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);

INSERT INTO schema_version (version) VALUES (1);
`,
	},
	{
		version: 2,
		sql: `
CREATE INDEX IF NOT EXISTS idx_tasks_source_type_updated
	ON tasks(source_type, updated_at);

CREATE INDEX IF NOT EXISTS idx_notifications_task_id
	ON notifications(task_id);

INSERT INTO schema_version (version) VALUES (2);
`,
	},
	{
		version: 3,
		sql: `
CREATE TABLE IF NOT EXISTS projects (
	id          TEXT PRIMARY KEY,
	name        TEXT NOT NULL UNIQUE,
	description TEXT NOT NULL DEFAULT '',
	color       TEXT NOT NULL DEFAULT '',
	icon        TEXT NOT NULL DEFAULT '',
	archived    INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0, 1)),
	sort_order  INTEGER NOT NULL DEFAULT 0,
	created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS todos (
	id           TEXT PRIMARY KEY,
	title        TEXT NOT NULL,
	description  TEXT NOT NULL DEFAULT '',
	status       TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'complete')),
	priority     INTEGER NOT NULL DEFAULT 3 CHECK(priority BETWEEN 1 AND 5),
	due_date     DATETIME,
	sort_order   INTEGER NOT NULL DEFAULT 0,
	project_id   TEXT REFERENCES projects(id) ON DELETE SET NULL,
	created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	completed_at DATETIME,
	updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_todos_status ON todos(status);
CREATE INDEX IF NOT EXISTS idx_todos_priority ON todos(priority);
CREATE INDEX IF NOT EXISTS idx_todos_due_date ON todos(due_date);
CREATE INDEX IF NOT EXISTS idx_todos_project_id ON todos(project_id);
CREATE INDEX IF NOT EXISTS idx_todos_sort_order ON todos(sort_order);
CREATE INDEX IF NOT EXISTS idx_todos_updated_at ON todos(updated_at);

CREATE TABLE IF NOT EXISTS tags (
	id         TEXT PRIMARY KEY,
	name       TEXT NOT NULL UNIQUE,
	color      TEXT NOT NULL DEFAULT '',
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS todo_tags (
	todo_id TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
	tag_id  TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
	PRIMARY KEY (todo_id, tag_id)
);

CREATE TABLE IF NOT EXISTS checklist_items (
	id         TEXT PRIMARY KEY,
	todo_id    TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
	text       TEXT NOT NULL,
	checked    INTEGER NOT NULL DEFAULT 0 CHECK(checked IN (0, 1)),
	sort_order INTEGER NOT NULL DEFAULT 0,
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_checklist_items_todo_id ON checklist_items(todo_id);

CREATE TABLE IF NOT EXISTS links (
	id         TEXT PRIMARY KEY,
	todo_id    TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
	task_id    TEXT NOT NULL,
	link_type  TEXT NOT NULL DEFAULT 'manual' CHECK(link_type IN ('manual', 'auto')),
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	UNIQUE(todo_id, task_id)
);

CREATE INDEX IF NOT EXISTS idx_links_todo_id ON links(todo_id);
CREATE INDEX IF NOT EXISTS idx_links_task_id ON links(task_id);

INSERT INTO schema_version (version) VALUES (3);
`,
	},
}
