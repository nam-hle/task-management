package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	_ "modernc.org/sqlite"

	"github.com/nhle/task-management/internal/model"
)

// SQLiteStore implements the Store interface using a local SQLite database.
type SQLiteStore struct {
	db *sqlx.DB
}

// NewSQLiteStore opens (or creates) a SQLite database at dbPath,
// enables WAL mode, and runs any pending schema migrations.
func NewSQLiteStore(dbPath string) (*SQLiteStore, error) {
	db, err := sqlx.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("opening sqlite db: %w", err)
	}

	// Enable WAL mode for better concurrent read performance.
	if _, err := db.Exec("PRAGMA journal_mode=WAL"); err != nil {
		db.Close()
		return nil, fmt.Errorf("enabling WAL mode: %w", err)
	}

	// Enable foreign keys.
	if _, err := db.Exec("PRAGMA foreign_keys=ON"); err != nil {
		db.Close()
		return nil, fmt.Errorf("enabling foreign keys: %w", err)
	}

	s := &SQLiteStore{db: db}
	if err := s.runMigrations(); err != nil {
		db.Close()
		return nil, fmt.Errorf("running migrations: %w", err)
	}

	return s, nil
}

// Close closes the underlying database connection.
func (s *SQLiteStore) Close() error {
	return s.db.Close()
}

// runMigrations checks the current schema version and applies any
// outstanding migrations in order.
func (s *SQLiteStore) runMigrations() error {
	currentVersion := 0

	// Check if schema_version table exists.
	var tableCount int
	err := s.db.Get(
		&tableCount,
		"SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_version'",
	)
	if err != nil {
		return fmt.Errorf("checking schema_version table: %w", err)
	}

	if tableCount > 0 {
		err = s.db.Get(&currentVersion, "SELECT COALESCE(MAX(version), 0) FROM schema_version")
		if err != nil {
			return fmt.Errorf("reading schema version: %w", err)
		}
	}

	for _, m := range migrations {
		if m.version <= currentVersion {
			continue
		}
		if _, err := s.db.Exec(m.sql); err != nil {
			return fmt.Errorf("applying migration v%d: %w", m.version, err)
		}
	}

	return nil
}

// UpsertTasks inserts or replaces a batch of tasks.
func (s *SQLiteStore) UpsertTasks(ctx context.Context, tasks []model.Task) error {
	if len(tasks) == 0 {
		return nil
	}

	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return fmt.Errorf("beginning transaction: %w", err)
	}
	defer tx.Rollback()

	const query = `
		INSERT OR REPLACE INTO tasks (
			id, source_type, source_item_id, source_id,
			title, description, status, priority,
			assignee, author, source_url,
			created_at, updated_at, fetched_at,
			raw_data, cross_refs
		) VALUES (
			?, ?, ?, ?,
			?, ?, ?, ?,
			?, ?, ?,
			?, ?, ?,
			?, ?
		)`

	stmt, err := tx.PreparexContext(ctx, query)
	if err != nil {
		return fmt.Errorf("preparing upsert statement: %w", err)
	}
	defer stmt.Close()

	for _, t := range tasks {
		crossRefs, err := json.Marshal(t.CrossRefs)
		if err != nil {
			return fmt.Errorf("marshaling cross_refs for task %s: %w", t.ID, err)
		}

		_, err = stmt.ExecContext(ctx,
			t.ID, string(t.SourceType), t.SourceItemID, t.SourceID,
			t.Title, t.Description, t.Status, t.Priority,
			t.Assignee, t.Author, t.SourceURL,
			t.CreatedAt.UTC(), t.UpdatedAt.UTC(), t.FetchedAt.UTC(),
			t.RawData, string(crossRefs),
		)
		if err != nil {
			return fmt.Errorf("upserting task %s: %w", t.ID, err)
		}
	}

	return tx.Commit()
}

