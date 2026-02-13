package store

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/nhle/task-management/internal/model"
)

// CreateProject inserts a new project.
func (s *SQLiteStore) CreateProject(ctx context.Context, project model.Project) error {
	if strings.TrimSpace(project.Name) == "" {
		return fmt.Errorf("project name must not be empty")
	}
	if project.ID == "" {
		project.ID = uuid.New().String()
	}
	now := time.Now().UTC()
	project.CreatedAt = now
	project.UpdatedAt = now

	if project.SortOrder == 0 {
		var maxOrder int
		_ = s.db.GetContext(ctx, &maxOrder,
			"SELECT COALESCE(MAX(sort_order), 0) FROM projects")
		project.SortOrder = maxOrder + 1
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO projects (id, name, description, color, icon, archived, sort_order, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		project.ID, project.Name, project.Description, project.Color, project.Icon,
		boolToInt(project.Archived), project.SortOrder, project.CreatedAt, project.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("creating project: %w", err)
	}
	return nil
}

// UpdateProject updates an existing project.
func (s *SQLiteStore) UpdateProject(ctx context.Context, project model.Project) error {
	if strings.TrimSpace(project.Name) == "" {
		return fmt.Errorf("project name must not be empty")
	}
	project.UpdatedAt = time.Now().UTC()

	result, err := s.db.ExecContext(ctx, `
		UPDATE projects SET
			name = ?, description = ?, color = ?, icon = ?,
			archived = ?, sort_order = ?, updated_at = ?
		WHERE id = ?`,
		project.Name, project.Description, project.Color, project.Icon,
		boolToInt(project.Archived), project.SortOrder, project.UpdatedAt,
		project.ID,
	)
	if err != nil {
		return fmt.Errorf("updating project %s: %w", project.ID, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("project %s not found", project.ID)
	}
	return nil
}

// DeleteProject removes a project. Associated todos get project_id set to NULL.
func (s *SQLiteStore) DeleteProject(ctx context.Context, id string) error {
	result, err := s.db.ExecContext(ctx, "DELETE FROM projects WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("deleting project %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("project %s not found", id)
	}
	return nil
}

// GetProjectByID retrieves a single project by ID.
func (s *SQLiteStore) GetProjectByID(
	ctx context.Context,
	id string,
) (*model.Project, error) {
	var project model.Project
	var archivedInt int

	err := s.db.QueryRowxContext(ctx, "SELECT * FROM projects WHERE id = ?", id).Scan(
		&project.ID, &project.Name, &project.Description,
		&project.Color, &project.Icon, &archivedInt,
		&project.SortOrder, &project.CreatedAt, &project.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("getting project %s: %w", id, err)
	}
	project.Archived = archivedInt != 0
	return &project, nil
}

// GetProjects retrieves all projects, optionally including archived ones.
func (s *SQLiteStore) GetProjects(
	ctx context.Context,
	includeArchived bool,
) ([]model.Project, error) {
	query := "SELECT * FROM projects"
	if !includeArchived {
		query += " WHERE archived = 0"
	}
	query += " ORDER BY sort_order"

	rows, err := s.db.QueryxContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("querying projects: %w", err)
	}
	defer rows.Close()

	var projects []model.Project
	for rows.Next() {
		var p model.Project
		var archivedInt int
		err := rows.Scan(
			&p.ID, &p.Name, &p.Description,
			&p.Color, &p.Icon, &archivedInt,
			&p.SortOrder, &p.CreatedAt, &p.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("scanning project row: %w", err)
		}
		p.Archived = archivedInt != 0
		projects = append(projects, p)
	}
	return projects, rows.Err()
}

// ArchiveProject sets the archived flag to true.
func (s *SQLiteStore) ArchiveProject(ctx context.Context, id string) error {
	result, err := s.db.ExecContext(ctx,
		"UPDATE projects SET archived = 1, updated_at = ? WHERE id = ?",
		time.Now().UTC(), id)
	if err != nil {
		return fmt.Errorf("archiving project %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("project %s not found", id)
	}
	return nil
}

// RestoreProject sets the archived flag to false.
func (s *SQLiteStore) RestoreProject(ctx context.Context, id string) error {
	result, err := s.db.ExecContext(ctx,
		"UPDATE projects SET archived = 0, updated_at = ? WHERE id = ?",
		time.Now().UTC(), id)
	if err != nil {
		return fmt.Errorf("restoring project %s: %w", id, err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("project %s not found", id)
	}
	return nil
}
