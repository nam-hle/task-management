# Feature Specification: Native macOS Todo App

**Feature Branch**: `004-macos-todo-app`
**Created**: 2026-02-14
**Status**: Draft
**Input**: User description: "Native macOS todo app with Jira, Bitbucket, and time tracking"

## Clarifications

### Session 2026-02-14

- Q: Can a todo link to multiple Jira tickets or Bitbucket PRs? → A: No. One-to-one: each todo links to at most 1 Jira ticket and 1 Bitbucket PR.
- Q: What is the app window style? → A: Standard window + menu bar timer. Main window for todo management, menu bar component shows active timer and quick actions (start/stop/switch todo).
- Q: What is the Timension export format? → A: Deferred. Timension booking requires interacting with its web UI (not just text paste). The time booking/export feature will be detailed in a future iteration.
- Q: What happens when a todo is deleted? → A: Soft delete. Todo moves to trash, can be restored within 30 days. Time entries and links are preserved. After 30 days, permanently purged.
- Q: Should todos support subtasks or checklists? → A: No. Todos are flat — use the description field for notes. No subtasks or checklist items.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Todo Management (Priority: P1)

As a developer, I want a native macOS app where I can create, organize, and manage my todos so that I have a single place to track all my work.

I open the app and see my todo list. I can quickly add a new todo with a title, assign it a priority (high, medium, low), group it under a project, and tag it. I can mark todos as complete, edit them, reorder them, and filter/search across all my todos. The app persists everything locally — I never lose data.

**Why this priority**: The todo list is the foundation. Per the constitution (Principle I: Todo-First Design), the app MUST be useful as a standalone todo manager with zero integrations. Every other feature builds on top of todos.

**Independent Test**: Can be fully tested by creating 10+ todos across 2 projects with various priorities and tags, then filtering, completing, and searching to verify all CRUD operations work correctly.

**Acceptance Scenarios**:

1. **Given** the app is open, **When** I press the "add todo" shortcut, **Then** a new todo input appears and I can type a title and press Enter to create it.
2. **Given** I have 20 todos, **When** I type in the search/filter bar, **Then** the list filters in real-time to show only matching todos.
3. **Given** I have a todo, **When** I click the checkbox or press the complete shortcut, **Then** the todo is marked as done with a completion timestamp and moves to the completed section.
4. **Given** I have todos in different projects, **When** I select a project in the sidebar, **Then** only todos belonging to that project are shown.
5. **Given** I quit and reopen the app, **When** the app loads, **Then** all my todos, projects, and tags are exactly as I left them.

---

### User Story 2 - Jira Ticket Linking (Priority: P2)

As a developer, I want to link my todos to Jira tickets so that I can see ticket status, details, and context directly in my todo list without switching to the browser.

I select a todo and choose "Link Jira ticket". I enter the ticket ID (e.g., PROJ-123) or search for tickets. The app fetches the ticket summary, status, and assignee from Jira and displays them alongside the todo. When the Jira ticket status changes, the linked information updates on the next sync. I can also create a todo directly from a Jira ticket.

**Why this priority**: Jira is central to daily work. Linking tickets to todos bridges the gap between personal task tracking and team project management. This is the most frequently used integration.

**Independent Test**: Can be fully tested by configuring Jira credentials, linking a todo to an existing Jira ticket, and verifying the ticket summary, status, and assignee appear on the todo. Then change the ticket status in Jira and verify it updates after sync.

**Acceptance Scenarios**:

1. **Given** I have configured my Jira credentials, **When** I link a todo to ticket "PROJ-123", **Then** the todo displays the ticket summary, status, and assignee fetched from Jira.
2. **Given** a todo is linked to a Jira ticket whose status changes from "In Progress" to "Done", **When** the app syncs, **Then** the displayed status updates to "Done".
3. **Given** I am offline, **When** I view a todo linked to a Jira ticket, **Then** I see the last synced ticket information with a staleness indicator showing when it was last updated.
4. **Given** I want to create a todo from Jira, **When** I use the "Import from Jira" action and select a ticket, **Then** a new todo is created with the ticket title and the link is established automatically.

---

### User Story 3 - Bitbucket PR Linking (Priority: P3)

As a developer, I want to link my todos to Bitbucket pull requests so that I can track code review status alongside my todo list.

I select a todo and choose "Link Bitbucket PR". I enter the PR URL or search by repository and PR number. The app fetches PR title, status (open, merged, declined), author, and reviewer information. I can see at a glance which of my todos have open PRs that need attention.

**Why this priority**: PR reviews are a core developer activity. Linking PRs to todos creates visibility into code review workload without context-switching to Bitbucket.

**Independent Test**: Can be fully tested by configuring Bitbucket credentials, linking a todo to an existing PR, and verifying the PR title, status, and reviewers appear on the todo.

**Acceptance Scenarios**:

1. **Given** I have configured my Bitbucket credentials, **When** I link a todo to PR #42 in repository "my-repo", **Then** the todo displays the PR title, status, author, and reviewers.
2. **Given** a todo is linked to an open PR that gets merged, **When** the app syncs, **Then** the PR status updates to "Merged".
3. **Given** I am offline, **When** I view a todo linked to a Bitbucket PR, **Then** I see the last synced PR information with a staleness indicator.
4. **Given** I have multiple todos with linked PRs, **When** I filter by "has open PR", **Then** only todos with open (unmerged) PRs are shown.

