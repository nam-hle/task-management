# Implementation Plan: Ticket-Centric Plugin System

**Branch**: `006-time-tracking-plugins` | **Date**: 2026-02-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/006-time-tracking-plugins/spec.md`

## Summary

Rewrite the time tracking architecture so that all sources — app tracking, WakaTime, Chrome, Firefox — are plugins implementing a common protocol. Tickets become the central organizing concept: computed aggregations from TimeEntry records grouped by ticket ID. The existing `TimeEntry` model is extended with plugin and ticket fields. The dashboard is redesigned to be ticket-first with per-source breakdown and wall-clock deduplication.

## Technical Context

**Language/Version**: Swift 6.0 (latest stable)
**Primary Dependencies**: SwiftUI, SwiftData, ApplicationServices (AXUIElement), IOKit, AppKit (NSWorkspace, NSAppleScript), Foundation, Security (Keychain)
**Storage**: SwiftData (SQLite-backed, macOS 14+) — extending existing schema
**Testing**: XCTest + swift build verification
**Target Platform**: macOS 14+ (native app)
**Project Type**: Single macOS application
**Performance Goals**: Dashboard renders ticket view within 5 seconds (SC-004); end-to-end plugin data to display under 3 seconds for 500 records (SC-010)
**Constraints**: Local-first (no cloud), in-process plugins (compiled-in protocol conformance), offline-capable
**Scale/Scope**: Single user, ~4 plugins, ~500 entries/day/source, ~50 tickets/day

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Ticket-Based Time Booking | PASS | Feature is entirely about ticket-centric time attribution — aligns perfectly with primary purpose |
| II. Local-First Data | PASS | All data stored locally via SwiftData. Plugins are in-process. No cloud, no telemetry |
| III. Adapter Pattern for External Sources | PASS | Plugin system IS the adapter pattern — each plugin independently configurable, no core changes needed for new sources |
| IV. Simplicity & YAGNI | PASS | Extending existing TimeEntry model (not creating parallel models), tickets computed not persisted, no new dependencies |
| V. Spec-Driven Development | PASS | Full spec written and clarified before planning |
| Technology: Swift + SwiftUI + SwiftData | PASS | Using existing stack, no new framework dependencies |
| Technology: macOS Keychain | PASS | Already in use for credential storage |
| Technology: No unjustified dependencies | PASS | Only Apple frameworks used |

**Pre-Phase 0 gate**: PASSED — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/006-time-tracking-plugins/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── plugin-protocol.md
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
Sources/
├── Models/
│   ├── TimeEntry.swift          # MODIFY — add sourcePluginID, ticketID, contextMetadata
│   ├── Enums.swift              # MODIFY — add PluginStatus, update EntrySource
│   └── TicketOverride.swift     # MODIFY — add URL pattern, priority field
├── Plugins/                     # NEW directory
│   ├── TimeTrackingPlugin.swift # NEW — protocol definition + PluginManager
│   ├── AppTrackingPlugin.swift  # NEW — wraps WindowMonitor + IdleDetection
│   ├── WakaTimePlugin.swift     # NEW — wraps WakaTimeService
│   ├── ChromePlugin.swift       # NEW — AppleScript tab reading
│   └── FirefoxPlugin.swift      # NEW — window title parsing
├── Services/
│   ├── TicketAggregationService.swift  # NEW — groups entries by ticket, deduplicates
│   ├── TimeEntryService.swift          # MODIFY — plugin-aware entry creation
│   ├── TrackingCoordinator.swift       # MODIFY — becomes thin orchestrator over PluginManager
│   ├── WindowMonitorService.swift      # KEEP — used internally by AppTrackingPlugin
│   ├── IdleDetectionService.swift      # KEEP — used internally by AppTrackingPlugin
│   ├── WakaTimeService.swift           # KEEP — used internally by WakaTimePlugin
│   ├── TicketInferenceService.swift    # MODIFY — unified ticket resolution across all plugins
│   └── BrowserTabService.swift         # NEW — shared AppleScript/window title reading
├── Views/
│   ├── TimeTracking/
│   │   ├── TimeTrackingDashboard.swift    # MODIFY — ticket-first tab redesign
│   │   ├── TicketsView.swift              # MODIFY — ticket aggregation with multi-source breakdown
│   │   ├── TicketDetailView.swift         # NEW — expanded ticket with source segments
│   │   └── UnassignedTimeView.swift       # NEW — manual ticket assignment UI
│   └── Settings/
│       ├── SettingsView.swift             # MODIFY — add Plugins tab
│       └── PluginSettingsView.swift       # NEW — plugin management UI
└── TaskManagementApp.swift                # MODIFY — register PluginManager, init plugins
```

**Structure Decision**: Existing single-project structure maintained. New `Sources/Plugins/` directory for plugin protocol and implementations. Services remain in `Sources/Services/`. This follows the existing convention of top-level feature directories under `Sources/`.

## Complexity Tracking

> No constitution violations — table not needed.

## Architecture Overview

### Plugin System

