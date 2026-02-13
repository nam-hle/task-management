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

// Store defines the persistence interface for tasks, sources, and notifications.
type Store interface {
	// UpsertTasks inserts or replaces a batch of tasks.
	UpsertTasks(ctx context.Context, tasks []model.Task) error

	// GetTasks retrieves tasks matching the provided filter.
	GetTasks(ctx context.Context, opts TaskFilter) ([]model.Task, error)

	// GetTaskByID retrieves a single task by its unique ID.
	GetTaskByID(ctx context.Context, id string) (*model.Task, error)

	// UpsertSource inserts or replaces a source configuration.
	// The SourceConfig.Config map is serialized as JSON in the config column.
	UpsertSource(ctx context.Context, src model.SourceConfig) error

	// GetSources retrieves all configured source entries.
	GetSources(ctx context.Context) ([]model.SourceConfig, error)

	// DeleteSource removes a source by its ID.
	DeleteSource(ctx context.Context, id string) error

	// CreateNotification inserts a new notification record.
	CreateNotification(ctx context.Context, n model.Notification) error

	// GetUnreadNotifications retrieves all unread notifications,
	// ordered by creation time descending.
	GetUnreadNotifications(ctx context.Context) ([]model.Notification, error)

	// MarkNotificationRead marks a single notification as read.
	MarkNotificationRead(ctx context.Context, id string) error
}
