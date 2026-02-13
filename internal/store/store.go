package store

import (
	"context"

	"github.com/nhle/task-management/internal/model"
)

// TaskFilter controls filtering, sorting, and pagination for task queries.
type TaskFilter struct {
	SourceType *string
	Status     *string
	Priority   *int
	Query      *string
	SortBy     string
	SortDesc   bool
	Limit      int
	Offset     int
}

// TodoFilter controls filtering, sorting, and pagination for todo queries.
type TodoFilter struct {
	Status    *string  // "open", "complete", or nil (all)
	Priority  *int     // 1-5 or nil (all)
	ProjectID *string  // project UUID, "inbox" (NULL project_id), or nil (all)
	TagIDs    []string // filter by any of these tags (OR logic)
	Query     *string  // search title + description
	DueDate   *string  // "today", "upcoming" (next 7 days), "overdue", or nil
	SortBy    string   // "sort_order", "priority", "due_date", "created_at", "updated_at", "title"
	SortDesc  bool
	Limit     int
	Offset    int
}

// Store defines the persistence interface for tasks, sources, notifications,
// and local todos with their associated entities.
type Store interface {
	// === Tasks (existing, unchanged) ===

	UpsertTasks(ctx context.Context, tasks []model.Task) error
	GetTasks(ctx context.Context, opts TaskFilter) ([]model.Task, error)
	GetTaskByID(ctx context.Context, id string) (*model.Task, error)

	// === Sources (existing, unchanged) ===

	UpsertSource(ctx context.Context, src model.SourceConfig) error
	GetSources(ctx context.Context) ([]model.SourceConfig, error)
	DeleteSource(ctx context.Context, id string) error

	// === Notifications (existing, unchanged) ===

	CreateNotification(ctx context.Context, n model.Notification) error
	GetUnreadNotifications(ctx context.Context) ([]model.Notification, error)
	MarkNotificationRead(ctx context.Context, id string) error

	// === Todo CRUD ===

	CreateTodo(ctx context.Context, todo model.Todo) error
	UpdateTodo(ctx context.Context, todo model.Todo) error
	DeleteTodo(ctx context.Context, id string) error
	GetTodoByID(ctx context.Context, id string) (*model.Todo, error)
	GetTodos(ctx context.Context, filter TodoFilter) ([]model.Todo, error)
	GetTodoCount(ctx context.Context, filter TodoFilter) (int, error)
	ReorderTodo(ctx context.Context, id string, newSortOrder int) error

	// === Project CRUD ===

	CreateProject(ctx context.Context, project model.Project) error
	UpdateProject(ctx context.Context, project model.Project) error
	DeleteProject(ctx context.Context, id string) error
	GetProjectByID(ctx context.Context, id string) (*model.Project, error)
	GetProjects(ctx context.Context, includeArchived bool) ([]model.Project, error)
	ArchiveProject(ctx context.Context, id string) error
	RestoreProject(ctx context.Context, id string) error

	// === Tag CRUD ===

	CreateTag(ctx context.Context, tag model.Tag) error
	UpdateTag(ctx context.Context, tag model.Tag) error
	DeleteTag(ctx context.Context, id string) error
	GetTags(ctx context.Context) ([]model.Tag, error)
	GetTagsForTodo(ctx context.Context, todoID string) ([]model.Tag, error)
	SetTodoTags(ctx context.Context, todoID string, tagIDs []string) error

	// === Checklist CRUD ===

	AddChecklistItem(ctx context.Context, item model.ChecklistItem) error
	UpdateChecklistItem(ctx context.Context, item model.ChecklistItem) error
	DeleteChecklistItem(ctx context.Context, id string) error
	GetChecklistItems(ctx context.Context, todoID string) ([]model.ChecklistItem, error)
	ToggleChecklistItem(ctx context.Context, id string) error
	ReorderChecklistItem(ctx context.Context, id string, newSortOrder int) error

	// === Link Management ===

	CreateLink(ctx context.Context, link model.Link) error
	DeleteLink(ctx context.Context, id string) error
	GetLinksForTodo(ctx context.Context, todoID string) ([]model.Link, error)
	GetLinksForTask(ctx context.Context, taskID string) ([]model.Link, error)
}
