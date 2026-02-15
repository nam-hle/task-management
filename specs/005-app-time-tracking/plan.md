# Implementation Plan: Application & Browser Time Tracking

**Branch**: `005-app-time-tracking` | **Date**: 2026-02-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-app-time-tracking/spec.md`

## Summary

Extend the existing macOS todo app (004) with automatic time tracking that monitors active application windows and browser tabs (Firefox, Chrome) to detect work on Jira tickets and Bitbucket PRs. Time entries auto-link to matching todos, are enriched via Jira/Bitbucket APIs and WakaTime data, and go through a learned review workflow before export for Timension booking. This feature implements Pillar 1 (Primary) of the constitution: Ticket-Based Time Booking.

## Technical Context

**Language/Version**: Swift 6.0 (latest stable)
**Primary Dependencies**: SwiftUI, SwiftData, ApplicationServices (AXUIElement), IOKit (idle detection), AppKit (NSWorkspace, NSAppleScript), Foundation, Security (Keychain)
**Storage**: SwiftData (SQLite-backed, macOS 14+) — extending existing 004 schema
**Testing**: XCTest + Swift Testing framework
**Target Platform**: macOS 14+ (Sonoma) — required for SwiftData
**Project Type**: Single native macOS app (extending existing SPM package)
**Performance Goals**: <2s dashboard load, <1min tracking accuracy per hour, background tracking with no perceptible UI impact
**Constraints**: No App Sandbox (Accessibility API requirement), offline-capable, single-user, <=60s data loss on crash
**Scale/Scope**: Single developer user, ~50-100 time entries/day, 90-day retention

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Ticket-Based Time Booking | PASS | This feature IS the primary purpose — automatic time tracking with ticket-based attribution and Timension export |
| II. Local-First Data | PASS | All time entries stored locally in SwiftData. WakaTime cloud API and Jira/Bitbucket APIs are optional enrichments; core tracking works fully offline |
| III. Adapter Pattern for External Sources | PASS | WakaTime, Jira API, Bitbucket API each implemented as independent adapter services with own auth and error handling. Browser context detection follows configurable rule patterns |
| IV. Simplicity & YAGNI | PASS | Reuses existing 004 data layer, models, and UI patterns. New services follow established patterns (struct with ModelContext). No premature abstractions |
| V. Spec-Driven Development | PASS | This plan follows from the completed spec and clarification sessions |

**Gate result**: ALL PASS — proceeding to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/005-app-time-tracking/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (Swift protocol interfaces)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
TaskManagement/Sources/
├── TaskManagementApp.swift          # Extend: add permission check on launch
├── Models/
│   ├── Todo.swift                   # Existing (no changes needed)
│   ├── TimeEntry.swift              # Extend: add applicationName, browserContext, wakatimeContext fields
│   ├── JiraLink.swift               # Existing (no changes needed)
│   ├── BitbucketLink.swift          # Existing (no changes needed)
│   ├── IntegrationConfig.swift      # Existing (no changes needed)
│   ├── TrackedApplication.swift     # NEW: allowlist app config
│   ├── BrowserContextRule.swift     # NEW: URL/title extraction patterns
│   ├── LearnedPattern.swift         # NEW: validated context→todo associations
│   ├── ExportRecord.swift           # NEW: export batch tracking
│   └── Enums.swift                  # Extend: add new enum cases
├── Services/
│   ├── TodoService.swift            # Existing (no changes needed)
│   ├── ProjectService.swift         # Existing (no changes needed)
│   ├── TagService.swift             # Existing (no changes needed)
│   ├── TimeEntryService.swift       # NEW: CRUD, merge, split, review, auto-save
│   ├── WindowMonitorService.swift   # NEW: AXUIElement active window tracking
│   ├── BrowserContextService.swift  # NEW: Chrome AppleScript + Firefox title parsing
│   ├── IdleDetectionService.swift   # NEW: IOKit idle + sleep/wake/lock
│   ├── WakaTimeService.swift        # NEW: WakaTime cloud API integration
│   ├── LearnedPatternService.swift  # NEW: pattern learning and auto-approval
│   ├── ExportService.swift          # NEW: formatted export generation
│   ├── JiraAPIService.swift         # NEW: Jira REST API for ticket enrichment
│   ├── BitbucketAPIService.swift    # NEW: Bitbucket REST API for PR enrichment
│   ├── KeychainService.swift        # NEW: macOS Keychain wrapper
│   └── TrackingCoordinator.swift    # NEW: orchestrates all tracking services
├── Views/
│   ├── ContentView.swift            # Extend: add time tracking tab/section
│   ├── MenuBar/
│   │   └── MenuBarView.swift        # Extend: wire start/stop, show active context
│   ├── TimeTracking/                # NEW: all time tracking UI
│   │   ├── TimeTrackingDashboard.swift    # Daily overview with live tracking
│   │   ├── TimeEntryListView.swift        # Review view with merge/split/edit
│   │   ├── TimeEntryRow.swift             # Individual entry display
│   │   ├── TimeEntryDetailView.swift      # Edit entry details
│   │   ├── ExportView.swift               # Export preview and booking
│   │   └── ManualTimerView.swift          # Manual timer start/stop UI
│   ├── Settings/                    # NEW: configuration UI
│   │   ├── SettingsView.swift             # Main settings container
│   │   ├── TrackedAppsSettingsView.swift  # App allowlist management
│   │   ├── IntegrationSettingsView.swift  # Jira/Bitbucket/WakaTime credentials
│   │   ├── TrackingSettingsView.swift     # Idle timeout, min switch, auto-save
│   │   └── LearnedPatternsView.swift      # Review/revoke learned patterns
│   └── Permissions/                 # NEW: first-run permission flow
│       └── AccessibilityPermissionView.swift
└── Networking/                      # NEW: HTTP client and API adapters
    ├── HTTPClient.swift                   # Shared URLSession wrapper
    ├── JiraAPI.swift                      # Jira REST endpoints
    ├── BitbucketAPI.swift                 # Bitbucket REST endpoints
    └── WakaTimeAPI.swift                  # WakaTime API endpoints

TaskManagement/Tests/TaskManagementTests/
├── Services/
│   ├── TimeEntryServiceTests.swift
│   ├── BrowserContextServiceTests.swift
│   ├── LearnedPatternServiceTests.swift
│   └── ExportServiceTests.swift
└── Models/
    └── TimeEntryTests.swift
```

