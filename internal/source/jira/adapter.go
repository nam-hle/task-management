package jira

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source"
)

// defaultJQL is used when no custom JQL is configured.
const defaultJQL = "assignee=currentUser() AND " +
	"resolution=Unresolved ORDER BY updated DESC"

// fetchFields are the Jira fields requested during list/search queries.
var fetchFields = []string{
	"summary", "status", "priority", "assignee", "issuetype",
	"project", "created", "updated", "labels", "duedate",
}

// Adapter implements source.Source for Jira Server/DC.
type Adapter struct {
	client     *Client
	baseURL    string
	sourceID   string
	defaultJQL string
}

// NewAdapter creates a new Jira source adapter.
func NewAdapter(
	baseURL string,
	token string,
	sourceID string,
	jql string,
) *Adapter {
	if jql == "" {
		jql = defaultJQL
	}
	return &Adapter{
		client:     NewClient(baseURL, token),
		baseURL:    strings.TrimRight(baseURL, "/"),
		sourceID:   sourceID,
		defaultJQL: jql,
	}
}

// Type returns the source type identifier for Jira.
func (a *Adapter) Type() source.SourceType {
	return source.SourceTypeJira
}

// ValidateConnection verifies credentials by calling GET /rest/api/2/myself.
// Returns the user's display name on success.
func (a *Adapter) ValidateConnection(
	ctx context.Context,
) (string, error) {
	var me Myself
	if err := a.client.Get(ctx, "/rest/api/2/myself", &me); err != nil {
		return "", fmt.Errorf("validating Jira connection: %w", err)
	}
	return me.DisplayName, nil
}

// FetchItems retrieves a page of Jira issues assigned to the current user.
func (a *Adapter) FetchItems(
	ctx context.Context,
	opts source.FetchOptions,
) (*source.FetchResult, error) {
	page := opts.Page
	if page < 1 {
		page = 1
	}
	pageSize := opts.PageSize
	if pageSize < 1 {
		pageSize = 50
	}

	startAt := (page - 1) * pageSize

	body := map[string]interface{}{
		"jql":        a.defaultJQL,
		"fields":     fetchFields,
		"startAt":    startAt,
		"maxResults": pageSize,
	}

	var searchResp SearchResponse
	err := a.client.Post(
		ctx, "/rest/api/2/search", body, &searchResp,
	)
	if err != nil {
		return nil, fmt.Errorf("fetching Jira items: %w", err)
	}

	tasks := make([]model.Task, 0, len(searchResp.Issues))
	for _, issue := range searchResp.Issues {
		tasks = append(tasks, a.issueToTask(issue))
	}

	hasMore := startAt+len(searchResp.Issues) < searchResp.Total

	return &source.FetchResult{
		Items:   tasks,
		Total:   searchResp.Total,
		HasMore: hasMore,
	}, nil
}

// GetItemDetail retrieves full details for a single Jira issue,
// including rendered HTML fields and available transitions.
func (a *Adapter) GetItemDetail(
	ctx context.Context,
	sourceItemID string,
) (*source.ItemDetail, error) {
	path := fmt.Sprintf(
		"/rest/api/2/issue/%s?expand=renderedFields,transitions",
		sourceItemID,
	)

	var issue Issue
	if err := a.client.Get(ctx, path, &issue); err != nil {
		return nil, fmt.Errorf(
			"fetching Jira issue %s: %w", sourceItemID, err,
		)
	}

	task := a.issueToTask(issue)

	renderedBody := ""
	if issue.RenderedFields != nil {
		renderedBody = stripHTML(issue.RenderedFields.Description)
	}
	if renderedBody == "" {
		renderedBody = issue.Fields.Description
	}

	metadata := make(map[string]string)
	metadata["Project"] = fmt.Sprintf(
		"%s (%s)", issue.Fields.Project.Name, issue.Fields.Project.Key,
	)
	metadata["Type"] = issue.Fields.IssueType.Name
	if len(issue.Fields.Labels) > 0 {
		metadata["Labels"] = strings.Join(issue.Fields.Labels, ", ")
	}
	if issue.Fields.DueDate != "" {
		metadata["Due Date"] = issue.Fields.DueDate
	}

	var comments []source.Comment
	if issue.Fields.Comment != nil {
		for _, c := range issue.Fields.Comment.Comments {
			comments = append(comments, source.Comment{
				Author:    c.Author.DisplayName,
				Body:      c.Body,
				CreatedAt: c.Created,
			})
		}
	}

	return &source.ItemDetail{
		Task:         task,
		RenderedBody: renderedBody,
		Metadata:     metadata,
		Comments:     comments,
	}, nil
}