---

### User Story 4 - Time Tracking per Todo (Priority: P4)

As a developer, I want to track time spent on each todo so that I know how long tasks take and can prepare time entries for booking to Timension.

I select a todo and start a timer. The app tracks elapsed time while I work. I can pause and resume the timer, or manually add time entries. When I'm done, I stop the timer and the time is recorded against that todo. At the end of the day, I can review all time entries, edit durations, and export a formatted summary for pasting into the Timension web app.

**Why this priority**: Time tracking depends on having todos to track against (P1). It's the final integration piece that connects daily work to company time booking.

**Independent Test**: Can be fully tested by starting a timer on a todo, working for 5 minutes, stopping it, then reviewing the time entry and exporting a formatted summary.

**Acceptance Scenarios**:

1. **Given** I have a todo, **When** I click "Start Timer", **Then** a running timer appears on the todo showing elapsed time.
2. **Given** a timer is running on a todo, **When** I click "Stop", **Then** a time entry is recorded with the start time, end time, and duration.
3. **Given** I have 5 todos with time entries for today, **When** I open the time review view, **Then** I see all entries grouped by todo with total time per todo and a daily total.
4. **Given** I have reviewed my time entries, **When** I trigger "Export for Timension", **Then** a copy-ready formatted summary is generated that I can paste into the Timension web app.
5. **Given** I have a todo linked to Jira ticket "PROJ-123", **When** I export time for that todo, **Then** the export includes the Jira ticket ID in the description.
6. **Given** a timer is running and the app quits unexpectedly, **When** I reopen the app, **Then** the in-progress time entry is recovered up to the last auto-save point.

---

### User Story 5 - Automatic App Time Detection (Priority: P5)

As a developer, I want the app to automatically detect when I'm working in Bitbucket or Jira in my browser and suggest linking that time to relevant todos, so that I don't forget to track time for code reviews and ticket analysis.

The app monitors the active window in the background. When it detects I'm viewing a Jira ticket or Bitbucket PR in my browser, it matches the identifier against linked todos. If a match is found, the app suggests attributing that time to the corresponding todo. If no match is found, it offers to create a new time entry or link the activity to an existing todo.

**Why this priority**: This is the most advanced feature — it depends on todos (P1), Jira linking (P2), Bitbucket linking (P3), and time tracking (P4) all working. It automates what would otherwise be manual time tracking.

**Independent Test**: Can be fully tested by opening a Jira ticket in the browser that matches a linked todo, waiting 30+ seconds, and verifying the app suggests attributing that time to the todo.

**Acceptance Scenarios**:

1. **Given** I have a todo linked to "PROJ-123" and I switch to a browser tab showing "PROJ-123" in Jira, **When** I've been on that tab for more than 30 seconds, **Then** the app suggests attributing time to the linked todo.
2. **Given** the app detects I'm viewing a Jira ticket with no linked todo, **When** it notifies me, **Then** I can choose to create a new todo and link it, link to an existing todo, or dismiss.
3. **Given** my computer has been idle for more than 5 minutes, **When** activity resumes, **Then** the idle period is excluded from any suggested time entries.
4. **Given** I prefer not to use automatic detection, **When** I disable it in settings, **Then** no background window monitoring occurs.

---

### Edge Cases

- What happens when the user has no internet connection? All local features (todo CRUD, time tracking, export) work normally. Jira/Bitbucket data shows last synced state with a staleness indicator.
- What happens when Jira/Bitbucket credentials expire? The app shows a clear notification and guides the user to re-authenticate. Previously synced data remains visible.
- What happens when a linked Jira ticket or Bitbucket PR is deleted? The link is marked as broken with a visual indicator. The todo itself is unaffected.
- What happens when the user tracks time across midnight? The time entry is split at the day boundary into two entries.
- What happens when two timers are started simultaneously? Only one timer can be active at a time. Starting a new timer pauses the currently running one.
- What happens when the app is quit while a timer is running? The timer state is auto-saved every 60 seconds. On restart, the entry is recovered up to the last save.
- What happens when a todo with time entries and links is deleted? It moves to trash with all linked data preserved. It can be restored within 30 days. After 30 days, it is permanently purged.

## Requirements *(mandatory)*

### Functional Requirements

**Todo Management (Core)**

- **FR-001**: System MUST allow users to create todos with a title (required), description (optional), priority (high/medium/low, default: medium), and due date (optional).
- **FR-002**: System MUST allow users to organize todos into projects and assign multiple tags.
- **FR-003**: System MUST allow users to mark todos as complete or reopen them.
- **FR-004**: System MUST support searching and filtering todos by title, project, tag, priority, completion status, and linked integration status.
- **FR-005**: System MUST persist all data locally. The app MUST function fully without any network connection.
- **FR-006**: System MUST support keyboard shortcuts for all primary actions (create, complete, delete, search, navigate).
- **FR-006a**: System MUST soft-delete todos — deleted todos move to a trash view, preserving all linked data (time entries, Jira/PR links). Todos in trash can be restored within 30 days, after which they are permanently purged.

