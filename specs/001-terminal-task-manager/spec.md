# Feature Specification: Terminal Task Manager

**Feature Branch**: `001-terminal-task-manager`
**Created**: 2026-02-13
**Status**: Draft
**Input**: User description: "I want to build a terminal UI similar to k9s that allow me manage tasks with external sources like jira, bitbucket, chat app, email. Help me decide the technology as well"

## Clarifications

### Session 2026-02-13

- Q: Which specific chat application should be supported first? → A: Chat integration deferred entirely - out of scope for initial release. Focus on Jira, Bitbucket, and Email.
- Q: How should the unified dashboard navigation model work? → A: Single flat list - all items normalized into one task list with source indicated by icon/label. No separate per-source views.
- Q: How fresh should data be in the main list? → A: Periodic polling with configurable interval (e.g., every 1-5 minutes) plus manual refresh on demand.
- Q: Should the set of integrations be fixed or extensible via plugins? → A: Fixed for v1 (Jira, Bitbucket, Email hardcoded), plan to extract a plugin/adapter interface in v2.
- Q: Which Jira instance type should be supported? → A: Jira Server/Data Center only (on-premise, personal access tokens).
- Q: Should the AI assistant search/read only or also execute write actions? → A: Read only - AI can search and summarize across sources but cannot modify anything.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unified Task Dashboard (Priority: P1)

As a developer, I want to see all my tasks from connected sources in a single terminal view so that I can quickly understand my workload without switching between multiple applications.

When I launch the application, I see a single flat list of all items normalized from my configured sources (e.g., Jira issues assigned to me, Bitbucket pull requests awaiting my review, flagged emails). Each item shows a source icon/label for quick identification. I can navigate using keyboard shortcuts, filter by source, and sort by priority or due date.

**Why this priority**: This is the core value proposition - a single pane of glass for all work items. Without this, the application has no reason to exist.

**Independent Test**: Can be fully tested by configuring at least one source, launching the application, and verifying that tasks appear in a navigable list. Delivers immediate value by centralizing task visibility.

**Acceptance Scenarios**:

1. **Given** the user has configured at least one external source, **When** they launch the application, **Then** they see a list of their tasks from that source within 5 seconds.
2. **Given** the user is viewing the task list, **When** they press a filter key, **Then** they can filter tasks by source, status, or priority.
3. **Given** the user is viewing the task list, **When** they navigate to a task and press enter, **Then** they see the full details of that task in a detail view.
4. **Given** the user has multiple sources configured, **When** they view the dashboard, **Then** all items appear in a single flat list with source icon/label indicators, and can be filtered by source type.

---

### User Story 2 - Jira Integration (Priority: P1)

As a developer, I want to view and manage my Jira issues directly from the terminal so that I can update issue statuses, add comments, and track progress without opening a browser.

**Why this priority**: Jira is the most common project management tool for development teams and represents the primary use case. This integration validates the core architecture for all future integrations.

**Independent Test**: Can be fully tested by connecting to a Jira instance, viewing assigned issues, transitioning an issue's status, and adding a comment. Delivers standalone value as a terminal Jira client.

**Acceptance Scenarios**:

1. **Given** the user has configured Jira credentials, **When** they filter the list by Jira source, **Then** they see their assigned issues with title, status, priority, and project.
2. **Given** the user is viewing a Jira issue, **When** they trigger a status transition action, **Then** they see available transitions and can select one to update the issue.
3. **Given** the user is viewing a Jira issue, **When** they trigger the comment action, **Then** they can type and submit a comment that appears on the issue.
4. **Given** the user is viewing the list, **When** they type a search query, **Then** matching Jira issues are displayed in real time.

---

### User Story 3 - Bitbucket Integration (Priority: P2)

As a developer, I want to view and manage my Bitbucket pull requests from the terminal so that I can review PRs, check build statuses, and approve or request changes without leaving my workflow.

**Why this priority**: Pull request management is a daily developer workflow that pairs naturally with Jira task management. Together they cover the core development loop.

