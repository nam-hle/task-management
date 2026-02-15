# Feature Specification: Application & Browser Time Tracking

**Feature Branch**: `005-app-time-tracking`
**Created**: 2026-02-14
**Status**: Draft
**Input**: User description: "implement time tracking for application, firefox + chrome tabs for jira and bitbucket"

## Clarifications

### Session 2026-02-14

- Q: Should this be part of the 004 macOS todo app or a standalone application? → A: Integrated into the 004 macOS todo app — shares data layer (SwiftData), time entries link to todos.
- Q: How should the app handle the macOS Accessibility permission requirement? → A: Guided first-run prompt — explain why the permission is needed, deep-link to System Settings, disable tracking until granted.
- Q: When the system detects a Jira ticket or Bitbucket PR in a browser tab, should it auto-link the time entry to a matching todo? → A: Auto-link silently. The app has API access to Jira and Bitbucket (using credentials from 004's integrations) to fetch ticket/PR details for more accurate context extraction beyond just tab titles.
- Q: Should the system track all user-selected applications, or only Firefox and Chrome? → A: All user-selected applications. Firefox and Chrome are pre-configured with browser context detection. Additionally, the system reads WakaTime data from IntelliJ to centralize coding time with project/file-level context.
- Q: When does a time entry move from "unreviewed" to "reviewed"? → A: User manually reviews entries for correctness. Once a pattern is confirmed (e.g., context + todo linkage), the app remembers it and auto-approves matching entries on subsequent days.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Active Application Time Tracking (Priority: P1)

As a developer, I want the system to automatically track how long I spend in each application so that I have an accurate, effortless record of my work time without manual logging.

The system monitors which application is currently in the foreground and records time entries automatically. When I switch from one application to another, the system detects the change and starts a new time segment for the newly focused app. Brief switches (under 30 seconds) are ignored and the time is attributed to the previous application. At any point, I can see a real-time breakdown of how I've spent my day across applications.

**Why this priority**: This is the foundational capability. Without knowing which application is active, the system cannot determine context or attribute time. All other stories depend on this core tracking loop.

**Independent Test**: Can be fully tested by starting the tracker, switching between 3-4 applications over 10 minutes, and verifying that time segments are recorded with correct durations and application names.

**Acceptance Scenarios**:

1. **Given** time tracking is active, **When** I switch to a new application and spend more than 30 seconds in it, **Then** a time entry is created for the previous application with the correct duration and the new application becomes the active tracking target.
2. **Given** time tracking is active, **When** I briefly switch to another application for less than 30 seconds and switch back, **Then** no separate time entry is created for the brief switch and the time is attributed to the original application.
3. **Given** time tracking is active, **When** my computer becomes idle (no keyboard/mouse input) for more than 5 minutes, **Then** idle time is excluded from the active time entry.
4. **Given** time tracking is active, **When** I view the tracking dashboard, **Then** I see a live breakdown of today's time by application with running totals.
5. **Given** time tracking is active, **When** my computer goes to sleep or the screen locks, **Then** the current time entry is paused and resumes when the computer wakes or unlocks.

---

### User Story 2 - Browser Tab Context Detection for Jira and Bitbucket (Priority: P2)

As a developer, I want the system to detect when I'm viewing Jira tickets or Bitbucket PRs in Firefox or Chrome and automatically capture the specific ticket ID or PR details so that my time entries contain meaningful work context without any manual input.

When Firefox or Chrome is the active application, the system reads the active tab's title and URL to identify Jira and Bitbucket pages. For Jira, it extracts the ticket ID (e.g., PROJ-123) and ticket summary. For Bitbucket, it extracts the PR number, repository name, and PR title. This context is attached to the time entry, transforming generic "Chrome" entries into specific "Reviewing PR #42 in my-repo" or "Analyzing PROJ-123: Fix login bug" entries.

**Why this priority**: Raw application-level tracking (P1) only tells you "spent 2 hours in Chrome." Context detection transforms this into actionable data — "spent 45 min on PROJ-123, 30 min reviewing PR #42." Without this, users would still need to manually annotate every time block.

**Independent Test**: Can be fully tested by opening a Jira ticket in Firefox and a Bitbucket PR in Chrome, spending time on each, and verifying the recorded entries include the correct ticket ID, PR number, and titles.

**Acceptance Scenarios**:

1. **Given** time tracking is active and Chrome is focused, **When** the active tab is a Jira ticket page (e.g., title contains "PROJ-123"), **Then** the time entry captures the ticket ID (PROJ-123) and the ticket summary from the page title.
2. **Given** time tracking is active and Firefox is focused, **When** the active tab is a Bitbucket PR page, **Then** the time entry captures the PR number, repository name, and PR title.
3. **Given** the user switches between multiple browser tabs, **When** the active tab changes from one Jira ticket to another, **Then** a new time entry begins for the new ticket (subject to the 30-second minimum threshold).
4. **Given** the user is in Chrome on a non-Jira, non-Bitbucket page, **When** time is tracked, **Then** the entry is recorded as generic browser usage without specific context.
5. **Given** time tracking is active, **When** the user has multiple browser windows but only one is focused, **Then** only the focused window's active tab is used for context detection.

---

### User Story 3 - Review and Edit Tracked Time Entries (Priority: P3)

As a developer, I want to review my tracked time entries, merge short entries, adjust durations, and add notes so that my time records are clean and accurate before I use them for reporting or booking.

The system presents a daily summary of all tracked time entries. I can see entries grouped by application and context (Jira ticket, Bitbucket PR). I can merge consecutive entries for the same context, split long entries, adjust start and end times, and add descriptive notes. Entries that were automatically tracked show their source context, while manual adjustments are clearly indicated.

**Why this priority**: Automatically tracked data is rarely perfect — interruptions, brief context switches, and misdetected contexts require manual cleanup. This editing layer ensures data quality before any downstream use.

**Independent Test**: Can be fully tested by generating sample time entries, opening the review view, performing edits (merge two entries, adjust a duration, add a note), and verifying all changes persist correctly.

**Acceptance Scenarios**:

1. **Given** I have 15 time entries tracked for today, **When** I open the time review view, **Then** I see all entries listed with application name, context (ticket/PR), duration, and timestamps, grouped by context.
2. **Given** I see two consecutive entries for the same Jira ticket, **When** I select both and choose "merge", **Then** they combine into a single entry with the total duration and the earliest start time and latest end time.
3. **Given** I see a 2-hour entry, **When** I split it at the 1-hour mark, **Then** two separate entries appear with adjusted times and both retain the original context.
4. **Given** I have an entry with an incorrect duration, **When** I manually adjust the start or end time, **Then** the duration recalculates and the entry is marked as manually edited.

---

### User Story 4 - Start/Stop Manual Timer (Priority: P4)

As a developer, I want to manually start and stop a timer for specific activities that the automatic tracker cannot detect (e.g., meetings, thinking time, offline work) so that all my work time is captured.

I can start a manual timer with an optional label and context. While a manual timer runs, it takes precedence over automatic tracking. I can pause, resume, and stop the manual timer. The resulting entry appears in the same review view alongside automatically tracked entries.

**Why this priority**: Automatic tracking covers application usage but misses non-computer activities (meetings, whiteboard sessions, phone calls). Manual timers fill this gap, providing complete time coverage.

**Independent Test**: Can be fully tested by starting a manual timer with a label, waiting 5 minutes, stopping it, and verifying the entry appears in the review view with the correct duration and label.

**Acceptance Scenarios**:

1. **Given** I click "Start Timer", **When** I provide a label "Sprint Planning Meeting", **Then** a running timer appears showing elapsed time with the given label.
2. **Given** a manual timer is running, **When** I click "Stop", **Then** a time entry is recorded with the start time, end time, duration, and label.
3. **Given** a manual timer is running, **When** automatic tracking detects an application switch, **Then** the manual timer continues uninterrupted and the automatic detection is suppressed until the manual timer is stopped.
4. **Given** only one timer can be active at a time, **When** I start a new manual timer while one is already running, **Then** the running timer is stopped (creating its entry) and the new timer begins.

---

### User Story 5 - Export Formatted Time Summary (Priority: P5)

As a developer, I want to export my reviewed time entries as a formatted summary so that I can easily book time to external systems like Timension.

After reviewing and cleaning up my time entries, I trigger an export. The system generates a copy-ready summary grouped by context (Jira ticket, Bitbucket PR, or custom label) with total durations. I copy this output and use it for time booking. Exported entries are marked to prevent duplicate exports.

**Why this priority**: This is the ultimate output — converting tracked time into bookable data. It depends on all previous stories (tracking, context detection, review) being functional.

**Independent Test**: Can be fully tested by preparing reviewed time entries, triggering the export, and verifying the output is correctly formatted, grouped, and copyable.

**Acceptance Scenarios**:

1. **Given** I have 8 reviewed time entries for today, **When** I trigger "Export Summary", **Then** a formatted summary is generated showing entries grouped by Jira ticket/PR/label with total durations per group and a daily total.
2. **Given** I have exported entries, **When** I mark them as "booked", **Then** the entries are flagged and excluded from future exports.
3. **Given** I have already exported entries for today, **When** I trigger export again without new entries, **Then** the system warns me about duplicate exports and asks for confirmation.
4. **Given** a time entry has a linked Jira ticket context, **When** the export is generated, **Then** the Jira ticket ID and summary are included in the entry description.

---

### Edge Cases

- What happens when the user has both Firefox and Chrome open with Jira/Bitbucket tabs? Only the browser that is currently focused and its active tab are tracked.
- What happens when a Jira ticket ID cannot be parsed from the tab title? The entry is recorded as generic browser usage with the raw tab title stored for manual review.
- What happens when the user uses a private/incognito browser window? Tab title detection still works if the browser exposes the window title to the accessibility layer; if not, the entry is recorded as generic browser usage.
- What happens when the user rapidly alt-tabs between applications? Switches under 30 seconds are ignored and time is attributed to the previous entry.
- What happens when the computer wakes from sleep? The idle/sleep period is excluded from any active time entry, and tracking resumes from the wake-up time.
- What happens when the app crashes during active tracking? In-progress entries are auto-saved every 60 seconds. On restart, partial entries are recovered up to the last save point, losing at most 60 seconds of data.
- What happens when entries cross midnight? Time entries are automatically split at the midnight boundary into two separate daily entries.
- What happens when no browser is running? The system tracks only application-level time without browser context. No errors or warnings are shown.
- What happens when Firefox or Chrome updates and changes its window title format? The context extraction rules are user-configurable, allowing the user to update patterns without waiting for a system update.
- What happens when the Accessibility permission is not granted? Automatic time tracking and browser tab detection are disabled. Manual timers remain functional. A persistent prompt guides the user to grant the permission.
- What happens when WakaTime is not installed or configured? The system falls back to window-title-based tracking for IntelliJ and other IDEs. No error is shown; WakaTime integration is treated as an optional enhancement.
- What happens when WakaTime data overlaps with window-monitoring data for the same time period? WakaTime data takes precedence and the window-monitoring entry is replaced, since WakaTime provides richer context (project, file, branch).
- What happens when a learned pattern becomes stale (e.g., a Jira ticket is closed or a todo is completed)? The system continues to apply the pattern but flags the entry for manual review with a staleness indicator. The user can revoke the pattern from settings.

## Requirements *(mandatory)*

### Functional Requirements

**Active Window Monitoring**

- **FR-001**: System MUST detect the currently focused/active application window and record which application is in use.
- **FR-002**: System MUST detect idle periods (configurable threshold, default 5 minutes of no keyboard/mouse input) and exclude them from active time entries.
- **FR-003**: System MUST detect computer sleep/lock events and pause time tracking, resuming on wake/unlock.
- **FR-004**: System MUST ignore application switches shorter than a configurable minimum duration (default 30 seconds), attributing that time to the previously active entry.
- **FR-005**: System MUST split time entries that cross midnight into separate daily entries.

**Browser Tab Context Detection**

- **FR-006**: System MUST detect the active tab title and URL in Firefox when it is the focused application.
- **FR-007**: System MUST detect the active tab title and URL in Chrome when it is the focused application.
- **FR-008**: System MUST extract Jira ticket identifiers (matching patterns like `[A-Z]+-\d+`) from browser tab titles and verify/enrich them by fetching ticket details (summary, status, assignee) via the Jira API using credentials configured in the 004 todo app's Jira integration.
- **FR-009**: System MUST extract Bitbucket PR identifiers (repository name and PR number) from browser tab titles or URLs and verify/enrich them by fetching PR details (title, status, author, reviewers) via the Bitbucket API using credentials configured in the 004 todo app's Bitbucket integration.
- **FR-010**: System MUST allow users to configure context extraction patterns for different websites, including custom patterns beyond Jira and Bitbucket.
- **FR-011**: System MUST track only the focused browser window's active tab — background windows and tabs are not tracked.
- **FR-011a**: When a detected Jira ticket ID or Bitbucket PR matches a linked todo (from 004's Jira/Bitbucket integrations), the system MUST automatically attach the time entry to that todo without user confirmation.
- **FR-011b**: When a detected identifier does not match any linked todo, the time entry MUST be recorded as an unlinked entry available for manual association in the review view.

**WakaTime Integration**

- **FR-011c**: System MUST import coding activity data from WakaTime (via its local data or API) to create time entries with project, file, language, and branch context.
- **FR-011d**: When IntelliJ is the active application, the system MUST prefer WakaTime-sourced data over window-title-based tracking for richer context (project name, branch, files edited).
- **FR-011e**: WakaTime-imported entries MUST be deduplicated against window-monitoring entries for the same time period — WakaTime data takes precedence when both sources overlap.
- **FR-011f**: System MUST allow users to configure WakaTime data access (API key or local data file path).

**Time Entry Management**

- **FR-012**: System MUST persist all tracked time entries locally with: application name, browser context (if applicable), start time, end time, duration, and source (automatic or manual).
- **FR-013**: System MUST provide a daily review view showing all entries with application, context, duration, and timestamps.
- **FR-014**: System MUST allow users to merge two or more time entries into a single entry with combined duration.
- **FR-015**: System MUST allow users to split a time entry at a specified point into two entries.
- **FR-016**: System MUST allow users to manually adjust start time, end time, and duration of any entry.
- **FR-017**: System MUST allow users to add, edit, and delete notes on time entries.
- **FR-018**: System MUST clearly indicate which entries were automatically tracked versus manually edited.

**Manual Timer**

- **FR-019**: System MUST allow users to start a manual timer with an optional label and context description.
- **FR-020**: System MUST allow users to pause, resume, and stop a manual timer.
- **FR-021**: System MUST enforce that only one timer (manual or automatic context) is actively recording at a time.
- **FR-022**: While a manual timer is running, automatic context detection MUST be suppressed.

**Export and Booking**

- **FR-023**: System MUST generate a copy-ready formatted summary of reviewed time entries, grouped by context with totals.
- **FR-024**: System MUST track export/booking status per time entry (unreviewed, reviewed, exported, booked) to prevent duplicate exports.
- **FR-024a**: Time entries start as "unreviewed" and move to "reviewed" only when the user explicitly confirms them in the review view (individually or in bulk).
- **FR-024b**: System MUST learn from confirmed review patterns. When the user reviews and confirms a time entry (e.g., "Chrome tab with PROJ-123 linked to todo X"), the system MUST remember that pattern (context type + identifier + todo linkage) and auto-approve matching entries on subsequent days without requiring manual review.
- **FR-024c**: Auto-approved entries MUST be visually distinguishable from manually reviewed entries, so the user can spot-check the system's learned decisions.
- **FR-024d**: System MUST allow users to revoke or edit a learned pattern if it becomes incorrect (e.g., a ticket is reassigned to a different todo).
- **FR-025**: System MUST warn users when attempting to re-export previously exported entries.
- **FR-026**: System MUST include Jira ticket IDs and Bitbucket PR identifiers in exported entry descriptions when available.

**Data Persistence and Recovery**

- **FR-027**: System MUST auto-save in-progress time entries every 60 seconds.
- **FR-028**: On restart after a crash or unexpected shutdown, the system MUST recover partial entries up to the last auto-save point.
- **FR-029**: System MUST retain time entries for 90 days. Booked entries older than 90 days are automatically purged. Unbooked entries older than 90 days are flagged as overdue rather than deleted.

**Configuration**

- **FR-030**: System MUST allow users to configure which applications to track (allowlist approach — only explicitly selected apps are tracked). Firefox and Chrome MUST be pre-configured with browser context detection enabled. Other common dev tools (IntelliJ, Xcode, Terminal, VS Code, Slack) MUST be available as suggested additions.
- **FR-031**: System MUST allow users to enable or disable automatic time tracking independently of manual timers.
- **FR-032**: System MUST allow users to configure the idle timeout threshold, minimum switch duration, and auto-save interval.
- **FR-033**: On first launch (or when permission is missing), the system MUST display a guided prompt explaining why Accessibility permission is needed, provide a direct link to System Settings > Privacy & Security > Accessibility, and disable automatic time tracking until the permission is granted. Manual timers remain functional without this permission.

### Key Entities

- **Time Entry**: A recorded period of activity. Attributes: application name, browser context (Jira ticket ID/Bitbucket PR with API-enriched details), WakaTime context (project, file, language, branch — when sourced from WakaTime), linked todo (auto-linked when context matches a todo's Jira/Bitbucket link, or manually assigned), start time, end time, duration, notes, source (automatic/manual/edited/wakatime), export status (unreviewed/reviewed/exported/booked), label (for manual entries).
- **Tracked Application**: A configured application to monitor. Attributes: application name, whether browser context detection is enabled, context extraction patterns.
- **Browser Context Rule**: A pattern for extracting context from browser tabs. Attributes: URL pattern, title extraction regex, context type (Jira/Bitbucket/custom), associated fields to extract.
- **Learned Pattern**: A validated association between a detected context and a todo. Attributes: context type (Jira/Bitbucket/WakaTime/custom), identifier pattern (e.g., ticket ID, PR number, project name), linked todo, confirmation count (how many times reviewed and confirmed), last confirmed date, active status (can be revoked).
- **Export Record**: A generated export batch. Attributes: linked time entries, export timestamp, formatted output text, whether entries have been confirmed as booked.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can view a real-time breakdown of their daily application usage within 2 seconds of opening the tracking dashboard.
- **SC-002**: 95% of Jira ticket IDs are correctly extracted from Firefox and Chrome tab titles without manual correction.
- **SC-003**: 95% of Bitbucket PR identifiers are correctly extracted from Firefox and Chrome tab titles without manual correction.
- **SC-004**: Time tracking accuracy is within 1 minute of actual application usage per hour-long session.
- **SC-005**: Users can review and clean up a full day's time entries (20+ entries) in under 5 minutes.
- **SC-006**: Users can generate an export-ready summary of a full day's time in a single action taking under 10 seconds.
- **SC-007**: No more than 60 seconds of tracking data is lost in the event of an unexpected shutdown.
- **SC-008**: Time tracking operates in the background with no perceptible impact on system responsiveness.

## Assumptions

- The user accesses Jira and Bitbucket through Firefox and/or Chrome web browsers, and relevant identifiers (ticket IDs, PR numbers) are present in browser tab titles or URLs.
- The user runs macOS, which provides accessibility APIs for reading the active application window and browser tab information.
- Firefox and Chrome expose active tab titles through their window titles or through accessibility interfaces that the system can read.
- The user has a relatively stable set of applications they want to track, configured once and updated infrequently.
- Idle detection relies on system-level inactivity signals (no keyboard/mouse input for a configurable threshold).
- This feature is integrated into the existing macOS todo app (004), sharing its SwiftData layer. Time entries link to todos, and the time tracking UI is part of the main app window and menu bar component.
- Timension is a web app without a programmatic API; the system generates copy-ready formatted output for manual entry.
- The user works primarily on a single display or has a clear primary display where the focused window is tracked.
