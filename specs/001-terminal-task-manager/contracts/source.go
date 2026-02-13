// Package source defines the common interface for all external source adapters.
// This is the contract that each integration (Jira, Bitbucket, Email) must implement.
package source

import "context"

// SourceType identifies the kind of external source.
type SourceType string

const (
	SourceTypeJira      SourceType = "jira"
	SourceTypeBitbucket SourceType = "bitbucket"
	SourceTypeEmail     SourceType = "email"
)

// Source is the common interface for all external source adapters.
// Each source must implement these methods to integrate with the unified task list.
type Source interface {
	// Type returns the source type identifier.
	Type() SourceType

	// ValidateConnection tests the configured credentials and returns the
	// authenticated user's display name, or an error.
	ValidateConnection(ctx context.Context) (string, error)

	// FetchItems retrieves items from the source. Returns normalized Task items
	// suitable for the unified list.
	FetchItems(ctx context.Context, opts FetchOptions) (*FetchResult, error)

	// GetItemDetail retrieves the full detail for a single item by its
	// source-specific ID. Returns the raw source data for the detail view.
	GetItemDetail(ctx context.Context, sourceItemID string) (*ItemDetail, error)

	// GetActions returns the available actions for an item in its current state.
	GetActions(ctx context.Context, sourceItemID string) ([]Action, error)

	// ExecuteAction performs a write action on an item (e.g., transition, comment).
	ExecuteAction(ctx context.Context, sourceItemID string, action Action, input string) error

	// Search performs a source-specific search query.
	Search(ctx context.Context, query string, opts FetchOptions) (*FetchResult, error)
}

// FetchOptions controls pagination and filtering for fetch operations.
type FetchOptions struct {
	Page     int
	PageSize int
}

// FetchResult contains a page of normalized task items.
type FetchResult struct {
	Items   []Task
	Total   int
	HasMore bool
}

// Task is the unified, normalized representation of a work item.
type Task struct {
	ID           string
	SourceType   SourceType
	SourceItemID string
	SourceID     string // Reference to configured Source (foreign key)
	Title        string
	Description  string
	Status       string
	Priority     int
	Assignee     string
	Author       string
	SourceURL    string
	CreatedAt    string
	UpdatedAt    string
	FetchedAt    string // When this item was last synced from the source
	RawData      string
	CrossRefs    []string
}

// ItemDetail contains the full information for a single source item,
// including source-specific fields for rendering in the detail view.
type ItemDetail struct {
	Task
	RenderedBody string            // Markdown/text body for display
	Metadata     map[string]string // Source-specific key-value pairs
	Comments     []Comment
}

// Comment represents a comment or reply on a source item.
type Comment struct {
	Author    string
	Body      string
	CreatedAt string
}

// Action represents an available action on a source item.
type Action struct {
	ID          string
	Name        string
	RequiresInput bool   // Whether the action needs text input (e.g., comment body)
	InputPrompt   string // Prompt to show if input is required
}
