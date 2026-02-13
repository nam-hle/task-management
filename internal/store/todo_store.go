package store

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/nhle/task-management/internal/model"
)

// CreateTodo inserts a new todo. Generates a UUID if ID is empty.
func (s *SQLiteStore) CreateTodo(ctx context.Context, todo model.Todo) error {
	if strings.TrimSpace(todo.Title) == "" {
		return fmt.Errorf("todo title must not be empty")
	}
	if todo.ID == "" {
		todo.ID = uuid.New().String()
	}
	now := time.Now().UTC()
	todo.CreatedAt = now
	todo.UpdatedAt = now
	if todo.Status == "" {
		todo.Status = model.TodoStatusOpen
	}
	if todo.Priority < 1 || todo.Priority > 5 {
		todo.Priority = model.PriorityMedium
	}

	// Default sort_order to max+1.
	if todo.SortOrder == 0 {
		var maxOrder int
		err := s.db.GetContext(ctx, &maxOrder,
			"SELECT COALESCE(MAX(sort_order), 0) FROM todos")
		if err != nil {
			return fmt.Errorf("getting max sort_order: %w", err)
		}
		todo.SortOrder = maxOrder + 1
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO todos (
			id, title, description, status, priority,
			due_date, sort_order, project_id,
			created_at, completed_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		todo.ID, todo.Title, todo.Description, todo.Status, todo.Priority,
		todo.DueDate, todo.SortOrder, todo.ProjectID,
		todo.CreatedAt, todo.CompletedAt, todo.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("creating todo: %w", err)
	}
	return nil
}

// UpdateTodo updates an existing todo by ID.
func (s *SQLiteStore) UpdateTodo(ctx context.Context, todo model.Todo) error {
	if strings.TrimSpace(todo.Title) == "" {
		return fmt.Errorf("todo title must not be empty")
	}

	now := time.Now().UTC()
	todo.UpdatedAt = now

	// Auto-manage completed_at based on status.
	if todo.Status == model.TodoStatusComplete && todo.CompletedAt == nil {
		todo.CompletedAt = &now
	} else if todo.Status == model.TodoStatusOpen {
		todo.CompletedAt = nil
	}

	result, err := s.db.ExecContext(ctx, `
		UPDATE todos SET
			title = ?, description = ?, status = ?, priority = ?,
			due_date = ?, sort_order = ?, project_id = ?,
			completed_at = ?, updated_at = ?
		WHERE id = ?`,
		todo.Title, todo.Description, todo.Status, todo.Priority,
		todo.DueDate, todo.SortOrder, todo.ProjectID,
		todo.CompletedAt, todo.UpdatedAt,
		todo.ID,
	)
	if err != nil {
		return fmt.Errorf("updating todo %s: %w", todo.ID, err)
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("todo %s not found", todo.ID)
	}
	return nil
}

// DeleteTodo removes a todo by ID. Cascades to checklist_items, todo_tags, links.
func (s *SQLiteStore) DeleteTodo(ctx context.Context, id string) error {
	result, err := s.db.ExecContext(ctx, "DELETE FROM todos WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("deleting todo %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("todo %s not found", id)
	}
	return nil
}

// GetTodoByID retrieves a single todo by ID, including its tags.
func (s *SQLiteStore) GetTodoByID(
	ctx context.Context,
	id string,
) (*model.Todo, error) {
	var todo model.Todo
	var checkedInt int
	var dueDate, completedAt *time.Time
	var projectID *string

	err := s.db.QueryRowxContext(ctx, "SELECT * FROM todos WHERE id = ?", id).Scan(
		&todo.ID, &todo.Title, &todo.Description, &todo.Status, &todo.Priority,
		&dueDate, &todo.SortOrder, &projectID,
		&todo.CreatedAt, &completedAt, &todo.UpdatedAt,
	)
	_ = checkedInt
	if err != nil {
		return nil, fmt.Errorf("getting todo %s: %w", id, err)
	}
	todo.DueDate = dueDate
	todo.CompletedAt = completedAt
	todo.ProjectID = projectID

	// Load tags.
	tags, err := s.GetTagsForTodo(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("loading tags for todo %s: %w", id, err)
	}
	todo.Tags = tags

	return &todo, nil
}

// GetTodos retrieves todos matching the filter.
func (s *SQLiteStore) GetTodos(
	ctx context.Context,
	filter TodoFilter,
) ([]model.Todo, error) {
	query, args := buildTodoQuery("SELECT todos.*", filter)

	rows, err := s.db.QueryxContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("querying todos: %w", err)
	}
	defer rows.Close()

	var todos []model.Todo
	for rows.Next() {
		todo, err := scanTodo(rows)
		if err != nil {
			return nil, err
		}
		todos = append(todos, todo)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// Batch load tags for all todos.
	for i := range todos {
		tags, err := s.GetTagsForTodo(ctx, todos[i].ID)
		if err != nil {
			return nil, fmt.Errorf("loading tags for todo %s: %w", todos[i].ID, err)
		}
		todos[i].Tags = tags
	}

	return todos, nil
}

// GetTodoCount returns the count of todos matching the filter.
func (s *SQLiteStore) GetTodoCount(
	ctx context.Context,
	filter TodoFilter,
) (int, error) {
	query, args := buildTodoQuery("SELECT COUNT(DISTINCT todos.id)", filter)

	var count int
	if err := s.db.GetContext(ctx, &count, query, args...); err != nil {
		return 0, fmt.Errorf("counting todos: %w", err)
	}
	return count, nil
}

// ReorderTodo updates the sort_order for a specific todo.
func (s *SQLiteStore) ReorderTodo(
	ctx context.Context,
	id string,
	newSortOrder int,
) error {
	result, err := s.db.ExecContext(ctx,
		"UPDATE todos SET sort_order = ?, updated_at = ? WHERE id = ?",
		newSortOrder, time.Now().UTC(), id,
	)
	if err != nil {
		return fmt.Errorf("reordering todo %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("todo %s not found", id)
	}
	return nil
}

// AddChecklistItem inserts a new checklist item for a todo.
func (s *SQLiteStore) AddChecklistItem(
	ctx context.Context,
	item model.ChecklistItem,
) error {
	if strings.TrimSpace(item.Text) == "" {
		return fmt.Errorf("checklist item text must not be empty")
	}
	if item.ID == "" {
		item.ID = uuid.New().String()
	}
	item.CreatedAt = time.Now().UTC()

	if item.SortOrder == 0 {
		var maxOrder int
		err := s.db.GetContext(ctx, &maxOrder,
			"SELECT COALESCE(MAX(sort_order), 0) FROM checklist_items WHERE todo_id = ?",
			item.TodoID)
		if err != nil {
			return fmt.Errorf("getting max checklist sort_order: %w", err)
		}
		item.SortOrder = maxOrder + 1
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO checklist_items (id, todo_id, text, checked, sort_order, created_at)
		VALUES (?, ?, ?, ?, ?, ?)`,
		item.ID, item.TodoID, item.Text, boolToInt(item.Checked),
		item.SortOrder, item.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("adding checklist item: %w", err)
	}
	return nil
}

// UpdateChecklistItem updates text and checked state of a checklist item.
func (s *SQLiteStore) UpdateChecklistItem(
	ctx context.Context,
	item model.ChecklistItem,
) error {
	if strings.TrimSpace(item.Text) == "" {
		return fmt.Errorf("checklist item text must not be empty")
	}
	result, err := s.db.ExecContext(ctx,
		"UPDATE checklist_items SET text = ?, checked = ? WHERE id = ?",
		item.Text, boolToInt(item.Checked), item.ID,
	)
	if err != nil {
		return fmt.Errorf("updating checklist item %s: %w", item.ID, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("checklist item %s not found", item.ID)
	}
	return nil
}

// DeleteChecklistItem removes a checklist item by ID.
func (s *SQLiteStore) DeleteChecklistItem(ctx context.Context, id string) error {
	result, err := s.db.ExecContext(ctx,
		"DELETE FROM checklist_items WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("deleting checklist item %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("checklist item %s not found", id)
	}
	return nil
}

// GetChecklistItems returns all checklist items for a todo, ordered by sort_order.
func (s *SQLiteStore) GetChecklistItems(
	ctx context.Context,
	todoID string,
) ([]model.ChecklistItem, error) {
	rows, err := s.db.QueryxContext(ctx,
		"SELECT * FROM checklist_items WHERE todo_id = ? ORDER BY sort_order",
		todoID)
	if err != nil {
		return nil, fmt.Errorf("querying checklist items: %w", err)
	}
	defer rows.Close()

	var items []model.ChecklistItem
	for rows.Next() {
		item, err := scanChecklistItem(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

// ToggleChecklistItem flips the checked state of a checklist item.
func (s *SQLiteStore) ToggleChecklistItem(ctx context.Context, id string) error {
	result, err := s.db.ExecContext(ctx,
		"UPDATE checklist_items SET checked = CASE WHEN checked = 0 THEN 1 ELSE 0 END WHERE id = ?",
		id)
	if err != nil {
		return fmt.Errorf("toggling checklist item %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("checklist item %s not found", id)
	}
	return nil
}

// ReorderChecklistItem updates the sort_order for a checklist item.
func (s *SQLiteStore) ReorderChecklistItem(
	ctx context.Context,
	id string,
	newSortOrder int,
) error {
	result, err := s.db.ExecContext(ctx,
		"UPDATE checklist_items SET sort_order = ? WHERE id = ?",
		newSortOrder, id)
	if err != nil {
		return fmt.Errorf("reordering checklist item %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("checklist item %s not found", id)
	}
	return nil
}

// buildTodoQuery constructs the SQL query and args for a TodoFilter.
func buildTodoQuery(selectClause string, filter TodoFilter) (string, []interface{}) {
	var conditions []string
	var args []interface{}
	needsTagJoin := len(filter.TagIDs) > 0

	from := " FROM todos"
	if needsTagJoin {
		from += " INNER JOIN todo_tags ON todos.id = todo_tags.todo_id"
	}

	if filter.Status != nil {
		conditions = append(conditions, "todos.status = ?")
		args = append(args, *filter.Status)
	}
	if filter.Priority != nil {
		conditions = append(conditions, "todos.priority = ?")
		args = append(args, *filter.Priority)
	}
	if filter.ProjectID != nil {
		if *filter.ProjectID == "inbox" {
			conditions = append(conditions, "todos.project_id IS NULL")
		} else {
			conditions = append(conditions, "todos.project_id = ?")
			args = append(args, *filter.ProjectID)
		}
	}
	if len(filter.TagIDs) > 0 {
		placeholders := make([]string, len(filter.TagIDs))
		for i, id := range filter.TagIDs {
			placeholders[i] = "?"
			args = append(args, id)
		}
		conditions = append(conditions,
			"todo_tags.tag_id IN ("+strings.Join(placeholders, ", ")+")")
	}
	if filter.Query != nil && *filter.Query != "" {
		conditions = append(conditions,
			"(todos.title LIKE ? OR todos.description LIKE ?)")
		q := "%" + *filter.Query + "%"
		args = append(args, q, q)
	}
	if filter.DueDate != nil {
		now := time.Now()
		switch *filter.DueDate {
		case "today":
			today := now.Format("2006-01-02")
			tomorrow := now.AddDate(0, 0, 1).Format("2006-01-02")
			conditions = append(conditions,
				"todos.due_date >= ? AND todos.due_date < ?")
			args = append(args, today, tomorrow)
		case "upcoming":
			today := now.Format("2006-01-02")
			weekFromNow := now.AddDate(0, 0, 7).Format("2006-01-02")
			conditions = append(conditions,
				"todos.due_date >= ? AND todos.due_date < ?")
			args = append(args, today, weekFromNow)
		case "overdue":
			today := now.Format("2006-01-02")
			conditions = append(conditions,
				"todos.due_date < ? AND todos.status != 'complete'")
			args = append(args, today)
		}
	}

	query := selectClause + from
	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}

	if needsTagJoin {
		query += " GROUP BY todos.id"
	}

	// Sort.
	sortBy := "todos.sort_order"
	if filter.SortBy != "" {
		allowed := map[string]string{
			"sort_order": "todos.sort_order",
			"priority":   "todos.priority",
			"due_date":   "todos.due_date",
			"created_at": "todos.created_at",
			"updated_at": "todos.updated_at",
			"title":      "todos.title",
		}
		if col, ok := allowed[filter.SortBy]; ok {
			sortBy = col
		}
	}
	direction := "ASC"
	if filter.SortDesc {
		direction = "DESC"
	}
	query += fmt.Sprintf(" ORDER BY %s %s", sortBy, direction)

	if filter.Limit > 0 {
		query += fmt.Sprintf(" LIMIT %d", filter.Limit)
	}
	if filter.Offset > 0 {
		query += fmt.Sprintf(" OFFSET %d", filter.Offset)
	}

	return query, args
}

// scanTodo scans a todo row from sqlx.Rows.
func scanTodo(rows interface{ Scan(dest ...interface{}) error }) (model.Todo, error) {
	var (
		todo        model.Todo
		dueDate     *time.Time
		completedAt *time.Time
		projectID   *string
	)

	err := rows.Scan(
		&todo.ID, &todo.Title, &todo.Description, &todo.Status, &todo.Priority,
		&dueDate, &todo.SortOrder, &projectID,
		&todo.CreatedAt, &completedAt, &todo.UpdatedAt,
	)
	if err != nil {
		return model.Todo{}, fmt.Errorf("scanning todo row: %w", err)
	}

	todo.DueDate = dueDate
	todo.CompletedAt = completedAt
	todo.ProjectID = projectID

	return todo, nil
}

// scanChecklistItem scans a checklist_item row from sqlx.Rows.
func scanChecklistItem(rows interface{ Scan(dest ...interface{}) error }) (model.ChecklistItem, error) {
	var (
		item       model.ChecklistItem
		checkedInt int
	)

	err := rows.Scan(
		&item.ID, &item.TodoID, &item.Text, &checkedInt,
		&item.SortOrder, &item.CreatedAt,
	)
	if err != nil {
		return model.ChecklistItem{}, fmt.Errorf("scanning checklist item row: %w", err)
	}

	item.Checked = checkedInt != 0
	return item, nil
}
