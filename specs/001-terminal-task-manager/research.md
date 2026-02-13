# Research: Terminal Task Manager

**Feature**: 001-terminal-task-manager
**Date**: 2026-02-13

---

## Technology Decision: Go + Bubble Tea

**Decision**: Go 1.22+ with the Charm ecosystem

**Rationale**: k9s itself is Go; Bubble Tea's Elm Architecture handles complex multi-source state cleanly; single binary distribution is critical for developer tools; goroutines map perfectly to concurrent source polling; Charm ecosystem (Lip Gloss, Bubbles, Huh, Glamour) is the most cohesive TUI toolkit available.

**Alternatives considered**:

| Stack | Pros | Cons | Verdict |
|-------|------|------|---------|
| TypeScript + Ink | User's primary language, official Claude SDK, rich npm ecosystem | Ink struggles with k9s-style layouts, needs custom virtualization, 4-8x slower startup, Node.js runtime required | Rejected: TUI quality ceiling too low |
| Rust + Ratatui | Best performance, single binary, excellent type safety | No Jira/BB/Claude client libraries, 2x dev time, steepest learning curve | Rejected: Integration layer too costly |
| Go + tview | What k9s uses, built-in Flex/Grid layouts | Callback-based state management, harder to test, less active development | Considered but Bubble Tea's architecture scales better |

**Key library decisions**: See [plan.md](./plan.md) for the complete library table.

---

## 1. Jira Server / Data Center REST API

### 1.1 Base URL & Versioning

```
{protocol}://{host}:{port}/rest/api/2/{resource}
```

- **Current stable version**: `2` (used by both Jira Server and Data Center)
- There is also a `/rest/api/latest/` alias that resolves to the latest version, but
  pinning to `/rest/api/2/` is recommended for stability.
- The context path may differ if Jira runs behind a reverse proxy or uses a non-root
  context (e.g., `https://jira.example.com/jira/rest/api/2/...`). The base URL should
  be user-configurable.

**Example**: `https://jira.corp.example.com/rest/api/2/search`

### 1.2 Authentication: Personal Access Tokens (PAT)

Personal Access Tokens were introduced in **Jira Data Center 8.14** and **Jira Server 8.14+**.

**Header format**:
```
Authorization: Bearer <token>
```

- The token is passed as a standard HTTP Bearer token in the `Authorization` header.
- No username is required; the token is tied to the user who created it.
- Tokens inherit the permissions of the creating user.
- Tokens can be created in: User Profile > Personal Access Tokens.
- Tokens do not expire by default, but administrators can enforce expiration policies.

**Fallback authentication** (for older instances without PAT support):
- Basic Auth: `Authorization: Basic <base64(username:password)>`
- This should be supported as a fallback but PAT is the primary method per the spec.

**Request headers** (all requests):
```
Authorization: Bearer <token>
Content-Type: application/json
Accept: application/json
```

### 1.3 Key Endpoints

#### 1.3.1 Search Issues (JQL)

```
GET /rest/api/2/search
POST /rest/api/2/search
```

**Query parameters (GET) / JSON body (POST)**:

| Parameter     | Type   | Description                                          |
|---------------|--------|------------------------------------------------------|
| `jql`         | string | JQL query string                                     |
| `startAt`     | int    | 0-based index of first result (default: 0)           |
| `maxResults`  | int    | Max results to return (default: 50, max: 1000)       |
| `fields`      | string | Comma-separated field names to include               |
| `expand`      | string | Extra data to include (e.g., `renderedFields`, `changelog`) |
| `validateQuery`| string | `strict`, `warn`, or `none`                         |

**Recommended fields for list view**:
```
fields=summary,status,priority,assignee,issuetype,project,created,updated,labels,duedate
```

**Example JQL queries for the app**:
```
# Issues assigned to the current user
assignee = currentUser() ORDER BY updated DESC

# Issues assigned + unresolved
assignee = currentUser() AND resolution = Unresolved ORDER BY priority DESC, updated DESC

# Free-text search
text ~ "search term" AND assignee = currentUser()

# Filter by project
project = "PROJ" AND assignee = currentUser() ORDER BY updated DESC
```