// GetActions returns the available transitions for a Jira issue,
// plus a built-in "Add Comment" action.
func (a *Adapter) GetActions(
	ctx context.Context,
	sourceItemID string,
) ([]source.Action, error) {
	path := fmt.Sprintf(
		"/rest/api/2/issue/%s/transitions", sourceItemID,
	)

	var transResp TransitionsResponse
	if err := a.client.Get(ctx, path, &transResp); err != nil {
		return nil, fmt.Errorf(
			"fetching transitions for %s: %w", sourceItemID, err,
		)
	}

	actions := make([]source.Action, 0, len(transResp.Transitions)+1)

	// Add comment action is always available.
	actions = append(actions, source.Action{
		ID:            "comment",
		Name:          "Add Comment",
		RequiresInput: true,
		InputPrompt:   "Enter comment text:",
	})

	for _, t := range transResp.Transitions {
		actions = append(actions, source.Action{
			ID:   "transition-" + t.ID,
			Name: t.Name,
		})
	}

	return actions, nil
}

// ExecuteAction performs a transition or adds a comment on a Jira issue.
func (a *Adapter) ExecuteAction(
	ctx context.Context,
	sourceItemID string,
	action source.Action,
	input string,
) error {
	if action.ID == "comment" {
		return a.addComment(ctx, sourceItemID, input)
	}

	if strings.HasPrefix(action.ID, "transition-") {
		transitionID := strings.TrimPrefix(action.ID, "transition-")
		return a.doTransition(ctx, sourceItemID, transitionID)
	}

	return fmt.Errorf("unknown action %q for issue %s", action.ID, sourceItemID)
}

// Search finds Jira issues matching the query text assigned to the
// current user.
func (a *Adapter) Search(
	ctx context.Context,
	query string,
	opts source.FetchOptions,
) (*source.FetchResult, error) {
	page := opts.Page
	if page < 1 {
		page = 1
	}
	pageSize := opts.PageSize
	if pageSize < 1 {
		pageSize = 50
	}

	startAt := (page - 1) * pageSize

	jql := fmt.Sprintf(
		`text~"%s" AND assignee=currentUser() ORDER BY updated DESC`,
		escapeJQL(query),
	)

	body := map[string]interface{}{
		"jql":        jql,
		"fields":     fetchFields,
		"startAt":    startAt,
		"maxResults": pageSize,
	}

	var searchResp SearchResponse
	err := a.client.Post(
		ctx, "/rest/api/2/search", body, &searchResp,
	)
	if err != nil {
		return nil, fmt.Errorf("searching Jira issues: %w", err)
	}

	tasks := make([]model.Task, 0, len(searchResp.Issues))
	for _, issue := range searchResp.Issues {
		tasks = append(tasks, a.issueToTask(issue))
	}

	hasMore := startAt+len(searchResp.Issues) < searchResp.Total

	return &source.FetchResult{
		Items:   tasks,
		Total:   searchResp.Total,
		HasMore: hasMore,
	}, nil
}

// addComment posts a new comment to a Jira issue.
func (a *Adapter) addComment(
	ctx context.Context,
	sourceItemID string,
	body string,
) error {
	path := fmt.Sprintf("/rest/api/2/issue/%s/comment", sourceItemID)
	payload := map[string]string{"body": body}

	var result Comment
	return a.client.Post(ctx, path, payload, &result)
}

// doTransition performs a status transition on a Jira issue.
func (a *Adapter) doTransition(
	ctx context.Context,
	sourceItemID string,
	transitionID string,
) error {
	path := fmt.Sprintf(
		"/rest/api/2/issue/%s/transitions", sourceItemID,
	)
	payload := map[string]interface{}{
		"transition": map[string]string{"id": transitionID},
	}

	// Transition endpoint returns 204 No Content on success.
	return a.client.Post(ctx, path, payload, nil)
}

