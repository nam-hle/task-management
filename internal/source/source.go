package source

import (
	"context"
	"errors"
	"fmt"

	"github.com/nhle/task-management/internal/model"
)

// AuthError indicates that authentication has failed or expired for a source.
// It is returned by source clients when a 401 response is received.
type AuthError struct {
	SourceType SourceType
	Message    string
}

func (e *AuthError) Error() string {
	return fmt.Sprintf("auth error (%s): %s", e.SourceType, e.Message)
}

// IsAuthError reports whether err (or any error in its chain) is an AuthError.
func IsAuthError(err error) bool {
	var authErr *AuthError
	return errors.As(err, &authErr)
}

// SourceType identifies the kind of external source integration.
type SourceType string

const (
	SourceTypeJira      SourceType = "jira"
	SourceTypeBitbucket SourceType = "bitbucket"
	SourceTypeEmail     SourceType = "email"
)

// FetchOptions controls pagination for list and search operations.
type FetchOptions struct {
	Page     int
	PageSize int
}

// FetchResult holds a page of tasks returned from a source query.
type FetchResult struct {
	Items   []model.Task
	Total   int
	HasMore bool
}

// Comment represents a single comment or reply on a source item.
type Comment struct {
	Author    string
	Body      string
	CreatedAt string
}

// ItemDetail extends a Task with additional rendered content and metadata
// available when viewing a single item in detail.
type ItemDetail struct {
	model.Task

	// RenderedBody is the description/body formatted for terminal display.
	RenderedBody string

	// Metadata holds arbitrary key-value pairs from the source
	// (e.g., labels, components, sprint info).
	Metadata map[string]string

	// Comments contains the discussion thread for the item.
	Comments []Comment
}

// Action describes an operation that can be performed on a source item
// (e.g., transition status, add comment, approve PR).
type Action struct {
	// ID is the machine-readable action identifier.
	ID string

	// Name is the human-readable label shown in the UI.
	Name string

	// RequiresInput indicates whether the user must provide text input.
	RequiresInput bool

	// InputPrompt is the prompt shown when RequiresInput is true.
	InputPrompt string
}

// Source defines the contract that every external integration must implement.
type Source interface {
	// Type returns the source type identifier.
	Type() SourceType

	// ValidateConnection verifies credentials and connectivity.
	// Returns a human-readable status message on success.
	ValidateConnection(ctx context.Context) (string, error)

	// FetchItems retrieves a page of tasks from the source.
	FetchItems(ctx context.Context, opts FetchOptions) (*FetchResult, error)

	// GetItemDetail retrieves full details for a single item.
	GetItemDetail(ctx context.Context, sourceItemID string) (*ItemDetail, error)

	// GetActions returns the available actions for a source item.
	GetActions(ctx context.Context, sourceItemID string) ([]Action, error)

	// ExecuteAction performs an action on a source item, optionally
	// with user-provided input text.
	ExecuteAction(
		ctx context.Context,
		sourceItemID string,
		action Action,
		input string,
	) error

	// Search finds items matching the query string with pagination.
	Search(
		ctx context.Context,
		query string,
		opts FetchOptions,
	) (*FetchResult, error)
}
