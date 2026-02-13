package model

import "time"

// SourceType identifies the origin system of a task.
type SourceType string

const (
	SourceTypeJira      SourceType = "jira"
	SourceTypeBitbucket SourceType = "bitbucket"
	SourceTypeEmail     SourceType = "email"
)

// Normalized status constants used across all source types.
const (
	StatusOpen       = "open"
	StatusInProgress = "in_progress"
	StatusReview     = "review"
	StatusDone       = "done"
)

// Normalized priority constants (lower number = higher priority).
const (
	PriorityCritical = 1
	PriorityHigh     = 2
	PriorityMedium   = 3
	PriorityLow      = 4
	PriorityLowest   = 5
)

// Task is the unified representation of a work item from any source.
type Task struct {
	// ID is the internal unique identifier for this task.
	ID string `json:"id"`

	// SourceType identifies which integration produced this task.
	SourceType SourceType `json:"source_type"`

	// SourceItemID is the item's identifier within its source system
	// (e.g., Jira issue key, Bitbucket PR number).
	SourceItemID string `json:"source_item_id"`

	// SourceID is the identifier for the configured source instance.
	SourceID string `json:"source_id"`

	// Title is the human-readable summary of the task.
	Title string `json:"title"`

	// Description is the full body/description text.
	Description string `json:"description"`

	// Status is the normalized status (use Status* constants).
	Status string `json:"status"`

	// Priority is the normalized priority level (use Priority* constants).
	Priority int `json:"priority"`

	// Assignee is the display name or username of the assigned person.
	Assignee string `json:"assignee"`

	// Author is the display name or username of the creator.
	Author string `json:"author"`

	// SourceURL is the direct link back to the item in its source system.
	SourceURL string `json:"source_url"`

	// CreatedAt is when the item was originally created in the source system.
	CreatedAt time.Time `json:"created_at"`

	// UpdatedAt is when the item was last modified in the source system.
	UpdatedAt time.Time `json:"updated_at"`

	// FetchedAt is when this item was last retrieved from the source.
	FetchedAt time.Time `json:"fetched_at"`

	// RawData holds the original JSON payload from the source system.
	RawData string `json:"raw_data"`

	// CrossRefs holds references to related items across sources.
	CrossRefs []string `json:"cross_refs,omitempty"`
}