**Response shape** (abbreviated):
```json
{
  "startAt": 0,
  "maxResults": 50,
  "total": 245,
  "issues": [
    {
      "id": "10001",
      "key": "PROJ-123",
      "self": "https://jira.example.com/rest/api/2/issue/10001",
      "fields": {
        "summary": "Fix login timeout",
        "status": {
          "name": "In Progress",
          "id": "3",
          "statusCategory": { "key": "indeterminate", "name": "In Progress" }
        },
        "priority": { "name": "High", "id": "2" },
        "issuetype": { "name": "Bug", "id": "1" },
        "assignee": { "displayName": "John Doe", "key": "jdoe" },
        "project": { "key": "PROJ", "name": "My Project" },
        "created": "2026-02-10T09:15:00.000+0000",
        "updated": "2026-02-12T14:30:00.000+0000",
        "duedate": "2026-02-20",
        "labels": ["backend", "urgent"]
      }
    }
  ]
}
```

**Note**: Use `POST /rest/api/2/search` for long/complex JQL queries to avoid URL length
limits. The body is JSON: `{ "jql": "...", "startAt": 0, "maxResults": 50, "fields": [...] }`.

#### 1.3.2 Get Issue Details

```
GET /rest/api/2/issue/{issueIdOrKey}
```

**Query parameters**:

| Parameter | Type   | Description                                         |
|-----------|--------|-----------------------------------------------------|
| `fields`  | string | Comma-separated fields (use `*all` for everything)  |
| `expand`  | string | `renderedFields,transitions,changelog,names`        |

**Example**:
```
GET /rest/api/2/issue/PROJ-123?fields=*all&expand=renderedFields,transitions
```

**Response includes**:
- `fields.summary`, `fields.description` (wiki markup or ADF depending on version)
- `fields.status`, `fields.priority`, `fields.issuetype`
- `fields.assignee`, `fields.reporter`
- `fields.comment` (with `fields` including comment)
- `fields.attachment`, `fields.subtasks`
- `fields.issuelinks` (linked issues, including links to other Jira issues)
- `renderedFields.description` (HTML-rendered description, if `expand=renderedFields`)
- `transitions` (available transitions, if `expand=transitions`)

**Description rendering**: Jira Server uses **wiki markup** by default. Newer Data Center
versions may use ADF (Atlassian Document Format). The `renderedFields` expansion returns
HTML which can be converted to terminal-friendly text.

#### 1.3.3 Get Transitions

```
GET /rest/api/2/issue/{issueIdOrKey}/transitions
```

**Query parameters**:

| Parameter     | Type   | Description                                   |
|---------------|--------|-----------------------------------------------|
| `expand`      | string | `transitions.fields` to get required fields   |

**Response**:
```json
{
  "transitions": [
    {
      "id": "21",
      "name": "Start Progress",
      "to": {
        "name": "In Progress",
        "id": "3",
        "statusCategory": { "key": "indeterminate" }
      },
      "hasScreen": false,
      "fields": {}
    },
    {
      "id": "31",
      "name": "Done",
      "to": {
        "name": "Done",
        "id": "10001",
        "statusCategory": { "key": "done" }
      },
      "hasScreen": true,
      "fields": {
        "resolution": { "required": true, "allowedValues": [...] }
      }
    }
  ]
}
```

**Important**: Transitions with `hasScreen: true` may require additional fields (like
resolution). The `fields` object describes what must be submitted with the transition.

#### 1.3.4 Perform Transition

```
POST /rest/api/2/issue/{issueIdOrKey}/transitions
```

**Request body**:
```json
{
  "transition": {
    "id": "21"
  },
  "fields": {
    "resolution": { "name": "Done" }
  },
  "update": {
    "comment": [
      {
        "add": {
          "body": "Transitioning via terminal task manager"
        }
      }
    ]
  }
}
```

- `transition.id` is required (obtained from GET transitions).
- `fields` is required if the transition has mandatory fields (e.g., resolution).
- `update.comment` is optional; allows adding a comment during the transition.
- **Response**: `204 No Content` on success.

#### 1.3.5 Add Comment

```
POST /rest/api/2/issue/{issueIdOrKey}/comment
```

**Request body**:
```json
{
  "body": "This is a comment added from the terminal task manager."
}
```

**Response** (201 Created):
```json
{
  "id": "10050",
  "body": "This is a comment added from the terminal task manager.",
  "author": { "displayName": "John Doe", "key": "jdoe" },
  "created": "2026-02-13T10:30:00.000+0000",
  "updated": "2026-02-13T10:30:00.000+0000"
}
```

