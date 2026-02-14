# Quickstart: Native macOS Todo App

**Feature**: `004-macos-todo-app`
**Date**: 2026-02-14

## Prerequisites

- macOS 14 Sonoma or later
- Xcode 16+ (latest stable)
- Swift 6.x

## Project Setup

1. Create a new Xcode project:
   - Template: macOS > App
   - Interface: SwiftUI
   - Storage: SwiftData
   - Bundle ID: `com.taskmanagement.app`

2. Configure deployment target:
   - Minimum macOS: 14.0

3. Add entitlements:
   - `com.apple.security.automation.apple-events` (for browser tab access)
   - App Sandbox: disabled (required for Accessibility API access)

4. Add Info.plist keys:
   - `NSAccessibilityUsageDescription`: "TaskManagement needs
     Accessibility access to detect which application you are using for
     automatic time tracking."
   - `NSAppleEventsUsageDescription`: "TaskManagement needs Apple Events
     access to read browser tab titles for automatic time tracking."

## Build & Run

```bash
# Open in Xcode
open TaskManagement.xcodeproj

# Or build from command line
swift build

# Run tests
swift test
```

## Project Structure

```text
TaskManagement/
├── TaskManagementApp.swift       # @main App with WindowGroup + MenuBarExtra
├── Models/
│   ├── Todo.swift                # @Model Todo entity
│   ├── Project.swift             # @Model Project entity
│   ├── Tag.swift                 # @Model Tag entity
│   ├── JiraLink.swift            # @Model JiraLink entity
│   ├── BitbucketLink.swift       # @Model BitbucketLink entity
│   ├── TimeEntry.swift           # @Model TimeEntry entity
│   ├── IntegrationConfig.swift   # @Model IntegrationConfig entity
│   └── Enums.swift               # Priority, BookingStatus, EntrySource
├── Services/
│   ├── TodoService.swift         # Todo CRUD + soft delete
│   ├── ProjectService.swift      # Project management
│   ├── TagService.swift          # Tag management
│   ├── TimerService.swift        # Timer start/stop/pause + auto-save
│   ├── TimeEntryService.swift    # Time entry CRUD + daily summary
│   ├── JiraService.swift         # Jira API integration
│   ├── BitbucketService.swift    # Bitbucket API integration
│   ├── SyncService.swift         # Periodic background sync
│   ├── KeychainService.swift     # macOS Keychain wrapper
│   └── WindowDetectionService.swift  # P5: active window monitoring
├── Views/
│   ├── Sidebar/
│   │   ├── SidebarView.swift     # Project list + filters
│   │   └── ProjectRow.swift
│   ├── TodoList/
│   │   ├── TodoListView.swift    # Main todo list
│   │   ├── TodoRow.swift         # Single todo row
│   │   └── SearchBar.swift
│   ├── TodoDetail/
│   │   ├── TodoDetailView.swift  # Todo detail + editing
│   │   ├── JiraLinkView.swift    # Jira ticket info display
│   │   ├── BitbucketLinkView.swift
│   │   └── TimeEntriesView.swift
│   ├── TimeTracking/
│   │   ├── DailyTimeView.swift   # Daily time review
│   │   └── TimeEntryRow.swift
│   ├── Settings/
│   │   ├── SettingsView.swift    # App settings
│   │   ├── JiraConfigView.swift
│   │   └── BitbucketConfigView.swift
│   ├── MenuBar/
│   │   ├── MenuBarView.swift     # Menu bar popover content
│   │   └── TimerDisplay.swift
│   └── ContentView.swift         # Main NavigationSplitView
├── Networking/
│   ├── HTTPClient.swift          # URLSession wrapper with retry
│   ├── JiraAPI.swift             # Jira endpoint definitions
│   └── BitbucketAPI.swift        # Bitbucket endpoint definitions
└── Tests/
    └── TaskManagementTests/
        ├── TodoServiceTests.swift
        ├── TimerServiceTests.swift
        ├── JiraServiceTests.swift
        └── BitbucketServiceTests.swift
```

## Verification

After building and launching the app:

1. **Todo management**: Create a todo, verify it persists after restart
2. **Menu bar**: Timer icon appears in menu bar, click to see popover
3. **Projects/Tags**: Create a project, assign todo, filter by project
4. **Keyboard shortcuts**: Cmd+N creates todo, Enter completes

## Key Technical Notes

- SwiftData requires explicit `context.save()` for timer auto-save
- Many-to-many Tag relationship needs `@Relationship(inverse:)` on
  both sides
- Soft delete via `deletedAt` field — filter in all queries
- MenuBarExtra uses `.window` style for full SwiftUI popover
- `@Observable` TimerManager shared between WindowGroup and MenuBarExtra
