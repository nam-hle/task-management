package bitbucket

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/nhle/task-management/internal/crossref"
	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source"
)

// Adapter implements source.Source for Bitbucket Server/DC.
type Adapter struct {
	client   *Client
	baseURL  string
	sourceID string
}

// NewAdapter creates a new Bitbucket source adapter.
func NewAdapter(baseURL, token, sourceID string) *Adapter {
	return &Adapter{
		client:   NewClient(baseURL, token),
		baseURL:  strings.TrimRight(baseURL, "/"),
		sourceID: sourceID,
	}
}

// Type returns the source type identifier for Bitbucket.
func (a *Adapter) Type() source.SourceType {
	return source.SourceTypeBitbucket
}

// ValidateConnection verifies credentials by calling the whoami
// endpoint and then fetching the user's display name.
func (a *Adapter) ValidateConnection(
	ctx context.Context,
) (string, error) {
	username, err := a.client.GetRaw(
		ctx, "/plugins/servlet/applinks/whoami",
	)
	if err != nil {
		return "", fmt.Errorf(
			"validating Bitbucket connection: %w", err,
		)
	}

	if username == "" {
		return "", fmt.Errorf(
			"whoami returned empty username; token may be invalid",
		)
	}

	var user User
	userPath := fmt.Sprintf("/rest/api/1.0/users/%s", username)
	if err := a.client.Get(ctx, userPath, &user); err != nil {
		// If user lookup fails, fall back to the username.
		return username, nil
	}

	if user.DisplayName != "" {
		return user.DisplayName, nil
	}
	return username, nil
}

// FetchItems retrieves pull requests from the Bitbucket inbox for
// both REVIEWER and AUTHOR roles, deduplicating by PR ID.
func (a *Adapter) FetchItems(
	ctx context.Context,
	opts source.FetchOptions,
) (*source.FetchResult, error) {
	pageSize := opts.PageSize
	if pageSize < 1 {
		pageSize = 25
	}

	// Fetch PRs where user is a reviewer.
	reviewerPRs, err := a.client.GetAllPRPages(
		ctx,
		"/rest/api/1.0/inbox/pull-requests?role=REVIEWER",
		pageSize,
	)
	if err != nil {
		return nil, fmt.Errorf("fetching reviewer PRs: %w", err)
	}

	// Fetch PRs where user is the author.
	authorPRs, err := a.client.GetAllPRPages(
		ctx,
		"/rest/api/1.0/inbox/pull-requests?role=AUTHOR",
		pageSize,
	)
	if err != nil {
		return nil, fmt.Errorf("fetching author PRs: %w", err)
	}

	// Merge and deduplicate by composite key (project/repo/prID).
	seen := make(map[string]bool)
	var merged []PullRequest

	for _, prs := range [][]PullRequest{reviewerPRs, authorPRs} {
		for _, pr := range prs {
			key := prCompositeKey(pr)
			if seen[key] {
				continue
			}
			seen[key] = true
			merged = append(merged, pr)
		}
	}

	tasks := make([]model.Task, 0, len(merged))
	for _, pr := range merged {
		tasks = append(tasks, a.prToTask(pr))
	}

	return &source.FetchResult{
		Items:   tasks,
		Total:   len(tasks),
		HasMore: false,
	}, nil
}