**Note on formatting**: Comment body uses Jira wiki markup on Server/DC (not Markdown).
Key differences from Markdown:
- Bold: `*bold*` (not `**bold**`)
- Italic: `_italic_` (not `*italic*`)
- Code: `{{code}}` (not `` `code` ``)
- Code block: `{code}...{code}` (not triple backticks)
- Links: `[text|url]` (not `[text](url)`)
- Headers: `h1.`, `h2.`, etc. (not `#`, `##`)

For simplicity, the app could accept plain text comments and skip formatting.

#### 1.3.6 Get Assigned Issues (Current User)

```
GET /rest/api/2/search?jql=assignee%3DcurrentUser()%20AND%20resolution%3DUnresolved%20ORDER%20BY%20updated%20DESC&fields=summary,status,priority,issuetype,project,created,updated,duedate,labels
```

The `currentUser()` JQL function resolves based on the authenticated token.

#### 1.3.7 Get Current User

```
GET /rest/api/2/myself
```

Returns the authenticated user's profile. Useful for configuration validation and
displaying the logged-in user identity.

**Response**:
```json
{
  "key": "jdoe",
  "name": "jdoe",
  "displayName": "John Doe",
  "emailAddress": "jdoe@example.com",
  "active": true
}
```

### 1.4 Pagination

Jira Server uses **offset-based pagination**:

| Field        | Description                              |
|--------------|------------------------------------------|
| `startAt`    | 0-based offset of first result           |
| `maxResults` | Number of results per page (max 1000)    |
| `total`      | Total number of matching results         |

**Algorithm**:
```
page = 0
do:
  response = GET /rest/api/2/search?startAt={page * pageSize}&maxResults={pageSize}
  process(response.issues)
  page++
while (page * pageSize < response.total)
```

**Gotcha**: The `total` value can change between requests if issues are created/updated
during pagination. Use it as an approximation. Stop iterating when the returned issues
array is empty.

**Recommended page size**: 50 (the default). Going higher reduces HTTP round trips but
increases response time and memory usage.

### 1.5 Rate Limiting

Jira Server/Data Center does **not** have built-in REST API rate limiting by default.
However:

- **Administrators can configure rate limiting** via the `Rate Limiting` feature
  (introduced in Jira DC 8.0+). When enabled, limits are per-user.
- When rate-limited, the server returns **HTTP 429 Too Many Requests**.
- Response headers when rate limiting is active:
  ```
  Retry-After: <seconds>
  X-RateLimit-Limit: <max-requests>
  X-RateLimit-Remaining: <remaining>
  X-RateLimit-Reset: <epoch-seconds>
  ```
- **Recommendation**: Implement exponential backoff on 429 responses. Default behavior:
  wait for `Retry-After` seconds, then retry. Cap at 3 retries.
- Even without rate limiting, be respectful: avoid hammering the server with parallel
  requests. Use a concurrency limit of 2-3 concurrent requests.

### 1.6 Gotchas: Jira Server/DC vs Jira Cloud

| Aspect | Server/DC | Cloud |
|--------|-----------|-------|
| **Base URL** | `/rest/api/2/` | `/rest/api/3/` (also supports `/2`) |
| **Auth** | PAT (`Bearer`) or Basic Auth | OAuth 2.0 or API Token (Basic with email + token) |
| **User identifier** | `key` field (e.g., `jdoe`) | `accountId` (GUID-like string) |
| **Description format** | Wiki markup (plain text) | ADF (Atlassian Document Format, JSON) |
| **Comment format** | Wiki markup string | ADF JSON document |
| **`currentUser()` JQL** | Works with PAT | Works with OAuth/API token |
| **Rate limiting** | Admin-configured, often absent | Always active, strict limits |
| **Webhooks** | Available but self-hosted | Managed by Atlassian |
| **Permissions** | Based on user's PAT permissions | Scoped OAuth permissions |
| **Custom fields** | `customfield_NNNNN` | Same but different field IDs per instance |
| **API deprecation** | Stable, rarely changes | Aggressive deprecation cycle |

**Key design implication**: Our adapter should use `key` (not `accountId`) for user
references, and handle wiki markup (not ADF) for description/comment rendering.

### 1.7 Error Responses