// GetTasks retrieves tasks matching the provided filter options.
func (s *SQLiteStore) GetTasks(
	ctx context.Context,
	opts TaskFilter,
) ([]model.Task, error) {
	var conditions []string
	var args []interface{}

	if opts.SourceType != nil {
		conditions = append(conditions, "source_type = ?")
		args = append(args, *opts.SourceType)
	}
	if opts.Status != nil {
		conditions = append(conditions, "status = ?")
		args = append(args, *opts.Status)
	}
	if opts.Priority != nil {
		conditions = append(conditions, "priority = ?")
		args = append(args, *opts.Priority)
	}
	if opts.Query != nil && *opts.Query != "" {
		conditions = append(conditions, "(title LIKE ? OR description LIKE ?)")
		q := "%" + *opts.Query + "%"
		args = append(args, q, q)
	}

	query := "SELECT * FROM tasks"
	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}

	// Determine sort column.
	sortBy := "updated_at"
	if opts.SortBy != "" {
		allowedSorts := map[string]bool{
			"title":      true,
			"status":     true,
			"priority":   true,
			"created_at": true,
			"updated_at": true,
		}
		if allowedSorts[opts.SortBy] {
			sortBy = opts.SortBy
		}
	}

	direction := "ASC"
	if opts.SortDesc {
		direction = "DESC"
	}
	query += fmt.Sprintf(" ORDER BY %s %s", sortBy, direction)

	if opts.Limit > 0 {
		query += fmt.Sprintf(" LIMIT %d", opts.Limit)
	}
	if opts.Offset > 0 {
		query += fmt.Sprintf(" OFFSET %d", opts.Offset)
	}

	rows, err := s.db.QueryxContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("querying tasks: %w", err)
	}
	defer rows.Close()

	var tasks []model.Task
	for rows.Next() {
		task, err := scanTask(rows)
		if err != nil {
			return nil, err
		}
		tasks = append(tasks, task)
	}

	return tasks, rows.Err()
}

// GetTaskByID retrieves a single task by its ID.
func (s *SQLiteStore) GetTaskByID(
	ctx context.Context,
	id string,
) (*model.Task, error) {
	row := s.db.QueryRowxContext(ctx, "SELECT * FROM tasks WHERE id = ?", id)

	task, err := scanTaskRow(row)
	if err != nil {
		return nil, fmt.Errorf("getting task %s: %w", id, err)
	}

	return &task, nil
}

// UpsertSource inserts or replaces a source configuration.
// If the source has no ID, a new UUID is generated.
func (s *SQLiteStore) UpsertSource(
	ctx context.Context,
	src model.SourceConfig,
) error {
	if src.ID == "" {
		src.ID = uuid.New().String()
	}

	configJSON, err := json.Marshal(src.Config)
	if err != nil {
		return fmt.Errorf("marshaling source config: %w", err)
	}

	_, err = s.db.ExecContext(ctx, `
		INSERT OR REPLACE INTO sources (
			id, type, name, base_url, enabled, poll_interval_sec, config, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		src.ID, src.Type, src.Name, src.BaseURL,
		boolToInt(src.Enabled), src.PollIntervalSec,
		string(configJSON), time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("upserting source %s: %w", src.ID, err)
	}

	return nil
}

// GetSources retrieves all configured source entries.
func (s *SQLiteStore) GetSources(
	ctx context.Context,
) ([]model.SourceConfig, error) {
	rows, err := s.db.QueryxContext(ctx, "SELECT * FROM sources ORDER BY name")
	if err != nil {
		return nil, fmt.Errorf("querying sources: %w", err)
	}
	defer rows.Close()

	var sources []model.SourceConfig
	for rows.Next() {
		src, err := scanSource(rows)
		if err != nil {
			return nil, err
		}
		sources = append(sources, src)
	}

	return sources, rows.Err()
}

// DeleteSource removes a source by ID.
func (s *SQLiteStore) DeleteSource(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM sources WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("deleting source %s: %w", id, err)
	}
	return nil
}

// CreateNotification inserts a new notification record.
func (s *SQLiteStore) CreateNotification(
	ctx context.Context,
	n model.Notification,
) error {
	if n.ID == "" {
		n.ID = uuid.New().String()
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO notifications (id, task_id, source_type, message, read, created_at)
		VALUES (?, ?, ?, ?, ?, ?)`,
		n.ID, n.TaskID, string(n.SourceType), n.Message,
		boolToInt(n.Read), n.CreatedAt.UTC(),
	)
	if err != nil {
		return fmt.Errorf("creating notification: %w", err)
	}

	return nil
}

// GetUnreadNotifications retrieves all notifications that have not been read,
// ordered by creation time descending.
func (s *SQLiteStore) GetUnreadNotifications(
	ctx context.Context,
) ([]model.Notification, error) {
	rows, err := s.db.QueryxContext(ctx,
		"SELECT * FROM notifications WHERE read = 0 ORDER BY created_at DESC",
	)
	if err != nil {
		return nil, fmt.Errorf("querying unread notifications: %w", err)
	}
	defer rows.Close()

	var notifications []model.Notification
	for rows.Next() {
		n, err := scanNotification(rows)
		if err != nil {
			return nil, err
		}
		notifications = append(notifications, n)
	}

	return notifications, rows.Err()
}

