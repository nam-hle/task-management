package jira

// SearchResponse is the response from POST /rest/api/2/search.
type SearchResponse struct {
	StartAt    int     `json:"startAt"`
	MaxResults int     `json:"maxResults"`
	Total      int     `json:"total"`
	Issues     []Issue `json:"issues"`
}

// Issue represents a single Jira issue from the REST API.
type Issue struct {
	ID     string      `json:"id"`
	Key    string      `json:"key"`
	Self   string      `json:"self"`
	Fields IssueFields `json:"fields"`
	// When expand=renderedFields
	RenderedFields *RenderedFields `json:"renderedFields,omitempty"`
	// When expand=transitions
	Transitions []Transition `json:"transitions,omitempty"`
}

// IssueFields contains the standard fields of a Jira issue.
type IssueFields struct {
	Summary     string       `json:"summary"`
	Status      Status       `json:"status"`
	Priority    Priority     `json:"priority"`
	IssueType   IssueType    `json:"issuetype"`
	Assignee    *User        `json:"assignee"`
	Reporter    *User        `json:"reporter"`
	Project     Project      `json:"project"`
	Created     string       `json:"created"`
	Updated     string       `json:"updated"`
	DueDate     string       `json:"duedate,omitempty"`
	Labels      []string     `json:"labels,omitempty"`
	Description string       `json:"description,omitempty"`
	Comment     *CommentPage `json:"comment,omitempty"`
}

// RenderedFields holds HTML-rendered versions of issue fields.
type RenderedFields struct {
	Description string `json:"description"`
}

// Status represents the status of a Jira issue.
type Status struct {
	Name           string         `json:"name"`
	ID             string         `json:"id"`
	StatusCategory StatusCategory `json:"statusCategory"`
}

// StatusCategory is the broad category a status belongs to.
type StatusCategory struct {
	Key  string `json:"key"`
	Name string `json:"name"`
}

// Priority represents the priority level of a Jira issue.
type Priority struct {
	Name string `json:"name"`
	ID   string `json:"id"`
}

// IssueType represents the type of a Jira issue (Bug, Story, etc.).
type IssueType struct {
	Name string `json:"name"`
	ID   string `json:"id"`
}

// User represents a Jira user.
type User struct {
	Key          string `json:"key"`
	Name         string `json:"name"`
	DisplayName  string `json:"displayName"`
	EmailAddress string `json:"emailAddress"`
}

// Project represents a Jira project.
type Project struct {
	Key  string `json:"key"`
	Name string `json:"name"`
}

// Transition represents a possible status transition for a Jira issue.
type Transition struct {
	ID   string       `json:"id"`
	Name string       `json:"name"`
	To   TransitionTo `json:"to"`
}

// TransitionTo describes the target status of a transition.
type TransitionTo struct {
	Name           string         `json:"name"`
	ID             string         `json:"id"`
	StatusCategory StatusCategory `json:"statusCategory"`
}

// Comment represents a single comment on a Jira issue.
type Comment struct {
	ID      string `json:"id"`
	Body    string `json:"body"`
	Author  User   `json:"author"`
	Created string `json:"created"`
	Updated string `json:"updated"`
}

// CommentPage holds a paginated list of comments.
type CommentPage struct {
	Comments   []Comment `json:"comments"`
	MaxResults int       `json:"maxResults"`
	Total      int       `json:"total"`
	StartAt    int       `json:"startAt"`
}

// Myself is the response from GET /rest/api/2/myself.
type Myself struct {
	Key          string `json:"key"`
	Name         string `json:"name"`
	DisplayName  string `json:"displayName"`
	EmailAddress string `json:"emailAddress"`
	Active       bool   `json:"active"`
}

// ErrorResponse is the standard Jira error response format.
type ErrorResponse struct {
	ErrorMessages []string          `json:"errorMessages"`
	Errors        map[string]string `json:"errors"`
}

// TransitionsResponse wraps the list of transitions returned by the API.
type TransitionsResponse struct {
	Transitions []Transition `json:"transitions"`
}