**Jira Integration**

- **FR-007**: System MUST allow users to configure Jira server credentials (server URL, authentication token) stored securely in the OS credential store.
- **FR-008**: System MUST allow users to link a todo to a Jira ticket by entering a ticket ID or searching for tickets.
- **FR-009**: System MUST fetch and display Jira ticket summary, status, and assignee for linked todos.
- **FR-010**: System MUST periodically sync linked Jira ticket data (configurable interval, default: 15 minutes).
- **FR-011**: System MUST allow users to create a todo from a Jira ticket, automatically establishing the link.

**Bitbucket Integration**

- **FR-012**: System MUST allow users to configure Bitbucket credentials (server URL, authentication token) stored securely in the OS credential store.
- **FR-013**: System MUST allow users to link a todo to a Bitbucket PR by entering a PR URL or searching by repository and PR number.
- **FR-014**: System MUST fetch and display PR title, status (open/merged/declined), author, and reviewers for linked todos.
- **FR-015**: System MUST periodically sync linked Bitbucket PR data (configurable interval, default: 15 minutes).

**Time Tracking**

- **FR-016**: System MUST allow users to start, pause, and stop a timer on any todo.
- **FR-017**: System MUST enforce that only one timer is active at a time — starting a new timer pauses the running one.
- **FR-018**: System MUST allow users to manually add, edit, and delete time entries on any todo.
- **FR-019**: System MUST provide a daily time review view showing all entries grouped by todo with per-todo and daily totals.
- **FR-020**: System MUST support exporting/booking time entries to Timension. The exact integration method (browser automation, formatted export, or other) is deferred to a future iteration.
- **FR-021**: System MUST track booking status per time entry to prevent duplicate bookings.
- **FR-022**: System MUST auto-save in-progress timer state every 60 seconds and recover on restart.
- **FR-023**: System MUST split time entries that cross midnight into separate daily entries.
- **FR-024**: System MUST ignore window switches shorter than 30 seconds when performing automatic time detection (P5).

**Automatic Detection (P5)**

- **FR-025**: System MUST detect the active application window and extract identifiers (Jira ticket IDs, Bitbucket PR numbers) from browser window titles.
- **FR-026**: System MUST match detected identifiers against linked todos and suggest attributing time to matching todos.
- **FR-027**: System MUST allow users to enable or disable automatic window detection in settings.
- **FR-028**: System MUST detect idle periods (configurable threshold, default: 5 minutes) and exclude them from suggested time entries.

### Key Entities

- **Todo**: Central entity. Attributes: title, description, priority (high/medium/low), due date, completion status, completion timestamp, project, tags, linked Jira ticket, linked Bitbucket PR, time entries, created date, sort order.
- **Project**: Grouping for todos. Attributes: name, color, description, sort order.
- **Tag**: Label for todos. Attributes: name, color. A todo can have multiple tags.
- **Jira Link**: Connection between a todo and a Jira ticket. Attributes: ticket ID, server URL, cached summary, cached status, cached assignee, last synced timestamp.
- **Bitbucket Link**: Connection between a todo and a Bitbucket PR. Attributes: repository slug, PR number, server URL, cached title, cached status, cached author, cached reviewers, last synced timestamp.
- **Time Entry**: A recorded period of work on a todo. Attributes: linked todo, start time, end time, duration, notes, export status (unreviewed/reviewed/exported), source (manual/timer/auto-detected).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create a new todo in under 3 seconds using a keyboard shortcut.
- **SC-002**: The app launches and displays the todo list within 2 seconds.
- **SC-003**: Searching/filtering across 500+ todos returns results instantly (under 200ms perceived).
- **SC-004**: Linked Jira ticket and Bitbucket PR data appears on todos within one sync cycle (default 15 minutes) of external changes.
- **SC-005**: Users can review and export a full day's time entries for Timension in under 3 minutes.
- **SC-006**: The app functions fully offline for all local operations (todo CRUD, time tracking, export) with zero degradation.
- **SC-007**: 95% of automatically detected Jira ticket IDs and Bitbucket PR numbers from browser window titles are correctly matched to linked todos.
- **SC-008**: All data persists across app restarts, OS reboots, and unexpected shutdowns with at most 60 seconds of timer data loss.

## Assumptions

- The user has a single Jira server and a single Bitbucket server to connect to (multi-server support is out of scope for this version).
- Jira and Bitbucket are Atlassian Server/Data Center or Cloud instances accessible via REST API with personal access tokens.
- The user accesses Jira and Bitbucket through a web browser for automatic detection (P5), with identifiers present in browser tab/window titles.
- Timension is a web app without a programmatic API; the system exports copy-ready formatted text for manual pasting.
- The app runs as a standard macOS application with a main window for todo management, plus a menu bar component that shows the active timer and provides quick actions (start/stop/switch todo). The menu bar component persists when the main window is closed.
- This is a single-user application — no multi-user collaboration or sharing features.