**Independent Test**: Can be fully tested by connecting to a Bitbucket workspace, viewing open PRs, reading PR details and diffs, and approving a PR.

**Acceptance Scenarios**:

1. **Given** the user has configured Bitbucket credentials, **When** they filter the list by Bitbucket source, **Then** they see PRs they authored and PRs awaiting their review.
2. **Given** the user is viewing a pull request, **When** they select it, **Then** they see the PR description, file changes summary, build status, and reviewer status.
3. **Given** the user is viewing a pull request, **When** they trigger the approve action, **Then** the PR is approved and the status updates in the view.
4. **Given** the user is viewing a pull request, **When** they trigger the comment action, **Then** they can add a general comment to the PR.

---

### User Story 4 - Email Integration (Priority: P3)

As a developer, I want to view and triage my email from the terminal so that I can quickly process actionable emails alongside my other tasks.

**Why this priority**: Email is a common source of tasks and action items. Integrating it completes the unified inbox vision, but is lower priority than dev-specific tools.

**Independent Test**: Can be fully tested by connecting to an email account, viewing the inbox, reading an email, and archiving or flagging it.

**Acceptance Scenarios**:

1. **Given** the user has configured email credentials, **When** they filter the list by email source, **Then** they see their inbox items with sender, subject, date, and read/unread status.
2. **Given** the user is viewing an email, **When** they select it, **Then** they see the full email content rendered as text.
3. **Given** the user is viewing an email, **When** they trigger the archive action, **Then** the email is archived and removed from the inbox view.
4. **Given** the user is viewing an email, **When** they trigger the reply action, **Then** they can compose and send a reply.

---

### User Story 5 - Keyboard-Driven Navigation (Priority: P1)

As a developer, I want to navigate the entire application using keyboard shortcuts (similar to k9s and vim) so that I can work efficiently without reaching for a mouse.

**Why this priority**: Keyboard-first design is fundamental to the k9s-like experience the user wants. It defines the interaction model for the entire application.

**Independent Test**: Can be fully tested by launching the application and performing all navigation, selection, filtering, and action operations using only the keyboard.

**Acceptance Scenarios**:

1. **Given** the user is on any screen, **When** they press `?` or a help key, **Then** they see a list of all available keyboard shortcuts for the current context.
2. **Given** the user is on the task list, **When** they use vim-style keys (j/k for up/down, `/` for search, `:` for commands), **Then** the application responds with the expected navigation behavior.
3. **Given** the user is on any view, **When** they press `Esc` or `q`, **Then** they return to the previous view or exit the application.
4. **Given** the user is on any list view, **When** they type a filter prefix, **Then** the list is filtered in real time.

---

### User Story 6 - Source Configuration (Priority: P2)

As a developer, I want to configure and manage my external source connections so that I can add, remove, and update credentials for each integration.

**Why this priority**: Users need a way to set up their sources before they can use the application. This is essential plumbing that supports all other stories.

**Independent Test**: Can be fully tested by running the configuration flow, adding a source with credentials, verifying the connection, and removing it.

**Acceptance Scenarios**:

1. **Given** the user launches the application for the first time, **When** no sources are configured, **Then** they are guided through setting up at least one source.
2. **Given** the user is in the configuration view, **When** they add a new source, **Then** they are prompted for the required credentials and connection details.
3. **Given** the user has entered source credentials, **When** they confirm, **Then** the system validates the connection and reports success or a clear error message.
4. **Given** the user has configured sources, **When** they want to remove one, **Then** they can delete the source configuration and its cached data.

---

### User Story 7 - AI Assistant Prompt (Priority: P2)

As a developer, I want to open a text prompt and ask an AI assistant questions in natural language so that I can search across all my connected sources, get summaries, and find information without manually filtering and browsing.

The AI assistant is read-only: it can search, retrieve, and summarize data from all configured sources but cannot modify any items (no status transitions, no comments, no approvals). The assistant maintains conversational context within a session so follow-up questions work naturally.