// MarkNotificationRead marks a single notification as read.
func (s *SQLiteStore) MarkNotificationRead(
	ctx context.Context,
	id string,
) error {
	_, err := s.db.ExecContext(ctx,
		"UPDATE notifications SET read = 1 WHERE id = ?", id,
	)
	if err != nil {
		return fmt.Errorf("marking notification %s as read: %w", id, err)
	}
	return nil
}

// scanTask scans a task row from a sqlx.Rows result set.
func scanTask(rows *sqlx.Rows) (model.Task, error) {
	var (
		task       model.Task
		sourceType string
		crossRefs  string
		createdAt  time.Time
		updatedAt  time.Time
		fetchedAt  time.Time
	)

	err := rows.Scan(
		&task.ID, &sourceType, &task.SourceItemID, &task.SourceID,
		&task.Title, &task.Description, &task.Status, &task.Priority,
		&task.Assignee, &task.Author, &task.SourceURL,
		&createdAt, &updatedAt, &fetchedAt,
		&task.RawData, &crossRefs,
	)
	if err != nil {
		return model.Task{}, fmt.Errorf("scanning task row: %w", err)
	}

	task.SourceType = model.SourceType(sourceType)
	task.CreatedAt = createdAt
	task.UpdatedAt = updatedAt
	task.FetchedAt = fetchedAt

	if crossRefs != "" {
		if err := json.Unmarshal([]byte(crossRefs), &task.CrossRefs); err != nil {
			return model.Task{}, fmt.Errorf("unmarshaling cross_refs: %w", err)
		}
	}

	return task, nil
}

// scanTaskRow scans a single task row from a sqlx.Row.
func scanTaskRow(row *sqlx.Row) (model.Task, error) {
	var (
		task       model.Task
		sourceType string
		crossRefs  string
		createdAt  time.Time
		updatedAt  time.Time
		fetchedAt  time.Time
	)

	err := row.Scan(
		&task.ID, &sourceType, &task.SourceItemID, &task.SourceID,
		&task.Title, &task.Description, &task.Status, &task.Priority,
		&task.Assignee, &task.Author, &task.SourceURL,
		&createdAt, &updatedAt, &fetchedAt,
		&task.RawData, &crossRefs,
	)
	if err != nil {
		return model.Task{}, fmt.Errorf("scanning task row: %w", err)
	}

	task.SourceType = model.SourceType(sourceType)
	task.CreatedAt = createdAt
	task.UpdatedAt = updatedAt
	task.FetchedAt = fetchedAt

	if crossRefs != "" {
		if err := json.Unmarshal([]byte(crossRefs), &task.CrossRefs); err != nil {
			return model.Task{}, fmt.Errorf("unmarshaling cross_refs: %w", err)
		}
	}

	return task, nil
}

// scanSource scans a source row from a sqlx.Rows result set.
func scanSource(rows *sqlx.Rows) (model.SourceConfig, error) {
	var (
		src        model.SourceConfig
		enabled    int
		configJSON string
		createdAt  time.Time
		updatedAt  time.Time
	)

	err := rows.Scan(
		&src.ID, &src.Type, &src.Name, &src.BaseURL,
		&enabled, &src.PollIntervalSec, &configJSON,
		&createdAt, &updatedAt,
	)
	if err != nil {
		return model.SourceConfig{}, fmt.Errorf("scanning source row: %w", err)
	}

	src.Enabled = enabled != 0

	if configJSON != "" {
		if err := json.Unmarshal([]byte(configJSON), &src.Config); err != nil {
			return model.SourceConfig{}, fmt.Errorf("unmarshaling source config: %w", err)
		}
	}

	return src, nil
}

// scanNotification scans a notification row from a sqlx.Rows result set.
func scanNotification(rows *sqlx.Rows) (model.Notification, error) {
	var (
		n          model.Notification
		sourceType string
		readInt    int
		createdAt  time.Time
	)

	err := rows.Scan(
		&n.ID, &n.TaskID, &sourceType, &n.Message,
		&readInt, &createdAt,
	)
	if err != nil {
		return model.Notification{}, fmt.Errorf("scanning notification row: %w", err)
	}

	n.SourceType = model.SourceType(sourceType)
	n.Read = readInt != 0
	n.CreatedAt = createdAt

	return n, nil
}

// boolToInt converts a boolean to 0 or 1 for SQLite storage.
func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