// GetItemDetail retrieves full details for a single pull request,
// including activities (comments/approvals), build status, and diff.
func (a *Adapter) GetItemDetail(
	ctx context.Context,
	sourceItemID string,
) (*source.ItemDetail, error) {
	projectKey, repoSlug, prID, err := parseSourceItemID(sourceItemID)
	if err != nil {
		return nil, err
	}

	basePath := fmt.Sprintf(
		"/rest/api/1.0/projects/%s/repos/%s/pull-requests/%d",
		projectKey, repoSlug, prID,
	)

	// Fetch the PR itself.
	var pr PullRequest
	if err := a.client.Get(ctx, basePath, &pr); err != nil {
		return nil, fmt.Errorf(
			"fetching PR %s: %w", sourceItemID, err,
		)
	}

	task := a.prToTask(pr)

	// Fetch activities (comments and approvals).
	activities, err := a.client.GetAllActivityPages(
		ctx, basePath+"/activities", 25,
	)
	if err != nil {
		// Non-fatal: we still have the PR data.
		activities = nil
	}

	var comments []source.Comment
	for _, act := range activities {
		if act.Action == "COMMENTED" && act.Comment != nil {
			comments = append(comments, source.Comment{
				Author: act.Comment.Author.DisplayName,
				Body:   act.Comment.Text,
				CreatedAt: epochMsToTime(
					act.Comment.CreatedDate,
				).Format("2006-01-02 15:04"),
			})
		}
	}

	// Build metadata.
	metadata := make(map[string]string)
	metadata["Source Branch"] = pr.FromRef.DisplayID
	metadata["Target Branch"] = pr.ToRef.DisplayID
	metadata["Repository"] = fmt.Sprintf(
		"%s/%s", pr.FromRef.Repository.Project.Key,
		pr.FromRef.Repository.Slug,
	)

	// Reviewers summary.
	if len(pr.Reviewers) > 0 {
		var reviewerParts []string
		for _, r := range pr.Reviewers {
			status := r.Status
			if status == "" {
				status = "UNAPPROVED"
			}
			reviewerParts = append(
				reviewerParts,
				fmt.Sprintf("%s (%s)", r.User.DisplayName, status),
			)
		}
		metadata["Reviewers"] = strings.Join(reviewerParts, ", ")
	}

	// Fetch build status from the source branch's latest commit.
	if pr.FromRef.LatestCommit != "" {
		buildPath := fmt.Sprintf(
			"/rest/build-status/1.0/commits/%s",
			pr.FromRef.LatestCommit,
		)
		var buildPage BuildStatusPage
		if err := a.client.Get(ctx, buildPath, &buildPage); err == nil {
			var buildParts []string
			for _, b := range buildPage.Values {
				buildParts = append(
					buildParts,
					fmt.Sprintf("%s: %s", b.Name, b.State),
				)
			}
			if len(buildParts) > 0 {
				metadata["Build Status"] = strings.Join(
					buildParts, ", ",
				)
			}
		}
	}

	// Fetch diff summary.
	diffPath := basePath + "/diff"
	var diffResp DiffResponse
	if err := a.client.Get(ctx, diffPath, &diffResp); err == nil {
		diffSummary := renderDiffSummary(diffResp)
		if diffSummary != "" {
			metadata["Files Changed"] = diffSummary
		}
	}

	// Render the body: description + diff detail.
	renderedBody := pr.Description
	diffDetail := renderDiffDetail(diffResp)
	if diffDetail != "" {
		if renderedBody != "" {
			renderedBody += "\n\n"
		}
		renderedBody += diffDetail
	}

	// Extract cross-references to Jira issues.
	jiraKeys := crossref.MatchCrossRefs(
		pr.FromRef.DisplayID,
		pr.Title,
		pr.Description,
		nil,
	)
	if len(jiraKeys) > 0 {
		metadata["Jira References"] = strings.Join(jiraKeys, ", ")
		task.CrossRefs = jiraKeys
	}

	return &source.ItemDetail{
		Task:         task,
		RenderedBody: renderedBody,
		Metadata:     metadata,
		Comments:     comments,
	}, nil
}

// GetActions returns the available actions for a Bitbucket pull request.
func (a *Adapter) GetActions(
	ctx context.Context,
	sourceItemID string,
) ([]source.Action, error) {
	return []source.Action{
		{
			ID:   "approve",
			Name: "Approve",
		},
		{
			ID:   "unapprove",
			Name: "Unapprove",
		},
		{
			ID:            "comment",
			Name:          "Add Comment",
			RequiresInput: true,
			InputPrompt:   "Enter comment text:",
		},
	}, nil
}

// ExecuteAction performs an action on a Bitbucket pull request.
func (a *Adapter) ExecuteAction(
	ctx context.Context,
	sourceItemID string,
	action source.Action,
	input string,
) error {
	projectKey, repoSlug, prID, err := parseSourceItemID(sourceItemID)
	if err != nil {
		return err
	}

	basePath := fmt.Sprintf(
		"/rest/api/1.0/projects/%s/repos/%s/pull-requests/%d",
		projectKey, repoSlug, prID,
	)

	switch action.ID {
	case "approve":
		return a.client.Post(
			ctx, basePath+"/approve", nil, nil,
		)

	case "unapprove":
		return a.client.Delete(
			ctx, basePath+"/approve", nil,
		)

	case "comment":
		payload := map[string]string{"text": input}
		return a.client.Post(
			ctx, basePath+"/comments", payload, nil,
		)

	default:
		return fmt.Errorf(
			"unknown action %q for PR %s", action.ID, sourceItemID,
		)
	}
}

// Search is not well supported by Bitbucket Server's REST API.
// Returns empty results.
func (a *Adapter) Search(
	ctx context.Context,
	query string,
	opts source.FetchOptions,
) (*source.FetchResult, error) {
	return &source.FetchResult{
		Items:   nil,
		Total:   0,
		HasMore: false,
	}, nil
}

// prToTask converts a Bitbucket PullRequest to a model.Task.
func (a *Adapter) prToTask(pr PullRequest) model.Task {
	rawData, _ := json.Marshal(pr)

	projectKey := pr.FromRef.Repository.Project.Key
	repoSlug := pr.FromRef.Repository.Slug
	sourceItemID := fmt.Sprintf(
		"%s/%s/%d", projectKey, repoSlug, pr.ID,
	)

	return model.Task{
		ID: fmt.Sprintf(
			"bb-%s-%s-%d", projectKey, repoSlug, pr.ID,
		),
		SourceType:   model.SourceTypeBitbucket,
		SourceItemID: sourceItemID,
		SourceID:     a.sourceID,
		Title:        pr.Title,
		Description:  pr.Description,
		Status:       normalizeState(pr.State),
		Priority:     normalizePRPriority(pr),
		Assignee:     pr.Author.User.DisplayName,
		Author:       pr.Author.User.DisplayName,
		SourceURL: fmt.Sprintf(
			"%s/projects/%s/repos/%s/pull-requests/%d",
			a.baseURL, projectKey, repoSlug, pr.ID,
		),
		CreatedAt: epochMsToTime(pr.CreatedDate),
		UpdatedAt: epochMsToTime(pr.UpdatedDate),
		FetchedAt: time.Now(),
		RawData:   string(rawData),
	}
}