**Why this priority**: Natural language search across multiple sources is a significant productivity multiplier. It reduces the cognitive load of remembering which source holds which information and eliminates complex filter/sort workflows for common queries.

**Independent Test**: Can be fully tested by opening the AI prompt, asking a natural language question about items across sources, and verifying the assistant returns relevant, accurate results with source references.

**Acceptance Scenarios**:

1. **Given** the user is on any view, **When** they press a designated key to open the AI prompt, **Then** a text input panel appears where they can type a natural language query.
2. **Given** the user has typed a query (e.g., "show me all critical Jira bugs from this week"), **When** they submit it, **Then** the AI searches across configured sources and displays matching results with source references.
3. **Given** the AI has returned results, **When** the user selects a result item, **Then** they navigate to the detail view for that item.
4. **Given** the user is in a conversation with the AI, **When** they ask a follow-up question (e.g., "which of those are assigned to me?"), **Then** the AI uses the prior context to refine the response.
5. **Given** the user asks the AI to perform a write action (e.g., "move this to Done"), **When** the AI receives the request, **Then** it explains that it can only search and summarize, and suggests the manual action the user can take.

---

### Edge Cases

- What happens when an external source is unreachable (network failure, service outage)? The system displays cached data with a staleness indicator and retries in the background.
- What happens when authentication tokens expire mid-session? The system notifies the user and provides a way to re-authenticate without restarting the application.
- What happens when a source returns a very large number of results (e.g., 10,000 Jira issues)? The system paginates results and loads additional pages on demand.
- What happens when the terminal window is resized? The layout adapts responsively to the new dimensions.
- What happens when the user has no tasks in any source? The system shows an empty state with helpful guidance.
- What happens when two sources return conflicting data for the same task (e.g., a Jira issue linked to a Bitbucket PR)? The system shows both items with cross-reference links.
- What happens when the AI provider is unreachable or the API key is invalid? The system displays a clear error and the rest of the application continues to function normally.
- What happens when the user asks the AI a question unrelated to their tasks? The AI responds helpfully but steers the conversation back to task management context.
- What happens when the AI returns results spanning many items? Results are paginated and the user can scroll through them.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display all items from configured external sources in a single flat, navigable list with source icon/label indicators.
- **FR-002**: System MUST support keyboard-driven navigation using vim-style keybindings (j/k, h/l, /, :, Esc, Enter).
- **FR-003**: System MUST allow filtering tasks by source, status, priority, and free-text search.
- **FR-004**: System MUST allow sorting tasks by date, priority, source, and status.
- **FR-005**: System MUST display a detail view for any selected task showing all relevant information from the source.
- **FR-006**: System MUST support Jira Server/Data Center integration: view assigned issues, transition statuses, add comments, and search issues using personal access tokens.
- **FR-007**: System MUST support Bitbucket integration: view authored and review-requested PRs, view diffs/build status, approve PRs, and add comments.
- **FR-008**: System MUST support email integration: view inbox, read emails, reply, archive, and flag messages.
- **FR-009**: System MUST provide a configuration interface for adding, editing, testing, and removing source connections.
- **FR-010**: System MUST securely store authentication credentials for configured sources.
- **FR-011**: System MUST gracefully handle source unavailability by showing cached data with staleness indicators.
- **FR-012**: System MUST handle token expiration by prompting the user to re-authenticate without restarting.
- **FR-013**: System MUST paginate large result sets, loading additional pages on demand.
- **FR-014**: System MUST adapt its layout when the terminal window is resized.
- **FR-015**: System MUST display a contextual help overlay showing available keyboard shortcuts.
- **FR-016**: System MUST support a command palette (triggered by `:`) for executing actions by name.
- **FR-017**: System MUST poll configured sources at a user-configurable interval (default: every 2 minutes) and notify the user of new or updated items. Users MUST be able to trigger a manual refresh at any time.
- **FR-018**: System MUST support cross-referencing related items across sources (e.g., a Jira issue linked to a Bitbucket PR).
- **FR-019**: System MUST provide an AI assistant prompt accessible via a keyboard shortcut from any view.
- **FR-020**: The AI assistant MUST be able to search and retrieve items across all configured sources using natural language queries.
- **FR-021**: The AI assistant MUST be read-only: it MUST NOT perform any write operations (status transitions, comments, approvals, or modifications) on any source.
- **FR-022**: The AI assistant MUST maintain conversational context within a session so follow-up questions can reference prior responses.
- **FR-023**: The AI assistant MUST display results with clear source references that the user can select to navigate to the item detail view.
- **FR-024**: The AI assistant MUST gracefully decline write action requests and suggest the manual action the user can take instead.

