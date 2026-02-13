package store

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/nhle/task-management/internal/model"
)

// CreateLink creates a link between a local todo and an external task.
func (s *SQLiteStore) CreateLink(ctx context.Context, link model.Link) error {
	if link.ID == "" {
		link.ID = uuid.New().String()
	}
	if link.LinkType == "" {
		link.LinkType = model.LinkTypeManual
	}
	link.CreatedAt = time.Now().UTC()

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO links (id, todo_id, task_id, link_type, created_at)
		VALUES (?, ?, ?, ?, ?)`,
		link.ID, link.TodoID, link.TaskID, link.LinkType, link.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("creating link: %w", err)
	}
	return nil
}

// DeleteLink removes a link by ID.
func (s *SQLiteStore) DeleteLink(ctx context.Context, id string) error {
	result, err := s.db.ExecContext(ctx, "DELETE FROM links WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("deleting link %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("link %s not found", id)
	}
	return nil
}

// GetLinksForTodo retrieves all links for a todo, with associated task titles.
func (s *SQLiteStore) GetLinksForTodo(
	ctx context.Context,
	todoID string,
) ([]model.Link, error) {
	rows, err := s.db.QueryxContext(ctx, `
		SELECT l.*, COALESCE(t.title, '') as task_title
		FROM links l
		LEFT JOIN tasks t ON l.task_id = t.id
		WHERE l.todo_id = ?
		ORDER BY l.created_at`, todoID)
	if err != nil {
		return nil, fmt.Errorf("querying links for todo %s: %w", todoID, err)
	}
	defer rows.Close()

	var links []model.Link
	for rows.Next() {
		var link model.Link
		if err := rows.Scan(
			&link.ID, &link.TodoID, &link.TaskID, &link.LinkType,
			&link.CreatedAt, &link.TaskTitle,
		); err != nil {
			return nil, fmt.Errorf("scanning link row: %w", err)
		}
		links = append(links, link)
	}
	return links, rows.Err()
}

// GetLinksForTask retrieves all links for an external task, with todo titles.
func (s *SQLiteStore) GetLinksForTask(
	ctx context.Context,
	taskID string,
) ([]model.Link, error) {
	rows, err := s.db.QueryxContext(ctx, `
		SELECT l.*, COALESCE(td.title, '') as todo_title
		FROM links l
		LEFT JOIN todos td ON l.todo_id = td.id
		WHERE l.task_id = ?
		ORDER BY l.created_at`, taskID)
	if err != nil {
		return nil, fmt.Errorf("querying links for task %s: %w", taskID, err)
	}
	defer rows.Close()

	var links []model.Link
	for rows.Next() {
		var link model.Link
		if err := rows.Scan(
			&link.ID, &link.TodoID, &link.TaskID, &link.LinkType,
			&link.CreatedAt, &link.TodoTitle,
		); err != nil {
			return nil, fmt.Errorf("scanning link row: %w", err)
		}
		links = append(links, link)
	}
	return links, rows.Err()
}