Standard HTTP error format:
```json
{
  "errorMessages": ["Issue does not exist or you do not have permission to see it."],
  "errors": {}
}
```

| Status | Meaning                                    |
|--------|--------------------------------------------|
| 400    | Bad request (invalid JQL, missing fields)  |
| 401    | Authentication failed (bad/expired token)  |
| 403    | Permission denied                          |
| 404    | Resource not found                         |
| 429    | Rate limited (if configured)               |
| 500    | Server error                               |

---

## 2. Bitbucket Server REST API

### 2.1 Base URL & Versioning

```
{protocol}://{host}:{port}/rest/api/1.0/{resource}
```

- **Current stable version**: `1.0`
- There is also a newer `2.0` API for some endpoints, but `1.0` remains the primary
  and most complete API for Bitbucket Server/Data Center.
- Like Jira, the context path may be customized (e.g., `/bitbucket/rest/api/1.0/...`).
  The base URL should be user-configurable.

**Example**: `https://bitbucket.corp.example.com/rest/api/1.0/inbox/pull-requests`

**Additional API namespaces**:
- **Build status**: `/rest/build-status/1.0/...`
- **Branch utils**: `/rest/branch-utils/1.0/...`
- **Comment likes**: `/rest/comment-likes/1.0/...`

### 2.2 Authentication: Personal Access Tokens (PAT)

Personal Access Tokens are supported in **Bitbucket Server 5.5+** and **Bitbucket Data
Center 5.5+**.

**Header format**:
```
Authorization: Bearer <token>
```

- Same Bearer token pattern as Jira.
- Tokens are created in: User avatar > Manage account > Personal access tokens.
- Token permissions: `PROJECT_READ`, `PROJECT_WRITE`, `REPO_READ`, `REPO_WRITE`, etc.
- For our use case, the token needs: `REPO_READ`, `REPO_WRITE` (for approvals/comments),
  and `PROJECT_READ`.

**Request headers** (all requests):
```
Authorization: Bearer <token>
Content-Type: application/json
Accept: application/json
```

### 2.3 Key Endpoints

#### 2.3.1 List Pull Requests (Dashboard / Inbox)

**User's PR inbox** (PRs the user is involved with):
```
GET /rest/api/1.0/inbox/pull-requests
```

| Parameter | Type   | Description                                      |
|-----------|--------|--------------------------------------------------|
| `role`    | string | `AUTHOR`, `REVIEWER`, or omit for all            |
| `start`   | int   | 0-based page start                               |
| `limit`   | int   | Page size (default 25, max 100)                  |

**PRs in a specific repository**:
```
GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests
```

| Parameter     | Type   | Description                                      |
|---------------|--------|--------------------------------------------------|
| `state`       | string | `OPEN`, `MERGED`, `DECLINED`, `ALL` (default: OPEN) |
| `direction`   | string | `INCOMING` or `OUTGOING`                         |
| `at`          | string | Ref to filter by (branch)                        |
| `order`       | string | `NEWEST` or `OLDEST`                             |
| `withAttributes` | bool | Include PR attributes                          |
| `withProperties` | bool | Include PR properties                          |
| `start`       | int    | Pagination start                                 |
| `limit`       | int    | Pagination limit                                 |

**Filtering by author/reviewer on a repo**:
```
# PRs authored by a specific user
GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests?author.username={username}&state=OPEN

# PRs where user is a reviewer
GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests?reviewer.username={username}&state=OPEN
```

**Inbox approach** (recommended for the unified dashboard):
The `/inbox/pull-requests` endpoint is ideal because it returns PRs across all repos
where the user is involved, without needing to enumerate repos.

**Response shape** (abbreviated):
```json
{
  "size": 25,
  "limit": 25,
  "start": 0,
  "isLastPage": false,
  "nextPageStart": 25,
  "values": [
    {
      "id": 101,
      "title": "PROJ-123: Fix login timeout issue",
      "description": "Fixes the session timeout bug...",
      "state": "OPEN",
      "createdDate": 1707820800000,
      "updatedDate": 1707907200000,
      "fromRef": {
        "id": "refs/heads/feature/PROJ-123-fix-login-timeout",
        "displayId": "feature/PROJ-123-fix-login-timeout",
        "repository": {
          "slug": "my-repo",
          "project": { "key": "PROJ" }
        }
      },
      "toRef": {
        "id": "refs/heads/main",
        "displayId": "main"
      },
      "author": {
        "user": { "name": "jdoe", "displayName": "John Doe" },
        "role": "AUTHOR",
        "approved": false
      },
      "reviewers": [
        {
          "user": { "name": "jsmith", "displayName": "Jane Smith" },
          "role": "REVIEWER",
          "approved": true,
          "status": "APPROVED"
        }
      ],
      "properties": {
        "mergeResult": { "outcome": "CLEAN" },
        "resolvedTaskCount": 2,
        "openTaskCount": 0,
        "commentCount": 5
      }
    }
  ]
}
```

