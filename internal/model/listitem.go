package model

import "time"

// ListItem is the common interface for items displayed in the unified list view.
// Both Todo (local) and Task (external) implement this interface.
type ListItem interface {
	GetID() string
	GetTitle() string
	GetDescription() string
	GetStatus() string
	GetPriority() int
	IsCompleted() bool
	GetSource() string
	IsLocal() bool
	GetCreatedAt() time.Time
	GetUpdatedAt() time.Time
	GetDueDate() *time.Time
	IsOverdue() bool
	GetProjectID() *string
	GetSortOrder() int
}

// Todo implements ListItem.

func (t Todo) GetID() string            { return t.ID }
func (t Todo) GetTitle() string          { return t.Title }
func (t Todo) GetDescription() string    { return t.Description }
func (t Todo) GetStatus() string         { return t.Status }
func (t Todo) GetPriority() int          { return t.Priority }
func (t Todo) IsCompleted() bool         { return t.Status == TodoStatusComplete }
func (t Todo) GetSource() string         { return "local" }
func (t Todo) IsLocal() bool             { return true }
func (t Todo) GetCreatedAt() time.Time   { return t.CreatedAt }
func (t Todo) GetUpdatedAt() time.Time   { return t.UpdatedAt }
func (t Todo) GetDueDate() *time.Time    { return t.DueDate }
func (t Todo) IsOverdue() bool {
	return t.DueDate != nil && t.DueDate.Before(time.Now()) && t.Status != TodoStatusComplete
}
func (t Todo) GetProjectID() *string     { return t.ProjectID }
func (t Todo) GetSortOrder() int         { return t.SortOrder }

// Task implements ListItem.

func (t Task) GetID() string            { return t.ID }
func (t Task) GetTitle() string          { return t.Title }
func (t Task) GetDescription() string    { return t.Description }
func (t Task) GetStatus() string         { return t.Status }
func (t Task) GetPriority() int          { return t.Priority }
func (t Task) IsCompleted() bool         { return t.Status == StatusDone }
func (t Task) GetSource() string         { return string(t.SourceType) }
func (t Task) IsLocal() bool             { return false }
func (t Task) GetCreatedAt() time.Time   { return t.CreatedAt }
func (t Task) GetUpdatedAt() time.Time   { return t.UpdatedAt }
func (t Task) GetDueDate() *time.Time    { return nil }
func (t Task) IsOverdue() bool           { return false }
func (t Task) GetProjectID() *string     { return nil }
func (t Task) GetSortOrder() int         { return 0 }
