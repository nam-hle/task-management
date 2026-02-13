// Package contracts/jira defines the Jira Server/DC adapter interface.
// Based on Jira REST API v2 with Personal Access Token authentication.
//
// Base URL: {baseUrl}/rest/api/2/
// Auth: Authorization: Bearer <PAT>
package contracts

// JiraAdapter extends the common Source interface with Jira-specific operations.
// All methods use the configured base URL and PAT from the source configuration.

// Key endpoints mapped to Source interface methods:
//
// ValidateConnection:
//   GET /rest/api/2/myself
//   Returns: { key, name, displayName, emailAddress }
//
// FetchItems (assigned issues):
//   POST /rest/api/2/search
//   Body: { jql: "assignee=currentUser() ORDER BY updated DESC",
//           startAt: 0, maxResults: 50,
//           fields: ["summary","status","priority","assignee","created","updated","project"] }
//   Maps to: Task { Title=summary, Status=status.name, Priority=priority.id, ... }
//
// GetItemDetail:
//   GET /rest/api/2/issue/{issueKey}?expand=renderedFields
//   Returns full issue with rendered HTML fields
//
// GetActions (transitions):
//   GET /rest/api/2/issue/{issueKey}/transitions
//   Returns: { transitions: [{ id, name, to: { name } }] }
//   Maps to: []Action where ID=transition.id, Name=transition.name
//
// ExecuteAction:
//   Transition: POST /rest/api/2/issue/{issueKey}/transitions
//               Body: { transition: { id: "actionId" } }
//   Comment:    POST /rest/api/2/issue/{issueKey}/comment
//               Body: { body: "input text" }
//
// Search:
//   POST /rest/api/2/search
//   Body: { jql: "text ~ \"{query}\" ORDER BY updated DESC", ... }
//
// Status normalization:
//   1. First check status name for review-related keywords:
//      Jira status name contains "review" (case-insensitive) -> "Review"
//   2. Then fall back to status category mapping:
//      Jira status category "new"           -> "Open"
//      Jira status category "indeterminate" -> "In Progress"
//      Jira status category "done"          -> "Done"
//
// Priority normalization:
//   Blocker (1) / Critical (2) -> 1
//   High (3)                   -> 2
//   Medium (4)                 -> 3
//   Low (5)                    -> 4
//   Lowest (6)                 -> 5
//
// Pagination:
//   Uses startAt (0-based) + maxResults. Total from response.total.
//
// Rate limiting:
//   Respect HTTP 429 with Retry-After header. Exponential backoff, max 3 retries.
//
// Error format:
//   { errorMessages: [...], errors: {...} }
//
// Note: Jira Server/DC uses wiki markup for descriptions/comments (not ADF).
//       Use renderedFields for HTML output, then convert to terminal text.