#### 2.3.2 Get PR Details

```
GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{pullRequestId}
```

Returns the full PR object (same shape as list item but with all fields populated).

#### 2.3.3 Get PR Diff

```
GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{pullRequestId}/diff
```

| Parameter     | Type   | Description                                      |
|---------------|--------|--------------------------------------------------|
| `contextLines`| int    | Number of context lines around changes (default 10) |
| `withComments`| bool   | Include inline comments in diff                  |
| `whitespace`  | string | `SHOW` or `IGNORE_ALL`                           |

**Response**: Returns a structured diff object with hunks per file:
```json
{
  "diffs": [
    {
      "source": { "toString": "src/auth/login.ts" },
      "destination": { "toString": "src/auth/login.ts" },
      "hunks": [
        {
          "sourceLine": 45,
          "sourceSpan": 10,
          "destinationLine": 45,
          "destinationSpan": 15,
          "segments": [
            {
              "type": "CONTEXT",
              "lines": [{ "line": 45, "source": 45, "destination": 45, "text": "  const timeout = config.timeout;" }]
            },
            {
              "type": "REMOVED",
              "lines": [{ "line": 46, "source": 46, "text": "  if (timeout > 0) {" }]
            },
            {
              "type": "ADDED",
              "lines": [{ "line": 46, "destination": 46, "text": "  if (timeout > 0 && timeout < MAX_TIMEOUT) {" }]
            }
          ]
        }
      ]
    }
  ],
  "truncated": false
}
```

**Alternative - raw diff**:
```
GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{pullRequestId}.diff
```
Returns a plain-text unified diff (standard git diff format). This may be easier to
render in a terminal.

#### 2.3.4 Get PR Activities (Comments, Approvals, etc.)

```
GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{pullRequestId}/activities
```

Returns a chronological list of all activities including comments, approvals, rescopes,
and merges.

#### 2.3.5 Approve PR

```
POST /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{pullRequestId}/approve
```

- **No request body required.**
- **Response**: `200 OK` with the participant object showing `approved: true`.

**Remove approval**:
```
DELETE /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{pullRequestId}/approve
```

#### 2.3.6 Add Comment to PR

**General comment**:
```
POST /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{pullRequestId}/comments
```

**Request body**:
```json
{
  "text": "This looks good to me. Nice work on the timeout handling."
}
```

**Inline comment** (on a specific file/line):
```json
{
  "text": "Consider adding a constant for this magic number.",
  "anchor": {
    "path": "src/auth/login.ts",
    "line": 46,
    "lineType": "ADDED",
    "fileType": "TO"
  }
}
```

**Response** (201 Created):
```json
{
  "id": 5001,
  "text": "This looks good to me.",
  "author": { "name": "jdoe", "displayName": "John Doe" },
  "createdDate": 1707993600000,
  "updatedDate": 1707993600000
}
```

**Comment format**: Bitbucket Server uses **Markdown** for comments (unlike Jira's wiki
markup). Standard Markdown syntax works: `**bold**`, `*italic*`, `` `code` ``,
triple-backtick code blocks, `[links](url)`, etc.

#### 2.3.7 Get Build Status

Build statuses are stored per **commit**, not per PR. Use the latest commit on the PR's
source branch:

```
GET /rest/build-status/1.0/commits/{commitHash}
```

**Note**: This uses a different API namespace (`/rest/build-status/1.0/`).

**Response**:
```json
{
  "size": 2,
  "limit": 25,
  "isLastPage": true,
  "values": [
    {
      "state": "SUCCESSFUL",
      "key": "build-pipeline-main",
      "name": "CI Pipeline - Main",
      "url": "https://ci.example.com/builds/12345",
      "description": "All 247 tests passed",
      "dateAdded": 1707993600000
    },
    {
      "state": "FAILED",
      "key": "sonarqube-analysis",
      "name": "SonarQube Analysis",
      "url": "https://sonar.example.com/dashboard?id=my-repo",
      "description": "Quality gate failed: 3 new bugs",
      "dateAdded": 1707993600000
    }
  ]
}
```

