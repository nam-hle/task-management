# Feature Specification: Ticket-Centric Plugin System

**Feature Branch**: `006-time-tracking-plugins`
**Created**: 2026-02-15
**Status**: Draft
**Input**: User description: "rewrite to plugin system allow external sources (wakatime, firefox, chrome) contribute to time tracking" + "ticket is the central model, everything should revolve around it"

## Core Concept

**Tickets are the central model.** Every piece of tracked time — whether detected from an IDE via WakaTime, a Jira page in Chrome, a PR in Firefox, or manual app switching — ultimately answers one question: *"How much time did I spend on each ticket today?"*

All time sources — including app tracking, WakaTime, Chrome, and Firefox — are plugins that contribute evidence toward ticket time. There is no special "built-in" source; every source implements the same plugin interface. The system's job is to collect evidence from all active plugins, resolve it to tickets, and present a ticket-centric daily summary ready for time booking.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Ticket-Centric Dashboard (Priority: P1)

As a user, I want my time tracking dashboard organized by tickets, not by sources. When I open the dashboard, I should see a list of tickets I worked on today with the total time per ticket — regardless of whether that time came from coding (WakaTime), browsing (Chrome/Firefox), or app switching. Each ticket shows a breakdown of contributing sources so I can verify the data before booking.

**Why this priority**: The entire purpose of time tracking is to book time against tickets. A ticket-centric dashboard directly serves this goal, whereas the current source-centric view (separate WakaTime/Applications tabs) forces the user to mentally combine data across tabs.

**Independent Test**: Work on ticket PROJ-123 for 30 minutes — 15 minutes coding in IntelliJ (detected by WakaTime via branch name), 10 minutes reviewing a Jira page in Chrome, 5 minutes in Slack discussing it (detected by App Tracking plugin). Open the dashboard and verify PROJ-123 shows 30 minutes total with a source breakdown (WakaTime: 15m, Chrome: 10m, App Tracking: 5m).

**Acceptance Scenarios**:

1. **Given** I worked on multiple tickets today across different tools, **When** I open the dashboard, **Then** I see a list of tickets sorted by total time descending, each showing its accumulated duration from all sources.
2. **Given** a ticket has time from multiple sources (WakaTime + Chrome + app tracking), **When** I expand that ticket, **Then** I see a per-source breakdown with individual time segments.
3. **Given** some tracked time cannot be resolved to a ticket (e.g., Slack with no branch context), **When** I view the dashboard, **Then** unresolved time appears in an "Unassigned" group that I can manually assign to tickets.
4. **Given** two sources report overlapping time for the same ticket (e.g., WakaTime and app tracking both see IntelliJ), **When** the dashboard calculates totals, **Then** overlapping periods are deduplicated so the ticket total reflects actual wall-clock time, not double-counted source time.
5. **Given** a source encounters an error, **When** other sources are healthy, **Then** the dashboard still shows ticket data from working sources with a non-blocking indicator for the failed source.

---

### User Story 2 — Plugin-Based Source Contribution (Priority: P2)

As a user, I want external sources (WakaTime, Chrome, Firefox) to contribute time evidence through a plugin system so that adding new sources in the future doesn't require changing the core ticket model or dashboard. Each plugin independently collects activity data and resolves it to tickets where possible.

