# Quickstart: Ticket-Centric Plugin System

**Branch**: `006-time-tracking-plugins` | **Date**: 2026-02-15

## Prerequisites

- macOS 14+
- Xcode 16+ (Swift 6.0)
- Accessibility permission granted (System Preferences → Privacy & Security → Accessibility)
- Optional: WakaTime CLI configured (`~/.wakatime.cfg` with API key)
- Optional: Google Chrome and/or Firefox installed

## Build & Run

```bash
# Clone and switch to feature branch
git checkout 006-time-tracking-plugins

# Build
swift build

# Run
swift run
```

## Architecture at a Glance

```
All Time Sources → Plugin Protocol → TimeEntry (SwiftData) → Ticket Aggregation → Dashboard
```

1. **Every source is a plugin** — AppTracking, WakaTime, Chrome, Firefox all implement `TimeTrackingPlugin`
2. **TimeEntry is the universal record** — extended with `sourcePluginID`, `ticketID`, `contextMetadata`
3. **Tickets are computed** — `TicketAggregationService` groups entries by `ticketID` at query time
4. **Deduplication is automatic** — overlapping intervals from multiple sources are merged to wall-clock time

## Key Files

| Purpose | File |
|---------|------|
| Plugin protocol | `Sources/Plugins/TimeTrackingPlugin.swift` |
| Plugin manager | `Sources/Plugins/TimeTrackingPlugin.swift` (PluginManager class) |
| App tracking plugin | `Sources/Plugins/AppTrackingPlugin.swift` |
| WakaTime plugin | `Sources/Plugins/WakaTimePlugin.swift` |
| Chrome plugin | `Sources/Plugins/ChromePlugin.swift` |
| Firefox plugin | `Sources/Plugins/FirefoxPlugin.swift` |
| Ticket aggregation | `Sources/Services/TicketAggregationService.swift` |
| TimeEntry model | `Sources/Models/TimeEntry.swift` |
| Dashboard | `Sources/Views/TimeTracking/TimeTrackingDashboard.swift` |
| Plugin settings | `Sources/Views/Settings/PluginSettingsView.swift` |

## Adding a New Plugin

1. Create a new file in `Sources/Plugins/` (e.g., `SlackPlugin.swift`)
2. Implement `TimeTrackingPlugin` protocol:
   ```swift
   @MainActor
   final class SlackPlugin: TimeTrackingPlugin {
       let id = "slack"
       let displayName = "Slack"
       var status: PluginStatus = .inactive

       func isAvailable() -> Bool { /* check if Slack is installed */ }
       func start() async throws { /* begin monitoring */ }
       func stop() async throws { /* stop monitoring */ }
   }
   ```
3. Register in `TaskManagementApp.swift`:
   ```swift
   pluginManager.register(SlackPlugin(container: container))
   ```
4. Add `slack` case to `EntrySource` enum in `Enums.swift`
5. Build and run — the plugin appears in Settings automatically

**Zero changes needed** to: TimeEntry model, TicketAggregationService, dashboard views, or other plugins.

## Verification Checklist

- [ ] `swift build` succeeds with zero warnings
- [ ] App launches and shows ticket-centric dashboard
- [ ] App Tracking plugin creates entries with `sourcePluginID = "app-tracking"`
- [ ] WakaTime plugin (if configured) creates entries with `sourcePluginID = "wakatime"`
- [ ] Chrome plugin (if installed) reads tab title when Chrome is active
- [ ] Firefox plugin (if installed) reads window title when Firefox is active
- [ ] Ticket view groups entries by ticket ID with deduplicated totals
- [ ] Unassigned entries visible and manually assignable
- [ ] Disabling a plugin stops new data collection
- [ ] Previously-recorded entries remain after plugin disable