**Build states**: `SUCCESSFUL`, `FAILED`, `INPROGRESS`

**To get the latest commit hash for a PR**, use the `fromRef.latestCommit` field from
the PR details response. If not present, fetch the PR details first:
```
GET /rest/api/1.0/projects/{projectKey}/repos/{repoSlug}/pull-requests/{pullRequestId}
```
Then use `response.fromRef.latestCommit` as the commit hash.

#### 2.3.8 Get Current User

```
GET /rest/api/1.0/users/{userSlug}
```

Or use the application-properties endpoint to validate connection:
```
GET /rest/api/1.0/application-properties
```

**Note**: Unlike Jira, Bitbucket Server does not have a direct `/myself` endpoint. The
user slug can be determined from the token. An alternative is:
```
GET /plugins/servlet/applinks/whoami
```
This returns the username of the authenticated user as plain text.

### 2.4 Pagination

Bitbucket Server uses **offset-based pagination** with a different parameter scheme than
Jira:

| Field           | Description                                      |
|-----------------|--------------------------------------------------|
| `start`         | 0-based offset of first result                   |
| `limit`         | Number of results per page (default 25, max varies, typically 100) |
| `size`          | Number of results in current page                |
| `isLastPage`    | Boolean indicating if this is the final page     |
| `nextPageStart` | Value to use as `start` for the next request     |

**Algorithm**:
```
start = 0
do:
  response = GET /rest/api/1.0/{resource}?start={start}&limit={pageSize}
  process(response.values)
  start = response.nextPageStart
while (!response.isLastPage)
```

**Important**: Always use `nextPageStart` from the response rather than computing
`start + limit`. Bitbucket may skip entries and `nextPageStart` accounts for this.

### 2.5 Rate Limiting

Bitbucket Server/Data Center has **built-in rate limiting** (since Bitbucket Server 5.2):

- **Default**: Often disabled. Administrators enable and configure per-user limits.
- When rate-limited, returns **HTTP 429 Too Many Requests**.
- Response headers:
  ```
  X-RateLimit-Limit: <max-requests-per-window>
  X-RateLimit-Remaining: <remaining>
  X-RateLimit-Reset: <epoch-seconds>
  Retry-After: <seconds>
  ```
- **Recommendation**: Same as Jira - implement exponential backoff on 429 responses.
  Respect `Retry-After` header. Cap at 3 retries.

### 2.6 Error Responses

```json
{
  "errors": [
    {
      "context": null,
      "message": "Pull request 999 does not exist in repository/slug.",
      "exceptionName": "com.atlassian.bitbucket.pull.NoSuchPullRequestException"
    }
  ]
}
```

| Status | Meaning                                    |
|--------|--------------------------------------------|
| 400    | Bad request                                |
| 401    | Authentication failed                      |
| 403    | Permission denied                          |
| 404    | Resource not found                         |
| 409    | Conflict (e.g., stale PR version)          |
| 429    | Rate limited                               |
| 500    | Server error                               |

---

## 3. Cross-Referencing: Jira Issues and Bitbucket PRs

### 3.1 Jira Issue Key Detection

Bitbucket Server has **built-in Jira integration** when configured by an administrator
via Application Links. When active:

- Bitbucket automatically detects Jira issue keys (e.g., `PROJ-123`) in:
  - PR titles
  - PR descriptions
  - Branch names
  - Commit messages
- The detected keys create links visible in both Jira and Bitbucket UIs.

### 3.2 Branch Naming Conventions

The most reliable cross-reference method uses **Jira issue keys in branch names**:

```
feature/PROJ-123-fix-login-timeout
bugfix/PROJ-456-handle-null-response
PROJ-789-update-dependencies
```

**Pattern to extract Jira keys from branch names**:
```regex
([A-Z][A-Z0-9]+-\d+)
```

This regex matches standard Jira issue keys (project prefix in uppercase letters/digits,
followed by a hyphen and a number).

### 3.3 PR Title Conventions

