package store

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/nhle/task-management/internal/model"
)

// CreateTag inserts a new tag.
func (s *SQLiteStore) CreateTag(ctx context.Context, tag model.Tag) error {
	if strings.TrimSpace(tag.Name) == "" {
		return fmt.Errorf("tag name must not be empty")
	}
	if tag.ID == "" {
		tag.ID = uuid.New().String()
	}
	tag.CreatedAt = time.Now().UTC()

	_, err := s.db.ExecContext(ctx,
		"INSERT INTO tags (id, name, color, created_at) VALUES (?, ?, ?, ?)",
		tag.ID, tag.Name, tag.Color, tag.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("creating tag: %w", err)
	}
	return nil
}

// UpdateTag updates a tag's name and color.
func (s *SQLiteStore) UpdateTag(ctx context.Context, tag model.Tag) error {
	if strings.TrimSpace(tag.Name) == "" {
		return fmt.Errorf("tag name must not be empty")
	}
	result, err := s.db.ExecContext(ctx,
		"UPDATE tags SET name = ?, color = ? WHERE id = ?",
		tag.Name, tag.Color, tag.ID,
	)
	if err != nil {
		return fmt.Errorf("updating tag %s: %w", tag.ID, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("tag %s not found", tag.ID)
	}
	return nil
}

// DeleteTag removes a tag. CASCADE on todo_tags removes associations.
func (s *SQLiteStore) DeleteTag(ctx context.Context, id string) error {
	result, err := s.db.ExecContext(ctx, "DELETE FROM tags WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("deleting tag %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("tag %s not found", id)
	}
	return nil
}

// GetTags retrieves all tags ordered by name.
func (s *SQLiteStore) GetTags(ctx context.Context) ([]model.Tag, error) {
	rows, err := s.db.QueryxContext(ctx,
		"SELECT * FROM tags ORDER BY name")
	if err != nil {
		return nil, fmt.Errorf("querying tags: %w", err)
	}
	defer rows.Close()

	var tags []model.Tag
	for rows.Next() {
		var t model.Tag
		if err := rows.Scan(&t.ID, &t.Name, &t.Color, &t.CreatedAt); err != nil {
			return nil, fmt.Errorf("scanning tag row: %w", err)
		}
		tags = append(tags, t)
	}
	return tags, rows.Err()
}

// GetTagsForTodo retrieves all tags associated with a todo.
func (s *SQLiteStore) GetTagsForTodo(
	ctx context.Context,
	todoID string,
) ([]model.Tag, error) {
	rows, err := s.db.QueryxContext(ctx, `
		SELECT t.* FROM tags t
		INNER JOIN todo_tags tt ON t.id = tt.tag_id
		WHERE tt.todo_id = ?
		ORDER BY t.name`, todoID)
	if err != nil {
		return nil, fmt.Errorf("querying tags for todo %s: %w", todoID, err)
	}
	defer rows.Close()

	var tags []model.Tag
	for rows.Next() {
		var t model.Tag
		if err := rows.Scan(&t.ID, &t.Name, &t.Color, &t.CreatedAt); err != nil {
			return nil, fmt.Errorf("scanning tag row: %w", err)
		}
		tags = append(tags, t)
	}
	return tags, rows.Err()
}

// SetTodoTags replaces all tag associations for a todo.
func (s *SQLiteStore) SetTodoTags(
	ctx context.Context,
	todoID string,
	tagIDs []string,
) error {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return fmt.Errorf("beginning transaction: %w", err)
	}
	defer tx.Rollback()

	// Remove existing associations.
	if _, err := tx.ExecContext(ctx,
		"DELETE FROM todo_tags WHERE todo_id = ?", todoID); err != nil {
		return fmt.Errorf("clearing todo tags: %w", err)
	}

	// Insert new associations.
	for _, tagID := range tagIDs {
		if _, err := tx.ExecContext(ctx,
			"INSERT INTO todo_tags (todo_id, tag_id) VALUES (?, ?)",
			todoID, tagID); err != nil {
			return fmt.Errorf("setting tag %s on todo %s: %w", tagID, todoID, err)
		}
	}

	return tx.Commit()
}