### Key Entities

- **Task**: A unified representation of a work item from any source. Contains a title, description, status, priority, source type, source identifier, assignee, creation date, and last updated date.
- **Source**: An external service integration. Contains a type (Jira, Bitbucket, email), connection configuration, authentication credentials, and sync status.
- **Source Item**: The raw data from a specific source before normalization into a Task. Retains source-specific fields (e.g., Jira issue type, Bitbucket PR reviewers, email attachments).
- **Notification**: An alert for new or updated items. Contains the source, item reference, timestamp, and read/unread status.
- **Configuration**: User preferences and source connection settings. Contains keybinding overrides, display preferences, source credentials, and AI provider settings.
- **AI Conversation**: A session-scoped exchange between the user and the AI assistant. Contains a sequence of user queries and AI responses, with references to source items returned in results.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can view their aggregated tasks from all configured sources within 5 seconds of launching the application.
- **SC-002**: Users can navigate to any task detail and back in under 3 keystrokes.
- **SC-003**: Users can perform a status transition on a Jira issue in under 10 seconds without leaving the terminal.
- **SC-004**: Users can filter the task list to show only items from a specific source in under 2 seconds.
- **SC-005**: 90% of users can configure a new source connection successfully on their first attempt without external documentation.
- **SC-006**: The application remains responsive (under 200ms input-to-render) even with 1,000+ tasks loaded across sources.
- **SC-007**: Users report a 50% reduction in context-switching between applications for daily task management.
- **SC-008**: All core workflows (view, filter, act on tasks) are completable using only the keyboard.
- **SC-009**: Users can find a specific item across all sources via the AI prompt in under 15 seconds using a natural language query.
- **SC-010**: The AI assistant responds to queries within 5 seconds for typical searches.

## Assumptions

- The primary user is a developer or technical professional comfortable with terminal-based applications and vim-style keybindings.
- The application is designed for single-user, personal productivity use (not multi-user collaboration).
- Jira integration targets Server/Data Center (on-premise) using personal access tokens. Jira Cloud support may be added in a future iteration.
- Token-based or standard protocol authentication will be used for all external source integrations.
- The application will run on macOS and Linux terminals. Windows support via WSL is assumed but not a primary target.
- Email integration assumes IMAP/SMTP-compatible email providers (Gmail, Outlook, etc.).
- The application will cache data locally for offline viewing and performance.
- Technology decisions (language, framework, TUI library) will be made during the planning phase.
- Source integrations (Jira, Bitbucket, Email) are hardcoded for v1. A plugin/adapter interface for user-extensible sources is planned for v2.
- The AI assistant requires a user-configured AI provider API key (e.g., Anthropic Claude). The specific provider will be decided during the planning phase.
- The AI assistant is strictly read-only in v1. Write capabilities may be considered for a future iteration with a confirmation-based safety model.

## Out of Scope

- Mobile or web interface - this is a terminal-only application.
- Multi-user collaboration features (shared task boards, team views).
- Calendar integration (may be added in a future iteration).
- File attachment viewing within the terminal (links to attachments will be shown).
- Full email composition with rich text or HTML formatting.
- Chat app integration (Slack, Teams, Discord) - deferred to a future iteration.
- Custom workflow automation or scripting engine.
