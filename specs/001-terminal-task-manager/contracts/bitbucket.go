// Package contracts/bitbucket defines the Bitbucket Server/DC adapter interface.
// Based on Bitbucket Server REST API v1.0 with Personal Access Token authentication.
//
// Base URL: {baseUrl}/rest/api/1.0/
// Auth: Authorization: Bearer <PAT>
package contracts

// BitbucketAdapter extends the common Source interface with Bitbucket-specific operations.

// Key endpoints mapped to Source interface methods:
//
// ValidateConnection:
//   GET /plugins/servlet/applinks/whoami
//   Returns: plain text username
//   Then: GET /rest/api/1.0/users/{username} for display name
//
// FetchItems (inbox PRs):
//   GET /rest/api/1.0/inbox/pull-requests?role=REVIEWER&start=0&limit=25
//   GET /rest/api/1.0/inbox/pull-requests?role=AUTHOR&start=0&limit=25
//   Maps to: Task { Title=pr.title, Status=pr.state, SourceURL=pr.links.self }
//   Priority based on: changes requested (2), needs review (3), approved (4)
//
// GetItemDetail:
//   GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{prId}
//   Additional calls:
//     GET .../pull-requests/{prId}/activities  (comments, approvals)
//     GET /rest/build-status/1.0/commits/{latestCommitHash}  (build status)
//
// GetActions:
//   Returns static actions based on PR state and user role:
//   - Reviewer: Approve, Unapprove, Comment
//   - Author: Comment
//
// ExecuteAction:
//   Approve:   POST .../pull-requests/{prId}/approve  (no body)
//   Unapprove: DELETE .../pull-requests/{prId}/approve
//   Comment:   POST .../pull-requests/{prId}/comments  Body: { text: "input" }
//
// Search:
//   No native full-text search across repos. Filter inbox by iterating cached items.
//
// Status normalization:
//   OPEN     -> "Open"
//   MERGED   -> "Done"
//   DECLINED -> "Done"
//
// Pagination:
//   Uses start (0-based) + limit. Use response.nextPageStart for next page.
//   Check response.isLastPage to stop.
//
// Rate limiting:
//   HTTP 429 with Retry-After. Same backoff strategy as Jira.
//
// Cross-referencing:
//   Extract Jira issue keys from PR branch name (fromRef.displayId),
//   title, and description using regex: ([A-Z][A-Z0-9]+-\d+)
//
// Note: Bitbucket uses Markdown for comments (not wiki markup like Jira).
//       Timestamps are Unix epoch milliseconds (not ISO 8601).