**Structure Decision**: Extends the existing 004 SPM package structure. New files follow the established Models/Services/Views pattern. Networking/ directory (currently empty) is populated with API adapters. No new SPM targets — everything lives in the single app target.

## MVP Scope

The MVP delivers **User Story 1 (P1): Active Application Time Tracking** only.

**MVP includes**:
- Extend TimeEntry model (applicationName, applicationBundleID)
- TrackedApplication model (app allowlist)
- AccessibilityPermissionView (guided first-run prompt)
- WindowMonitorService (NSWorkspace + AXUIElement)
- IdleDetectionService (IOKit + sleep/wake/lock)
- TrackingCoordinator (minimal orchestration)
- TimeEntryService (basic CRUD, auto-save, midnight split)
- Manual timer (start/stop with label)
- TimeTrackingDashboard (daily app usage breakdown)
- Settings (tracked apps, idle threshold, min switch duration)
- MenuBarView wiring (start/stop, active app display)

**MVP excludes** (deferred to post-MVP phases):
- Browser tab context detection (Chrome AppleScript, Firefox title parsing)
- BrowserContextRule model and Jira/Bitbucket pattern extraction
- Jira/Bitbucket API enrichment and auto-linking to todos
- WakaTime integration
- Time entry review/edit (merge, split, bulk operations)
- Learned patterns and auto-approval
- Export and booking workflow
- Networking layer (JiraAPI, BitbucketAPI, WakaTimeAPI)

## Complexity Tracking

> No constitution violations. Table intentionally left empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
