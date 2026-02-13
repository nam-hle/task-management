# Feature Specification: Todo List with External Source Connections

**Feature Branch**: `002-todo-external-sources`
**Created**: 2026-02-13
**Status**: Draft
**Input**: User description: "I want my app is a todo list-like one first, but can connect to external sources"

## Clarifications

### Session 2026-02-13

- Q: How should completed todos be displayed in the main list? → A: Completed items stay inline, visually dimmed/struck-through, with a toggle to show/hide them.
- Q: How should due dates behave when they arrive or pass? → A: Overdue items are visually flagged in the list, with date-based filters (today/upcoming/overdue).
- Q: Should todos support subtasks or nested items? → A: Simple one-level checklists within a todo (checklist items are text + checkbox, not full todos).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create and Manage Personal Todos (Priority: P1)

As a user, I want to create, view, edit, complete, and delete personal todo items so that I can track my own tasks and goals in a simple, fast interface.

**Why this priority**: The core value proposition is a functional todo list. Without local task management, the app has no standalone utility and is entirely dependent on external connections. This must work even with zero external sources configured.

**Independent Test**: Can be fully tested by creating several todos, marking some complete, editing one, and deleting another. Delivers immediate personal productivity value with no external dependencies.

**Acceptance Scenarios**:

1. **Given** the app is open with no todos, **When** the user creates a new todo with a title, **Then** it appears in the list immediately and persists across app restarts.
2. **Given** a list of todos exists, **When** the user marks a todo as complete, **Then** it remains in the list but is visually dimmed and struck-through, and the user can toggle visibility of completed items to show or hide them.
3. **Given** an existing todo, **When** the user edits its title or description, **Then** the changes are saved and reflected immediately.
4. **Given** an existing todo, **When** the user deletes it, **Then** it is removed from the list after confirmation.
5. **Given** multiple todos exist, **When** the user reorders them via manual priority, **Then** the custom order persists across sessions.

---

### User Story 2 - Organize Todos with Projects and Tags (Priority: P2)

As a user, I want to organize my todos into projects and tag them with labels so that I can group related work and find items quickly.

**Why this priority**: Organization is essential for any todo list beyond a handful of items. Without it, the list becomes unmanageable as it grows. This is the second most important capability after basic CRUD.

**Independent Test**: Can be tested by creating a project, adding todos to it, tagging them, and filtering by project or tag. Delivers organizational value on top of P1.

**Acceptance Scenarios**:

1. **Given** the app has todos, **When** the user creates a project and assigns todos to it, **Then** the user can view todos filtered by that project.
2. **Given** a todo exists, **When** the user adds one or more tags to it, **Then** the user can filter the todo list by any of those tags.
3. **Given** multiple projects exist, **When** the user switches between projects, **Then** only todos belonging to the selected project are shown (with an "all" option to see everything).
4. **Given** a project with todos, **When** the user archives or deletes the project, **Then** the todos within it are either moved to an inbox/default area or deleted (user's choice).

---

### User Story 3 - Connect External Sources (Priority: P3)

As a user, I want to connect external task sources (such as Jira, GitHub, Trello, or other project management tools) so that external work items appear alongside my personal todos in a unified view.

**Why this priority**: External source connections differentiate this from a plain todo app. However, the app must be fully usable without any external sources, making this an enhancement rather than a core requirement.

**Independent Test**: Can be tested by configuring one external source, verifying items appear in the unified list, and confirming they are visually distinguishable from local todos. Delivers cross-tool visibility.

**Acceptance Scenarios**:

1. **Given** the user has no external sources configured, **When** the user navigates to source settings, **Then** they see a list of available source types and can configure a new connection with credentials.
2. **Given** an external source is configured, **When** the connection is validated and items are fetched, **Then** external items appear in the unified todo list with a clear source indicator.
3. **Given** external items are displayed, **When** the user views an external item's details, **Then** relevant metadata from the source (status, assignee, priority, link to original) is shown.
4. **Given** an external source becomes unreachable, **When** the app attempts to sync, **Then** previously fetched items remain visible with a stale indicator, and the user is notified of the connection issue.

---

### User Story 4 - Interact with External Items (Priority: P4)

As a user, I want to perform actions on external items (change status, add comments, link to local todos) without leaving the app so that I can manage all my work from one place.

**Why this priority**: Interaction with external items elevates the app from a read-only dashboard to a true unified workspace. This builds on P3 and is valuable only after external connections are working.

**Independent Test**: Can be tested by changing the status of an external item and verifying the change is reflected in the external system. Delivers workflow efficiency.

**Acceptance Scenarios**:

1. **Given** an external item is displayed, **When** the user changes its status (e.g., "In Progress" to "Done"), **Then** the change is pushed to the external source and confirmed.
2. **Given** an external item is displayed, **When** the user adds a comment, **Then** the comment appears on the original item in the external system.
3. **Given** a local todo and an external item exist, **When** the user links them, **Then** both items show the linkage and navigating between them is seamless.

---

### User Story 5 - Search and Filter Across All Sources (Priority: P5)

As a user, I want to search and filter across both local todos and external items so that I can quickly find any work item regardless of where it originated.

**Why this priority**: Search becomes critical as the combined list of local and external items grows. This is a quality-of-life improvement that depends on P1 and P3 being in place.

**Independent Test**: Can be tested by searching for a keyword that exists in both a local todo and an external item, verifying both appear in results. Delivers discoverability.

**Acceptance Scenarios**:

1. **Given** local todos and external items exist, **When** the user enters a search query, **Then** results include matching items from all sources ranked by relevance.
2. **Given** the unified list is displayed, **When** the user applies a filter (by source, status, tag, project, or priority), **Then** only matching items are shown and filters can be combined.
3. **Given** search results are displayed, **When** the user clears the search, **Then** the full list is restored with previous sort/filter state preserved.

---

### Edge Cases

- What happens when the user creates a todo while offline? Local todos are always available; external syncs resume when connectivity is restored.
- How does the system handle duplicate items (e.g., a Jira ticket that was also manually created as a local todo)? Duplicates are flagged when detected (matching by title similarity or explicit link) and the user can merge or dismiss.
- What happens when an external source's authentication expires? The user is notified and prompted to re-authenticate; items from that source are shown as stale but not removed.
- What if an external item is deleted from the source? On the next sync, the item is marked as "removed from source" rather than silently disappearing, and the user can dismiss or archive it.
- What happens when the same external source is connected with different accounts? Each connection is treated independently with its own credential set; items are deduplicated by source-specific unique identifiers.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow users to create todo items with at minimum a title, and optionally a description, due date, priority level, tags, and project assignment.
- **FR-002**: System MUST allow users to view all todos in a unified list that includes both local and external items, with clear visual distinction between sources.
- **FR-003**: System MUST allow users to mark todos as complete, edit their properties, and delete them with confirmation.
- **FR-004**: System MUST persist all local todos and user preferences across sessions.
- **FR-005**: System MUST allow users to organize todos into projects and assign tags for filtering.
- **FR-006**: System MUST allow users to configure connections to external task sources with secure credential storage.
- **FR-007**: System MUST fetch and display items from connected external sources alongside local todos.
- **FR-008**: System MUST allow users to perform source-specific actions on external items (e.g., change status, add comments) from within the app.
- **FR-009**: System MUST support searching across all sources (local and external) by keyword, with results ranked by relevance.
- **FR-010**: System MUST support filtering the unified list by source, status, priority, tag, project, and date-based views (today, upcoming, overdue).
- **FR-010a**: System MUST visually flag overdue todos (past due date and not complete) with a distinct indicator in the list view.
- **FR-011**: System MUST handle external source unavailability gracefully by preserving cached items with staleness indicators and notifying the user.
- **FR-012**: System MUST allow users to link local todos to external items for cross-referencing.
- **FR-013**: System MUST support custom ordering of todos that persists across sessions.
- **FR-014**: System MUST provide a way for users to test external source connections before saving them.
- **FR-015**: System MUST allow users to add, check/uncheck, and remove checklist items within a todo. Checklist items are simple text entries with a checked/unchecked state and are not independent todos.

### Key Entities

- **Todo**: A local task item created by the user. Key attributes: title, description, status (open/complete), priority (1-5), due date, custom sort order, creation date, completion date, checklist (ordered list of checklist items).
- **Checklist Item**: A simple sub-entry within a todo. Key attributes: text, checked/unchecked state, display order. Not an independent todo — exists only as part of its parent.
- **Project**: A grouping of related todos. Key attributes: name, description, color/icon, archived status. A todo belongs to at most one project.
- **Tag**: A label that can be applied to any todo for cross-cutting categorization. Key attributes: name, color. A todo can have multiple tags.
- **External Source**: A configured connection to an external task system. Key attributes: source type, display name, connection details, credential reference, sync interval, last synced timestamp.
- **External Item**: A task/item fetched from an external source. Key attributes: source-specific ID, title, description, status (normalized), priority (normalized), source metadata, link to original, staleness indicator.
- **Link**: An association between a local todo and an external item. Key attributes: local todo reference, external item reference, link type (manual/auto-detected).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create a new todo in under 5 seconds from the main screen.
- **SC-002**: The app launches and displays the todo list in under 2 seconds, even with 1,000+ items across local and external sources.
- **SC-003**: Users can find any item (local or external) via search in under 10 seconds.
- **SC-004**: External source items appear within 30 seconds of the initial connection being configured.
- **SC-005**: 90% of users can configure an external source connection on their first attempt without consulting documentation.
- **SC-006**: The app remains fully functional for local todo management when all external sources are unavailable.
- **SC-007**: Users report at least a 30% reduction in context-switching between tools after adopting the unified view.
- **SC-008**: All local todo operations (create, edit, complete, delete) complete with no perceptible delay.

## Assumptions

- The app builds on the existing terminal UI (Bubble Tea) architecture from Feature 001, extending it with local todo management as the primary experience.
- External sources include at minimum the three already supported (Jira, Bitbucket, Email) with an extensible architecture for adding more (GitHub, Trello, Asana, etc.).
- The app is designed for individual users managing their personal task workflow, not team collaboration.
- Offline-first for local todos: all local operations work without any network connectivity.
- Data is stored locally on the user's machine; no cloud sync between devices is required.
- The existing secure credential storage (system keyring) is reused for external source authentication.

## Out of Scope

- Multi-user collaboration or shared task lists.
- Cloud sync or cross-device synchronization of local todos.
- Mobile or web interfaces (terminal UI only for this feature).
- Two-way sync of local todo changes back to external sources (external items are managed via source-specific actions, not by editing them as if they were local todos).
- Calendar or time-tracking integration.
- Recurring/repeating todo support (can be added in a future feature).
