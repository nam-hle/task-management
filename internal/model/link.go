package model

import "time"

// Link type constants.
const (
	LinkTypeManual = "manual"
	LinkTypeAuto   = "auto"
)

// Link is an association between a local todo and an external task.
type Link struct {
	ID        string    `json:"id" db:"id"`
	TodoID    string    `json:"todo_id" db:"todo_id"`
	TaskID    string    `json:"task_id" db:"task_id"`
	LinkType  string    `json:"link_type" db:"link_type"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`

	// TodoTitle and TaskTitle are optionally populated by join queries.
	TodoTitle string `json:"todo_title,omitempty" db:"-"`
	TaskTitle string `json:"task_title,omitempty" db:"-"`
}
