package model

import "time"

// Todo status constants.
const (
	TodoStatusOpen     = "open"
	TodoStatusComplete = "complete"
)

// Todo is a local task item created and managed by the user.
type Todo struct {
	ID          string     `json:"id" db:"id"`
	Title       string     `json:"title" db:"title"`
	Description string     `json:"description" db:"description"`
	Status      string     `json:"status" db:"status"`
	Priority    int        `json:"priority" db:"priority"`
	DueDate     *time.Time `json:"due_date,omitempty" db:"due_date"`
	SortOrder   int        `json:"sort_order" db:"sort_order"`
	ProjectID   *string    `json:"project_id,omitempty" db:"project_id"`
	CreatedAt   time.Time  `json:"created_at" db:"created_at"`
	CompletedAt *time.Time `json:"completed_at,omitempty" db:"completed_at"`
	UpdatedAt   time.Time  `json:"updated_at" db:"updated_at"`

	// Tags is populated by queries that join with todo_tags.
	Tags []Tag `json:"tags,omitempty" db:"-"`

	// ChecklistCount is optionally populated for list views.
	ChecklistCount    int `json:"checklist_count,omitempty" db:"-"`
	ChecklistDoneCount int `json:"checklist_done_count,omitempty" db:"-"`
}

// ChecklistItem is a simple sub-entry within a todo.
// Its lifecycle is bound to the parent todo (CASCADE delete).
type ChecklistItem struct {
	ID        string    `json:"id" db:"id"`
	TodoID    string    `json:"todo_id" db:"todo_id"`
	Text      string    `json:"text" db:"text"`
	Checked   bool      `json:"checked" db:"checked"`
	SortOrder int       `json:"sort_order" db:"sort_order"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}
