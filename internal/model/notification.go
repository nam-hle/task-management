package model

import "time"

// Notification represents an alert or update surfaced to the user
// about activity on a tracked task.
type Notification struct {
	// ID is the unique identifier for this notification.
	ID string `json:"id"`

	// TaskID links this notification to the originating task.
	TaskID string `json:"task_id"`

	// SourceType identifies which integration generated this notification.
	SourceType SourceType `json:"source_type"`

	// Message is the human-readable notification text.
	Message string `json:"message"`

	// Read indicates whether the user has seen this notification.
	Read bool `json:"read"`

	// CreatedAt is when this notification was generated.
	CreatedAt time.Time `json:"created_at"`
}
