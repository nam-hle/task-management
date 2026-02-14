# Feature Specification: App Time Tracking for Timension

**Feature Branch**: `003-app-time-tracking`
**Created**: 2026-02-14
**Status**: Draft
**Input**: User description: "I want to track all app time usages for booking time to my internal company time tracking called Timension. You need to track time I review code in Bitbucket PRs, ticket analysis in Jira."

## Clarifications

### Session 2026-02-14

- Q: How does the user book time to Timension today? → A: Timension is a web app. The system will generate copy-ready formatted time entries that the user pastes into the Timension web UI manually.
- Q: What is the minimum time segment duration before creating a time entry? → A: 30 seconds. Window switches shorter than 30 seconds are ignored and the time is attributed to the previous entry.
- Q: Should time tracking be part of the existing TUI or a separate process? → A: Part of the existing TUI — integrated as a new view/tab within the current task manager application, reusing the existing data layer and UI patterns.
- Q: How long should tracked time entries be retained? → A: 90 days. Booked entries older than 90 days are purged automatically.
- Q: What happens to in-progress tracking if the app crashes? → A: Auto-save every 60 seconds. On restart, the partial entry is recovered up to the last save point.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Time Tracking of App Usage (Priority: P1)

As a developer, I want the system to automatically track how long I spend in different applications (Bitbucket, Jira, etc.) so that I have an accurate record of my work time without manual effort.

The system monitors which application windows are active and records time entries automatically. When I switch from Jira to Bitbucket, the system detects the change and starts a new time segment. At the end of my work session, I can see a breakdown of how much time I spent in each application.

**Why this priority**: This is the foundational capability — without automatic time tracking, there is nothing to book to Timension. All other features depend on having accurate time data.

**Independent Test**: Can be fully tested by running the tracker, switching between applications for 10 minutes, and verifying that time segments are recorded with correct durations and application names.

**Acceptance Scenarios**:

1. **Given** the time tracker is running, **When** I switch to the Bitbucket window and spend 15 minutes reviewing a PR, **Then** a time entry of approximately 15 minutes is recorded with "Bitbucket" as the application and the PR identifier captured.
2. **Given** the time tracker is running, **When** I switch to Jira and spend 20 minutes analyzing a ticket, **Then** a time entry of approximately 20 minutes is recorded with "Jira" as the application and the ticket identifier captured.
3. **Given** the time tracker is running, **When** I switch to an untracked application (e.g., Spotify), **Then** no time entry is recorded for that application unless it has been configured for tracking.
4. **Given** the time tracker is running, **When** my computer is idle for more than 5 minutes, **Then** the idle time is excluded from any active time entry.

---

### User Story 2 - Contextual Activity Detection (Priority: P2)

As a developer, I want the system to capture what specific activity I'm performing within each application — such as which Bitbucket PR I'm reviewing or which Jira ticket I'm analyzing — so that my time entries contain meaningful context for booking.

The system extracts contextual information from the active application window (e.g., PR number from a Bitbucket browser tab title, Jira ticket ID from the page title). This context is attached to the time entry, enabling precise time booking later.

**Why this priority**: Context-aware tracking transforms raw time data into actionable booking entries. Without it, the user would still need to manually annotate each time block.

**Independent Test**: Can be fully tested by opening a Bitbucket PR in the browser, spending time on it, and verifying the recorded entry includes the PR identifier and repository name.

**Acceptance Scenarios**:

1. **Given** the time tracker is running, **When** I open a Bitbucket PR page (e.g., "Pull Request #42 - Fix login bug"), **Then** the time entry captures the PR number (#42) and PR title.
2. **Given** the time tracker is running, **When** I open a Jira ticket page (e.g., "PROJ-123: Implement user auth"), **Then** the time entry captures the ticket ID (PROJ-123) and ticket summary.
3. **Given** the time tracker is running, **When** I have multiple browser tabs open but only one is active, **Then** only the active tab's context is tracked.

---

### User Story 3 - Review and Edit Time Entries Before Booking (Priority: P3)

As a developer, I want to review my tracked time entries, merge or split them, adjust durations, and categorize them before booking to Timension, so that my bookings are accurate and properly organized.

The system presents a summary of tracked time entries grouped by day. I can review entries, merge short entries into logical blocks, split long entries, adjust start/end times, add notes, and assign categories (e.g., "Code Review", "Ticket Analysis", "Development"). Once satisfied, I confirm the entries for booking.

**Why this priority**: Raw tracked data is rarely perfect — there will be brief switches, interruptions, and context that needs correction. This step ensures booking quality.

**Independent Test**: Can be fully tested by generating sample time entries, opening the review view, editing entries (merge two entries, adjust a duration, add a note), and verifying the changes persist.

**Acceptance Scenarios**:

1. **Given** I have 10 time entries tracked for today, **When** I open the time review view, **Then** I see all entries listed with application, context, duration, and timestamps.
2. **Given** I see two consecutive Bitbucket entries for the same PR, **When** I select both and choose "merge", **Then** they combine into a single entry with the total duration.
3. **Given** I see a 2-hour Jira entry, **When** I split it into two 1-hour entries, **Then** two separate entries appear with adjusted times and I can assign different categories to each.
4. **Given** I have reviewed and edited my entries, **When** I mark them as "ready to book", **Then** the entries are flagged for booking and cannot be accidentally modified.

---

### User Story 4 - Export Time for Timension Booking (Priority: P4)

As a developer, I want my reviewed time entries formatted and ready to copy into the Timension web app so that I can quickly book my time without manual data entry.

The system generates a copy-ready summary of approved time entries, formatted to match the fields required by Timension (project, activity type, duration, description). The user copies this output and pastes it into the Timension web interface. After pasting, the user marks entries as "booked" in the system to prevent re-export.

**Why this priority**: This is the ultimate goal — getting time into Timension. However, it depends on all previous stories being functional. Since Timension is a web app without a programmatic API, the system prepares the data for manual entry rather than submitting directly.

**Independent Test**: Can be fully tested by preparing a set of reviewed time entries, triggering the export action, and verifying the output is correctly formatted and copyable.

**Acceptance Scenarios**:

1. **Given** I have 5 reviewed time entries ready to book, **When** I trigger "Export for Timension", **Then** a formatted summary is displayed that I can copy to clipboard.
2. **Given** I have exported entries and pasted them into Timension, **When** I mark them as "booked" in the system, **Then** the entries are flagged as booked and excluded from future exports.
3. **Given** I have already exported entries for today, **When** I try to export the same entries again, **Then** the system warns me about duplicate exports and asks for confirmation.

---

### Edge Cases

- What happens when the user's computer goes to sleep or is locked? Idle time should be detected and excluded from active tracking.
- What happens when the browser has multiple windows with Bitbucket/Jira? Only the focused/active window should be tracked.
- What happens when the user works across midnight? Time entries should be split at the day boundary.
- What happens when the user closes the app before marking exported entries as booked? The entries remain in "reviewed" state and can be re-exported.
- What happens when the user tracks time for an application not mapped to any Timension project? The entry should remain unbookable until a mapping is configured.
- What happens when the user rapidly alt-tabs between windows? Switches shorter than 30 seconds are ignored and time is attributed to the previous entry.
- What happens if the app crashes during active tracking? The in-progress entry is recovered up to the last auto-save point (every 60 seconds), losing at most 60 seconds of data.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST track time spent in user-configured applications by detecting the active/focused window.
- **FR-002**: System MUST detect idle periods (configurable threshold, default 5 minutes) and exclude them from active time entries.
- **FR-002a**: System MUST ignore window switches shorter than 30 seconds, attributing that time to the previously active entry.
- **FR-003**: System MUST extract contextual identifiers from application window titles (e.g., Jira ticket IDs matching pattern like `[A-Z]+-\d+`, Bitbucket PR numbers).
- **FR-004**: System MUST allow users to configure which applications to track and how to extract context from each.
- **FR-005**: System MUST persist all tracked time entries locally with application name, context, start time, end time, and duration.
- **FR-006**: System MUST provide a review interface where users can view, merge, split, edit, and categorize time entries.
- **FR-007**: System MUST generate copy-ready formatted output of reviewed time entries suitable for pasting into the Timension web app.
- **FR-008**: System MUST prevent duplicate exports by tracking which entries have already been exported and marked as booked.
- **FR-009**: System MUST allow users to mark exported entries as "booked" after they have been entered into Timension.
- **FR-010**: System MUST allow users to configure mappings between tracked applications/contexts and Timension projects/activity types.
- **FR-011**: System MUST support starting and stopping the time tracker manually.
- **FR-012**: System MUST split time entries that cross midnight into separate daily entries.
- **FR-013**: System MUST automatically purge booked time entries older than 90 days. Unbooked entries older than 90 days MUST be flagged as overdue rather than deleted.
- **FR-014**: System MUST auto-save in-progress time entries every 60 seconds. On restart after a crash or unexpected shutdown, the system MUST recover partial entries up to the last save point.

### Key Entities

- **Time Entry**: A recorded period of activity. Attributes: application name, context identifier (PR number, ticket ID), start time, end time, duration, category, notes, booking status (unreviewed, reviewed, booked, failed).
- **Tracked Application**: A configured application to monitor. Attributes: application name, window title pattern for context extraction, associated Timension project mapping.
- **Export Record**: A generated export for Timension. Attributes: linked time entries, export timestamp, formatted output, whether user has confirmed booking in Timension.
- **Activity Category**: A label for the type of work performed. Examples: "Code Review", "Ticket Analysis", "Development", "Meeting". Used for organizing and reporting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can view a complete breakdown of their daily app usage within 5 seconds of opening the review view.
- **SC-002**: 95% of Bitbucket PR and Jira ticket identifiers are correctly extracted from window titles without manual correction.
- **SC-003**: Users can review and prepare a full day's time entries for booking in under 5 minutes.
- **SC-004**: Time tracking accuracy is within 1 minute of actual application usage per session.
- **SC-005**: Users can export a full day's time entries in a copy-ready format in a single action taking under 30 seconds.
- **SC-006**: Exported entries are clearly distinguished from unprocessed entries to prevent duplicate data entry.

## Assumptions

- The user primarily accesses Bitbucket and Jira through a web browser, and relevant identifiers (PR numbers, ticket IDs) are present in browser tab/window titles.
- Timension is a web app without a programmatic API; the system generates copy-ready output for manual entry.
- Time tracking is integrated as a new view within the existing Bubble Tea TUI task manager, sharing its data layer (SQLite) and UI patterns.
- The user has a relatively stable set of applications they want to track, configured once and updated infrequently.
- Idle detection relies on system-level inactivity signals (no keyboard/mouse input).
