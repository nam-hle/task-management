package bitbucket

// PullRequestPage is a paginated response of pull requests.
type PullRequestPage struct {
	Size          int           `json:"size"`
	Limit         int           `json:"limit"`
	Start         int           `json:"start"`
	IsLastPage    bool          `json:"isLastPage"`
	NextPageStart int           `json:"nextPageStart"`
	Values        []PullRequest `json:"values"`
}

// ActivityPage is a paginated response of PR activities.
type ActivityPage struct {
	Size          int        `json:"size"`
	Limit         int        `json:"limit"`
	Start         int        `json:"start"`
	IsLastPage    bool       `json:"isLastPage"`
	NextPageStart int        `json:"nextPageStart"`
	Values        []Activity `json:"values"`
}

// BuildStatusPage is a paginated response of build statuses.
type BuildStatusPage struct {
	Size          int           `json:"size"`
	Limit         int           `json:"limit"`
	Start         int           `json:"start"`
	IsLastPage    bool          `json:"isLastPage"`
	NextPageStart int           `json:"nextPageStart"`
	Values        []BuildStatus `json:"values"`
}

// PullRequest represents a Bitbucket Server pull request.
type PullRequest struct {
	ID          int                    `json:"id"`
	Title       string                 `json:"title"`
	Description string                 `json:"description"`
	State       string                 `json:"state"` // OPEN, MERGED, DECLINED
	CreatedDate int64                  `json:"createdDate"`
	UpdatedDate int64                  `json:"updatedDate"`
	FromRef     Ref                    `json:"fromRef"`
	ToRef       Ref                    `json:"toRef"`
	Author      Participant            `json:"author"`
	Reviewers   []Participant          `json:"reviewers"`
	Properties  map[string]interface{} `json:"properties,omitempty"`
}

// Ref represents a branch reference in a pull request.
type Ref struct {
	ID           string     `json:"id"`
	DisplayID    string     `json:"displayId"`
	LatestCommit string     `json:"latestCommit,omitempty"`
	Repository   Repository `json:"repository"`
}

// Repository represents a Bitbucket repository.
type Repository struct {
	Slug    string  `json:"slug"`
	Project Project `json:"project"`
}

// Project represents a Bitbucket project.
type Project struct {
	Key  string `json:"key"`
	Name string `json:"name,omitempty"`
}

// Participant represents a user's role and status on a pull request.
type Participant struct {
	User     User   `json:"user"`
	Role     string `json:"role"`     // AUTHOR, REVIEWER
	Approved bool   `json:"approved"`
	Status   string `json:"status"`   // APPROVED, UNAPPROVED, NEEDS_WORK
}

// User represents a Bitbucket user.
type User struct {
	Name        string `json:"name"`
	DisplayName string `json:"displayName"`
	Slug        string `json:"slug,omitempty"`
}

// Activity represents an event on a pull request
// (comment, approval, rescope, merge, etc.).
type Activity struct {
	ID          int              `json:"id"`
	Action      string           `json:"action"` // COMMENTED, APPROVED, RESCOPED, MERGED, etc.
	Comment     *ActivityComment `json:"comment,omitempty"`
	CreatedDate int64            `json:"createdDate"`
	User        User             `json:"user"`
}

// ActivityComment is a comment attached to a PR activity.
type ActivityComment struct {
	ID          int    `json:"id"`
	Text        string `json:"text"`
	Author      User   `json:"author"`
	CreatedDate int64  `json:"createdDate"`
	UpdatedDate int64  `json:"updatedDate"`
}

// BuildStatus represents a CI/CD build status for a commit.
type BuildStatus struct {
	State       string `json:"state"` // SUCCESSFUL, FAILED, INPROGRESS
	Key         string `json:"key"`
	Name        string `json:"name"`
	URL         string `json:"url"`
	Description string `json:"description"`
	DateAdded   int64  `json:"dateAdded"`
}

// DiffResponse is the response from the pull request diff endpoint.
type DiffResponse struct {
	Diffs     []FileDiff `json:"diffs"`
	Truncated bool       `json:"truncated"`
}

// FileDiff represents the diff for a single file.
type FileDiff struct {
	Source      *DiffPath  `json:"source,omitempty"`
	Destination *DiffPath  `json:"destination,omitempty"`
	Hunks       []DiffHunk `json:"hunks"`
}

// DiffPath identifies a file path in a diff.
type DiffPath struct {
	ToString string `json:"toString"`
}

// DiffHunk represents a contiguous block of changes in a file diff.
type DiffHunk struct {
	SourceLine      int           `json:"sourceLine"`
	SourceSpan      int           `json:"sourceSpan"`
	DestinationLine int           `json:"destinationLine"`
	DestinationSpan int           `json:"destinationSpan"`
	Segments        []DiffSegment `json:"segments"`
}

// DiffSegment groups consecutive lines of the same change type.
type DiffSegment struct {
	Type  string     `json:"type"` // CONTEXT, ADDED, REMOVED
	Lines []DiffLine `json:"lines"`
}

// DiffLine is a single line within a diff segment.
type DiffLine struct {
	Destination int    `json:"destination"`
	Source      int    `json:"source"`
	Line        int    `json:"line"`
	Text        string `json:"text"`
}

// BBErrorResponse is the Bitbucket Server error response format.
type BBErrorResponse struct {
	Errors []BBError `json:"errors"`
}

// BBError is a single error entry within a Bitbucket error response.
type BBError struct {
	Context       string `json:"context"`
	Message       string `json:"message"`
	ExceptionName string `json:"exceptionName"`
}