// issueToTask converts a Jira Issue to a model.Task.
func (a *Adapter) issueToTask(issue Issue) model.Task {
	rawData, _ := json.Marshal(issue)

	assignee := ""
	if issue.Fields.Assignee != nil {
		assignee = issue.Fields.Assignee.DisplayName
	}

	author := ""
	if issue.Fields.Reporter != nil {
		author = issue.Fields.Reporter.DisplayName
	}

	return model.Task{
		ID:           "jira-" + issue.Key,
		SourceType:   model.SourceTypeJira,
		SourceItemID: issue.Key,
		SourceID:     a.sourceID,
		Title:        issue.Fields.Summary,
		Description:  issue.Fields.Description,
		Status:       normalizeStatus(issue.Fields.Status),
		Priority:     normalizePriority(issue.Fields.Priority),
		Assignee:     assignee,
		Author:       author,
		SourceURL:    a.baseURL + "/browse/" + issue.Key,
		CreatedAt:    parseJiraTime(issue.Fields.Created),
		UpdatedAt:    parseJiraTime(issue.Fields.Updated),
		FetchedAt:    time.Now(),
		RawData:      string(rawData),
	}
}

// normalizeStatus maps a Jira status to a normalized status constant.
// It first checks if the status name contains "review" (case-insensitive),
// then falls back to the status category key mapping.
func normalizeStatus(status Status) string {
	if strings.Contains(strings.ToLower(status.Name), "review") {
		return model.StatusReview
	}

	switch strings.ToLower(status.StatusCategory.Key) {
	case "new":
		return model.StatusOpen
	case "indeterminate":
		return model.StatusInProgress
	case "done":
		return model.StatusDone
	default:
		return model.StatusOpen
	}
}

// normalizePriority maps a Jira priority ID to a normalized priority level.
func normalizePriority(priority Priority) int {
	id, err := strconv.Atoi(priority.ID)
	if err != nil {
		return model.PriorityMedium
	}

	switch {
	case id <= 2:
		return model.PriorityCritical
	case id == 3:
		return model.PriorityHigh
	case id == 4:
		return model.PriorityMedium
	case id == 5:
		return model.PriorityLow
	default:
		return model.PriorityLowest
	}
}

// parseJiraTime parses a Jira timestamp string. Jira uses the format
// "2006-01-02T15:04:05.000+0000".
func parseJiraTime(s string) time.Time {
	if s == "" {
		return time.Time{}
	}

	// Try the standard Jira format with milliseconds.
	layouts := []string{
		"2006-01-02T15:04:05.000-0700",
		"2006-01-02T15:04:05.000+0000",
		"2006-01-02T15:04:05-0700",
		time.RFC3339,
	}

	for _, layout := range layouts {
		if t, err := time.Parse(layout, s); err == nil {
			return t
		}
	}

	return time.Time{}
}

// htmlTagPattern matches HTML tags for stripping.
var htmlTagPattern = regexp.MustCompile(`<[^>]*>`)

// stripHTML removes HTML tags from a string and collapses whitespace,
// providing a basic plain-text rendering for terminal display.
func stripHTML(html string) string {
	if html == "" {
		return ""
	}

	// Replace common block-level tags with newlines.
	result := html
	for _, tag := range []string{"<br>", "<br/>", "<br />", "</p>", "</div>", "</li>"} {
		result = strings.ReplaceAll(result, tag, "\n")
	}

	// Strip all remaining HTML tags.
	result = htmlTagPattern.ReplaceAllString(result, "")

	// Decode common HTML entities.
	replacer := strings.NewReplacer(
		"&amp;", "&",
		"&lt;", "<",
		"&gt;", ">",
		"&quot;", "\"",
		"&#39;", "'",
		"&nbsp;", " ",
	)
	result = replacer.Replace(result)

	// Collapse multiple consecutive blank lines.
	for strings.Contains(result, "\n\n\n") {
		result = strings.ReplaceAll(result, "\n\n\n", "\n\n")
	}

	return strings.TrimSpace(result)
}

// escapeJQL escapes special characters in a JQL text search query value.
func escapeJQL(s string) string {
	// Escape backslashes first, then double-quotes.
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return s
}