```
┌──────────────────────────────────────────────────────────┐
│                     PluginManager                         │
│  Discovers, initializes, manages plugin lifecycle         │
│  Stores enabled state in UserDefaults                     │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────┐ ┌─────────────┐ ┌────────┐ ┌─────────┐ │
│  │ AppTracking │ │  WakaTime   │ │ Chrome │ │ Firefox │ │
│  │   Plugin    │ │   Plugin    │ │ Plugin │ │ Plugin  │ │
│  └──────┬──────┘ └──────┬──────┘ └───┬────┘ └────┬────┘ │
│         │               │            │            │       │
└─────────┼───────────────┼────────────┼────────────┼───────┘
          │               │            │            │
          ▼               ▼            ▼            ▼
    ┌──────────────────────────────────────────────────┐
    │              TimeEntryService                     │
    │  Creates TimeEntry records with pluginID +        │
    │  ticketID + contextMetadata                       │
    └──────────────────────┬───────────────────────────┘
                           │
                           ▼
    ┌──────────────────────────────────────────────────┐
    │          TicketAggregationService                  │
    │  Groups TimeEntries by ticketID                    │
    │  Deduplicates overlapping wall-clock intervals     │
    │  Computes per-source breakdown                     │
    └──────────────────────┬───────────────────────────┘
                           │
                           ▼
    ┌──────────────────────────────────────────────────┐
    │              Dashboard (Tickets View)              │
    │  Ticket list → expand → source breakdown          │
    │  Unassigned group → manual ticket assignment       │
    └──────────────────────────────────────────────────┘
```

### Plugin Types

| Plugin | Data Source | Ticket Resolution | Real-Time? |
|--------|-----------|-------------------|------------|
| AppTrackingPlugin | WindowMonitor + IdleDetection | Via learned patterns / manual assignment | Yes — continuous |
| WakaTimePlugin | WakaTime API (durations + heartbeats) | Branch name → ticket ID regex | No — periodic fetch |
| ChromePlugin | AppleScript (`tell application "Google Chrome"`) | Tab title/URL → Jira ticket regex | Yes — on app switch |
| FirefoxPlugin | Window title parsing (AXUIElement) | Window title → ticket/PR regex | Yes — on app switch |

### Deduplication Algorithm

For each ticket's entries on a given day:
1. Collect all `(startTime, endTime)` intervals
2. Sort by `startTime` ascending
3. Merge overlapping/adjacent intervals: if `current.start <= previous.end`, extend `previous.end = max(previous.end, current.end)`
4. Sum merged interval durations = wall-clock time

### Key Design Decisions

1. **Extend TimeEntry, don't create new model** — preserves review, export, booking, learned patterns
2. **Tickets are computed, not persisted** — group TimeEntries by ticketID at query time, always accurate
3. **All sources are plugins** — no special "core" source, uniform deduplication rules
4. **Manual timers remain core** — user-initiated entry creation is not a plugin concern
5. **Plugin state in UserDefaults** — lightweight, no new SwiftData model for plugin config
6. **Existing services kept internal** — WindowMonitorService, IdleDetectionService, WakaTimeService become internal implementation details of their respective plugins

## Implementation Phases

### Phase 1: Plugin Infrastructure (US2 foundation)
- Define `TimeTrackingPlugin` protocol and `PluginStatus` enum
- Create `PluginManager` (registration, lifecycle, enable/disable)
- Extend `TimeEntry` with `sourcePluginID`, `ticketID`, `contextMetadata` fields
- Update `EntrySource` enum with plugin-derived cases
- Create `TicketAggregationService` (grouping + deduplication)
- Update `TicketOverride` with URL pattern matching and priority

### Phase 2: App Tracking Plugin (FR-011a, FR-019)
- Create `AppTrackingPlugin` wrapping WindowMonitor + IdleDetection
- Refactor `TrackingCoordinator` to use PluginManager
- Migrate entry creation to set `sourcePluginID = "app-tracking"`
- Preserve pause/resume, auto-save, midnight split, crash recovery
- Manual timer remains on TrackingCoordinator (not plugin)
- Zero regression on existing behavior

### Phase 3: WakaTime Plugin (FR-011)
- Create `WakaTimePlugin` wrapping WakaTimeService
- Plugin produces TimeEntry records directly (instead of BranchActivity)
- Ticket resolution via TicketInferenceService integrated into plugin
- Preserve branch fetching, manual overrides, excluded projects
- Remove WakaTime-specific state from dashboard views

### Phase 4: Browser Plugins (FR-012–FR-014, US3)
- Create `BrowserTabService` for shared tab reading logic
- Create `ChromePlugin` — AppleScript tab title/URL extraction
- Create `FirefoxPlugin` — window title parsing via AXUIElement
- Ticket extraction: Jira pattern from title, Bitbucket PR from URL/title
- Minimum duration threshold, availability detection
- Permission status reporting

### Phase 5: Ticket-Centric Dashboard (US1)
- Redesign `TicketsView` to use `TicketAggregationService`
- Show tickets sorted by total time descending
- Expandable ticket rows with per-source breakdown
- Create `UnassignedTimeView` for manual ticket assignment
- Deduplication display (wall-clock vs raw source time)
- Plugin error indicators (non-blocking)
- Remove/reorganize legacy source-centric tabs

### Phase 6: Plugin Settings & Management (US4, FR-015–FR-018)
- Create `PluginSettingsView` — list plugins with status, toggle, configure
- Integrate into Settings tab
- Plugin credential management via Keychain
- Override rules management (branch + URL patterns → ticket ID)
- Previously-recorded entries survive plugin disable