**Why this priority**: The plugin abstraction is the enabler for all future sources. WakaTime must be migrated to this pattern first (it's the existing, working integration), then browser plugins can follow the same pattern.

**Independent Test**: After migrating WakaTime to a plugin, verify all existing functionality works identically — branch fetching, ticket inference from branch names, manual overrides, excluded projects. Then enable the Chrome plugin and verify it contributes ticket data alongside WakaTime without any changes to the dashboard or ticket model.

**Acceptance Scenarios**:

1. **Given** WakaTime is configured, **When** the app starts, **Then** the WakaTime plugin discovers its configuration, fetches coding activity, resolves branch names to ticket IDs, and contributes time segments to the ticket model.
2. **Given** Chrome is the active application and I'm viewing a Jira ticket page, **When** the Chrome plugin detects the tab title/URL, **Then** it extracts the ticket ID (e.g., `PROJ-123`) and contributes the browsing time to that ticket.
3. **Given** Firefox is the active application and I'm viewing a Bitbucket PR page, **When** the Firefox plugin detects the tab title, **Then** it extracts the PR number and repository, attempts to resolve it to a ticket, and contributes the browsing time accordingly.
4. **Given** a plugin produces activity that cannot be resolved to a ticket, **When** the data reaches the ticket model, **Then** it appears in the "Unassigned" group with the source's contextual metadata (branch name, page title, app name) visible for manual assignment.
5. **Given** I add a manual ticket override (e.g., "branch `feature/cleanup` → ticket PROJ-456"), **When** any plugin produces activity matching that branch, **Then** the time is automatically resolved to PROJ-456.

---

### User Story 3 — Browser Activity Plugins (Priority: P3)

As a user, I want Chrome and Firefox to contribute time tracking data when I'm browsing Jira tickets, Bitbucket PRs, or other work-related pages. The browser plugins should detect the active tab's context and associate that time with the relevant ticket.

**Why this priority**: Browser context was originally planned but skipped. With the plugin system in place, browser plugins become straightforward implementations of the plugin interface, delivering high-value ticket detection from the tools where users spend significant time.

**Independent Test**: Open Jira ticket PROJ-123 in Chrome for 3 minutes, then switch to Bitbucket PR #42 in Firefox for 2 minutes. Verify the dashboard shows PROJ-123 with 3 minutes (source: Chrome) and the PR entry with 2 minutes (source: Firefox), with the PR resolved to a ticket if a matching override or pattern exists.

**Acceptance Scenarios**:

1. **Given** Chrome is active with a Jira page titled "PROJ-123: Fix login bug - Jira", **When** the Chrome plugin reads the tab, **Then** it extracts ticket ID `PROJ-123` and contributes the time to that ticket.
2. **Given** Firefox is active with a Bitbucket PR page, **When** the Firefox plugin reads the window title, **Then** it extracts the PR number and repository slug from the title.
3. **Given** I switch browser tabs rapidly (under 30 seconds each), **When** the minimum duration threshold applies, **Then** rapid switches are ignored and only sustained tab focus is recorded.
4. **Given** Chrome or Firefox is not installed, **When** the plugin system initializes, **Then** the corresponding plugin shows as "unavailable" — no error, no crash.
5. **Given** accessibility permission is not granted, **When** a browser plugin tries to read tab titles, **Then** it reports "permission required" status and does not block other plugins.

---

### User Story 4 — Plugin Settings & Ticket Management (Priority: P4)

As a user, I want to manage plugins and ticket resolution rules from settings. I should be able to enable/disable sources, configure credentials, define manual ticket overrides, and set patterns for ticket extraction.

**Why this priority**: Management and customization. The system should work with sensible defaults, but users need control for edge cases — overriding wrong ticket inference, excluding noisy projects, configuring API keys.

**Independent Test**: Open Settings, disable the WakaTime plugin, verify its data disappears from the ticket dashboard. Re-enable it, verify data returns. Add a manual override mapping a branch to a ticket, verify future activity on that branch resolves correctly.

**Acceptance Scenarios**:

1. **Given** I open the Settings panel, **When** I navigate to the Plugins section, **Then** I see all available plugins with their name, status (active/inactive/error/unavailable), and a toggle to enable or disable each.
2. **Given** I disable a plugin, **When** I return to the dashboard, **Then** new data from that plugin is no longer fetched, but previously-recorded ticket time from that source remains in history.
3. **Given** a plugin requires credentials, **When** I view that plugin's settings, **Then** I can enter or update the credential and it is stored securely.
4. **Given** I create a ticket override rule (e.g., "any activity with branch `main` on project `core-lib` → ticket INFRA-001"), **When** plugins produce matching activity, **Then** it resolves to the specified ticket.
5. **Given** I mark certain projects as excluded, **When** plugins report activity from those projects, **Then** the activity is hidden from the dashboard.

---

### Edge Cases

- What happens when two plugins report overlapping time for the same ticket? Deduplicate by wall-clock time — if WakaTime says 10:00-10:30 on PROJ-123 and Chrome says 10:15-10:45 on PROJ-123, the ticket total is 45 minutes (10:00-10:45), not 60 minutes.
- What happens when the same time period is attributed to different tickets by different plugins? Both ticket attributions are preserved — the user resolves the conflict manually via the Entries view.
- What happens when a plugin is removed? Previously-recorded entries retain their source label and ticket association. The plugin appears as "unavailable" rather than deleted.
- What happens when all plugins are disabled? The dashboard shows no new time data. Previously-recorded entries remain visible. The user must enable at least one plugin to track time.
- How does the system handle a plugin returning bad data? The plugin's data is skipped for that sync cycle, an error status is shown, other plugins continue normally.
- What if a browser tab title doesn't match any known ticket pattern? The time goes to Unassigned with the page title as context, available for manual ticket assignment.

## Requirements *(mandatory)*

### Functional Requirements

**Ticket Model**:
- **FR-001**: System MUST treat tickets as the central organizing entity — all tracked time is either resolved to a ticket or grouped as "Unassigned."
- **FR-002**: Each ticket MUST aggregate time from multiple sources, showing a total duration and a per-source breakdown.
- **FR-003**: System MUST deduplicate overlapping time periods within the same ticket, calculating wall-clock time rather than summing source durations.
- **FR-004**: System MUST allow users to manually assign unresolved time to tickets.
- **FR-005**: System MUST support ticket override rules that map source-specific identifiers (branch names, URLs, app names) to ticket IDs.

**Plugin System**:
- **FR-006**: System MUST define a plugin interface that external sources implement to contribute activity data with optional ticket resolution.
- **FR-007**: System MUST support discovering and initializing plugins at app startup.
- **FR-008**: Each plugin MUST be independently enable-able and disable-able without affecting other plugins or the core tracking system.
- **FR-009**: A plugin failure MUST NOT prevent other plugins or the core tracking system from functioning.
- **FR-010**: System MUST preserve the source identity on each time segment so users can see which plugin contributed each piece of data.

**Source Plugins**:
- **FR-011**: System MUST migrate the existing WakaTime integration to the plugin interface with zero loss of existing functionality (branch fetching, ticket inference, manual overrides, excluded projects).
- **FR-011a**: System MUST migrate the existing app tracking functionality (WindowMonitorService, IdleDetectionService, TrackingCoordinator) to the plugin interface with zero loss of existing functionality (window monitoring, idle detection, pause/resume).
- **FR-012**: Browser plugins (Chrome, Firefox) MUST extract the active tab's title and URL to identify Jira tickets and Bitbucket PRs.
- **FR-013**: All plugins MUST respect the same minimum duration threshold.
- **FR-014**: Browser plugins MUST detect whether the browser is installed and report "unavailable" status if not.

**Settings & Management**:
- **FR-015**: System MUST provide a settings interface for managing all plugins — view status, toggle enabled state, configure credentials.
- **FR-016**: Plugin credentials MUST be stored securely.
- **FR-017**: System MUST display per-plugin status (active, inactive, error, permission required, unavailable).
- **FR-018**: Previously-recorded time entries MUST remain accessible even if the plugin that created them is later disabled.

**App Tracking Plugin**:
- **FR-019**: The existing app tracking functionality (window monitoring, idle detection) MUST be migrated to the plugin interface, on equal footing with all other plugins.
- **FR-020**: Ticket inference MUST operate on the combined data from all active plugins uniformly — no source has special priority.

### Key Entities

- **Ticket (computed)**: A virtual aggregation, not a persisted database record. Computed at query time by grouping TimeEntry records by their ticket ID field. Has: ticket ID, total duration (deduplicated from grouped entries), source breakdown, resolution status (auto-resolved / manually assigned / unassigned). A special "Unassigned" pseudo-ticket collects entries with no resolved ticket ID. No separate Ticket table exists — the ticket ID on each TimeEntry is the single source of truth.
- **Time Segment (extended TimeEntry)**: The existing `TimeEntry` model is extended with plugin-specific fields: source plugin identifier, ticket ID (if resolved), and contextual metadata (branch, project, page title, URL). This preserves all existing functionality (review, export, booking, learned patterns) while enabling multi-source contribution. Multiple entries from different sources can be associated with the same ticket.
- **Plugin**: An external time tracking source. Has: unique identifier, display name, status, configuration, sync interval. Produces Time Segments and optionally resolves them to Ticket IDs.
- **Ticket Override Rule**: A user-defined mapping from source identifiers to ticket IDs. Has: match criteria (branch pattern, URL pattern, project name), target ticket ID, priority. Applied during ticket resolution before default inference.
- **Plugin Configuration**: Per-plugin settings including credentials, enabled state, sync interval, and source-specific preferences. Credentials stored securely.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The dashboard's primary view is organized by tickets — users see "Tickets" as the default tab showing time per ticket, not time per source.
- **SC-002**: Adding a new time tracking source requires implementing only the plugin interface — zero modifications to the ticket model, dashboard views, or settings UI.
- **SC-003**: All existing WakaTime functionality (branch fetching, ticket inference, manual overrides, excluded projects, timeline charts) works identically after migration to the plugin system.
- **SC-004**: Users can see combined ticket time from 2+ sources in a single view within 5 seconds of opening the dashboard.
- **SC-005**: Overlapping time from multiple sources on the same ticket is correctly deduplicated — wall-clock time is shown, not summed source time.
- **SC-006**: Disabling a plugin removes its future data contributions within 1 second, with no residual artifacts.
- **SC-007**: A plugin failure does not affect the dashboard's ability to display ticket data from other healthy sources.
- **SC-008**: Browser plugins extract Jira ticket IDs and Bitbucket PR numbers from tab titles with at least 95% accuracy for standard title formats.
- **SC-009**: Unresolved time is clearly visible and manually assignable to tickets in under 3 clicks.
- **SC-010**: End-to-end time from plugin data fetch to ticket dashboard display is under 3 seconds for up to 500 activity records per source.

## Clarifications

### Session 2026-02-15

- Q: Should the new "Time Segment" concept extend the existing `TimeEntry` model or be a separate new model? → A: Extend existing `TimeEntry` — add source plugin ID, ticket ID, and metadata fields to the current model. This preserves all existing functionality (review, export, booking, learned patterns).
- Q: Should tickets be persisted as their own database model or computed on-the-fly by grouping TimeEntry records? → A: Computed aggregation — group TimeEntries by ticket ID at query time, no separate Ticket table. The ticket ID on each TimeEntry is the single source of truth.
- Q: When a plugin-resolved entry and an app-tracking entry overlap, should resolved entries take priority? → A: Built-in app tracking must also be a plugin — no special core status. All sources are plugins; deduplication rules apply uniformly across all plugins.

## Assumptions

- Browser tab title reading requires macOS Accessibility permission, already requested for app tracking. No additional permission prompt needed.
- Chrome tab titles and URLs can be read via AppleScript. Firefox tab titles are parsed from the window title.
- App tracking (WindowMonitorService, IdleDetectionService, TrackingCoordinator) is migrated to a plugin. All sources are plugins with no special core status.
- WakaTime API key continues to be read from `~/.wakatime.cfg`. The plugin wraps existing behavior.
- The existing `TimeEntry` model is extended (not replaced) with plugin fields. All existing review, export, booking, and learned pattern functionality continues to work unchanged.
- The plugin system is in-process (compiled-in protocol conformance), not runtime dynamic loading.
- Ticket IDs follow the Jira pattern `[A-Z][A-Z0-9]+-\d+`. Other patterns can be added via override rules.

## Scope Boundaries

**In scope**:
- Ticket-centric data model and dashboard redesign
- Plugin abstraction layer
- App tracking migration to plugin interface
- WakaTime migration to plugin interface
- Chrome browser activity plugin
- Firefox browser activity plugin
- Unified ticket aggregation with deduplication
- Manual ticket assignment for unresolved time
- Ticket override rules
- Plugin settings management

**Out of scope**:
- Third-party plugin marketplace or runtime extension loading
- Jira/Bitbucket API enrichment (fetching ticket details from servers)
- Plugins for non-browser, non-coding tools (e.g., Slack, email)
- Cross-device synchronization
- Automatic ticket creation in external systems