Many teams also include Jira issue keys in PR titles:
```
PROJ-123: Fix login timeout issue
[PROJ-456] Handle null response in API client
feat(PROJ-789): Update dependencies
```

The same regex pattern works for extraction from titles.

### 3.4 Programmatic Cross-Reference Strategy

Since our app controls both the Jira and Bitbucket data:

**Option A: Client-side matching (recommended for v1)**

1. Fetch Jira issues (assigned to user).
2. Fetch Bitbucket PRs (authored by / reviewing user).
3. For each PR, extract Jira issue keys from:
   - `pr.fromRef.displayId` (branch name)
   - `pr.title`
   - `pr.description`
4. Match extracted keys against fetched Jira issue keys.
5. Store bidirectional references in the local task model.

```typescript
// Pseudocode for cross-reference extraction
function extractJiraKeys(text: string): string[] {
  const pattern = /([A-Z][A-Z0-9]+-\d+)/g;
  const matches = text.match(pattern);
  return [...new Set(matches ?? [])];
}

function crossReference(pr: BitbucketPR): string[] {
  const sources = [
    pr.fromRef.displayId,    // branch name
    pr.title,                 // PR title
    pr.description ?? '',     // PR description
  ];
  return sources.flatMap(extractJiraKeys);
}
```

**Option B: Jira REST API for remote links (if Application Links are configured)**

```
GET /rest/api/2/issue/{issueKey}/remotelink
```

This returns remote links including Bitbucket PR links if the Jira-Bitbucket application
link is configured. However, this depends on admin configuration and adds extra API calls.

**Recommendation**: Use Option A (client-side matching) as the primary strategy. It works
regardless of whether Application Links are configured, and requires no additional API
calls beyond what we already need.

### 3.5 Cross-Reference Data Model

```typescript
interface CrossReference {
  jiraKey: string;          // e.g., "PROJ-123"
  bitbucketPRId: number;    // e.g., 101
  matchSource: 'branch' | 'title' | 'description';
  projectKey: string;       // Bitbucket project key
  repoSlug: string;         // Bitbucket repo slug
}
```

---

## 4. Unified API Contract Summary

### 4.1 Common Patterns

Both APIs share these characteristics:

| Aspect              | Jira Server/DC                | Bitbucket Server              |
|---------------------|-------------------------------|-------------------------------|
| **Auth header**     | `Authorization: Bearer <PAT>` | `Authorization: Bearer <PAT>` |
| **Content type**    | `application/json`            | `application/json`            |
| **Pagination style**| Offset-based (`startAt`)      | Offset-based (`start`)        |
| **Rate limit**      | 429 + `Retry-After`           | 429 + `Retry-After`           |
| **Error format**    | `{ errorMessages, errors }`   | `{ errors: [{ message }] }`  |
| **Timestamps**      | ISO 8601 strings              | Unix epoch milliseconds       |
| **User IDs**        | `key` (string, e.g. `jdoe`)  | `name`/`slug` (string)       |

### 4.2 Adapter Interface Shape

Based on the research, here is the recommended adapter interface:

```typescript
interface JiraAdapter {
  // Connection
  validateConnection(): Promise<JiraUser>;

  // Read operations
  searchIssues(jql: string, options?: PaginationOptions): Promise<PaginatedResult<JiraIssue>>;
  getAssignedIssues(options?: PaginationOptions): Promise<PaginatedResult<JiraIssue>>;
  getIssue(issueKey: string): Promise<JiraIssueDetail>;
  getTransitions(issueKey: string): Promise<JiraTransition[]>;

  // Write operations
  transitionIssue(issueKey: string, transitionId: string, fields?: Record<string, unknown>): Promise<void>;
  addComment(issueKey: string, body: string): Promise<JiraComment>;
}

interface BitbucketAdapter {
  // Connection
  validateConnection(): Promise<BitbucketUser>;

  // Read operations
  getInboxPullRequests(role?: 'AUTHOR' | 'REVIEWER', options?: PaginationOptions): Promise<PaginatedResult<BitbucketPR>>;
  getPullRequest(projectKey: string, repoSlug: string, prId: number): Promise<BitbucketPRDetail>;
  getPullRequestDiff(projectKey: string, repoSlug: string, prId: number): Promise<BitbucketDiff>;
  getPullRequestActivities(projectKey: string, repoSlug: string, prId: number, options?: PaginationOptions): Promise<PaginatedResult<BitbucketActivity>>;
  getBuildStatus(commitHash: string): Promise<BitbucketBuildStatus[]>;

  // Write operations
  approvePullRequest(projectKey: string, repoSlug: string, prId: number): Promise<void>;
  unapprovePullRequest(projectKey: string, repoSlug: string, prId: number): Promise<void>;
  addComment(projectKey: string, repoSlug: string, prId: number, text: string): Promise<BitbucketComment>;
}

interface PaginationOptions {
  page?: number;
  pageSize?: number;
}

interface PaginatedResult<T> {
  items: T[];
  total: number;
  hasMore: boolean;
  nextPage?: number;
}
```