// normalizeState maps Bitbucket PR state to a normalized status.
func normalizeState(state string) string {
	switch strings.ToUpper(state) {
	case "OPEN":
		return model.StatusOpen
	case "MERGED":
		return model.StatusDone
	case "DECLINED":
		return model.StatusDone
	default:
		return model.StatusOpen
	}
}

// normalizePRPriority determines priority based on reviewer statuses.
// Needs work / changes requested = High (2),
// Needs review (no approvals) = Medium (3),
// Approved = Low (4).
func normalizePRPriority(pr PullRequest) int {
	if len(pr.Reviewers) == 0 {
		return model.PriorityMedium
	}

	hasApproval := false
	for _, r := range pr.Reviewers {
		if strings.EqualFold(r.Status, "NEEDS_WORK") {
			return model.PriorityHigh
		}
		if strings.EqualFold(r.Status, "APPROVED") {
			hasApproval = true
		}
	}

	if hasApproval {
		return model.PriorityLow
	}
	return model.PriorityMedium
}

// epochMsToTime converts a Unix epoch millisecond timestamp to time.Time.
func epochMsToTime(ms int64) time.Time {
	if ms == 0 {
		return time.Time{}
	}
	return time.UnixMilli(ms)
}

// prCompositeKey returns a deduplication key for a pull request.
func prCompositeKey(pr PullRequest) string {
	return fmt.Sprintf(
		"%s/%s/%d",
		pr.FromRef.Repository.Project.Key,
		pr.FromRef.Repository.Slug,
		pr.ID,
	)
}

// parseSourceItemID splits "PROJECT/repo-slug/123" into its parts.
func parseSourceItemID(id string) (
	projectKey string,
	repoSlug string,
	prID int,
	err error,
) {
	parts := strings.SplitN(id, "/", 3)
	if len(parts) != 3 {
		return "", "", 0, fmt.Errorf(
			"invalid Bitbucket sourceItemID %q: "+
				"expected PROJECT/repo-slug/prID", id,
		)
	}

	prID, err = strconv.Atoi(parts[2])
	if err != nil {
		return "", "", 0, fmt.Errorf(
			"invalid PR ID in sourceItemID %q: %w", id, err,
		)
	}

	return parts[0], parts[1], prID, nil
}

// renderDiffSummary produces a concise summary of changed files.
func renderDiffSummary(diff DiffResponse) string {
	if len(diff.Diffs) == 0 {
		return ""
	}

	fileCount := len(diff.Diffs)
	added := 0
	removed := 0

	for _, fd := range diff.Diffs {
		for _, hunk := range fd.Hunks {
			for _, seg := range hunk.Segments {
				for range seg.Lines {
					switch seg.Type {
					case "ADDED":
						added++
					case "REMOVED":
						removed++
					}
				}
			}
		}
	}

	summary := fmt.Sprintf(
		"%d file(s), +%d/-%d lines", fileCount, added, removed,
	)
	if diff.Truncated {
		summary += " (truncated)"
	}
	return summary
}

// renderDiffDetail produces a text rendering of the diff hunks for
// display in the detail view.
func renderDiffDetail(diff DiffResponse) string {
	if len(diff.Diffs) == 0 {
		return ""
	}

	var b strings.Builder
	b.WriteString("--- Diff ---\n")

	for _, fd := range diff.Diffs {
		srcName := "(new file)"
		if fd.Source != nil {
			srcName = fd.Source.ToString
		}
		dstName := "(deleted)"
		if fd.Destination != nil {
			dstName = fd.Destination.ToString
		}

		b.WriteString(fmt.Sprintf(
			"\n--- a/%s\n+++ b/%s\n", srcName, dstName,
		))

		for _, hunk := range fd.Hunks {
			b.WriteString(fmt.Sprintf(
				"@@ -%d,%d +%d,%d @@\n",
				hunk.SourceLine, hunk.SourceSpan,
				hunk.DestinationLine, hunk.DestinationSpan,
			))

			for _, seg := range hunk.Segments {
				prefix := " "
				switch seg.Type {
				case "ADDED":
					prefix = "+"
				case "REMOVED":
					prefix = "-"
				}
				for _, line := range seg.Lines {
					b.WriteString(prefix + line.Text + "\n")
				}
			}
		}
	}

	return b.String()
}