### 4.3 Configuration Shape

```typescript
interface JiraConfig {
  baseUrl: string;          // e.g., "https://jira.corp.example.com"
  personalAccessToken: string;
  defaultJql?: string;      // Optional user-customized default query
  pollIntervalMs?: number;  // Override for polling interval
}

interface BitbucketConfig {
  baseUrl: string;          // e.g., "https://bitbucket.corp.example.com"
  personalAccessToken: string;
  pollIntervalMs?: number;
}
```

### 4.4 HTTP Client Requirements

The shared HTTP client layer should support:

- **Base URL configuration**: Prepend the configured base URL to all relative paths.
- **Bearer token injection**: Automatically add `Authorization: Bearer <token>` header.
- **Retry with exponential backoff**: On 429, 500, 502, 503 responses.
- **Timeout**: Configurable per-request timeout (default 30 seconds).
- **Response parsing**: JSON deserialization with type validation.
- **Error normalization**: Convert API-specific error formats into a common error type.
- **Request logging**: Debug-level logging of request/response for troubleshooting.

### 4.5 Timestamp Normalization

Since the two APIs return timestamps differently, normalize to a common format:

```typescript
// Jira: ISO 8601 string -> Date
function parseJiraTimestamp(iso: string): Date {
  return new Date(iso);  // "2026-02-13T10:30:00.000+0000"
}

// Bitbucket: Unix epoch milliseconds -> Date
function parseBitbucketTimestamp(epochMs: number): Date {
  return new Date(epochMs);  // 1707993600000
}
```

---

## 5. Implementation Recommendations

### 5.1 Priority Order for API Integration

1. **Jira: `GET /myself`** - Validate connection on setup.
2. **Jira: `POST /search`** - Core data for the dashboard.
3. **Bitbucket: `GET /inbox/pull-requests`** - Core data for the dashboard.
4. **Jira: `GET /issue/{key}`** - Detail view.
5. **Bitbucket: `GET /.../pull-requests/{id}`** - Detail view.
6. **Bitbucket: `GET /build-status/1.0/commits/{hash}`** - Build status in detail view.
7. **Jira: `GET /issue/{key}/transitions`** + `POST` - Write actions.
8. **Jira: `POST /issue/{key}/comment`** - Write actions.
9. **Bitbucket: `POST /.../approve`** - Write actions.
10. **Bitbucket: `POST /.../comments`** - Write actions.
11. **Bitbucket: `GET /.../diff`** - Diff view.
12. **Cross-referencing**: Client-side key extraction after both sources are loaded.

### 5.2 Caching Strategy

- **List data** (search results, inbox PRs): Cache with TTL matching poll interval.
- **Detail data** (issue details, PR details): Cache with shorter TTL (30 seconds)
  since users expect fresh data when viewing details.
- **Transitions**: Do not cache; always fetch fresh (they change based on current status).
- **Build status**: Cache with 60-second TTL.
- **User info** (`/myself`, `/whoami`): Cache for session lifetime.

### 5.3 Known Limitations

- **Jira wiki markup**: The terminal cannot render rich formatting. Use `renderedFields`
  (HTML) and strip tags, or display raw wiki markup with minimal parsing.
- **Bitbucket diff size**: Large PRs with many files can produce very large diff
  responses. Consider fetching file-by-file diffs or limiting context lines.
- **No WebSocket/SSE**: Neither API supports push notifications for Server/DC. Polling
  is the only option for real-time updates.
- **Application Links dependency**: Jira-Bitbucket cross-referencing via remote links
  requires admin configuration. Client-side key matching is more reliable.
- **PAT availability**: Requires Jira 8.14+ and Bitbucket 5.5+. Older versions need
  Basic Auth fallback.
