# Implementation Plan: Native macOS Todo App

**Branch**: `004-macos-todo-app` | **Date**: 2026-02-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-macos-todo-app/spec.md`

## Summary

Build a native macOS todo application using Swift/SwiftUI with SwiftData
persistence. The app provides a main window for todo management (with
projects, tags, search, filtering) and a menu bar component showing the
active timer. Integrations with Jira and Bitbucket allow linking todos to
tickets and PRs with periodic background sync. Time tracking lets users
start/stop timers per todo and review daily summaries. An optional
automatic detection feature (P5) monitors active browser windows to
suggest time attribution.

## Technical Context

**Language/Version**: Swift 6.x (latest stable)
**Primary Dependencies**: SwiftUI, SwiftData, Foundation, Security (Keychain), AppKit (NSWorkspace), Accessibility APIs
**Storage**: SwiftData (macOS 14+)
**Testing**: XCTest, swift test
**Target Platform**: macOS 14 Sonoma+
**Project Type**: Single native macOS app
**Performance Goals**: <2s launch, <200ms search over 500+ todos, 1s timer updates
**Constraints**: Offline-capable, local-first, no cloud dependencies, single-user
**Scale/Scope**: Single user, hundreds of todos, ~5 views + menu bar

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Todo-First Design | PASS | Todos are central entity; all integrations link to todos; app works standalone |
| II. Local-First Data | PASS | SwiftData local storage; full offline capability; no cloud |
| III. Adapter Pattern | PASS | JiraService/BitbucketService are independent adapters with shared protocol patterns; adding new source requires no changes to existing code |
| IV. Simplicity & YAGNI | PASS | No abstractions beyond what's needed; flat todos (no subtasks); single server per integration |
| V. Spec-Driven | PASS | Full spec and clarifications completed before planning |

**Post-Phase 1 re-check**: All principles still satisfied. Data model
keeps Todo as central entity. Services are independent. No unnecessary
abstractions introduced.

## Project Structure

### Documentation (this feature)

```text
specs/004-macos-todo-app/
├── plan.md              # This file
├── research.md          # Phase 0: technology research
├── data-model.md        # Phase 1: entity definitions
├── quickstart.md        # Phase 1: setup and structure guide
├── contracts/
│   └── services.md      # Phase 1: service layer contracts
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
TaskManagement/
├── TaskManagementApp.swift
├── Models/
│   ├── Todo.swift
│   ├── Project.swift
│   ├── Tag.swift
│   ├── JiraLink.swift
│   ├── BitbucketLink.swift
│   ├── TimeEntry.swift
│   ├── IntegrationConfig.swift
│   └── Enums.swift
├── Services/
│   ├── TodoService.swift
│   ├── ProjectService.swift
│   ├── TagService.swift
│   ├── TimerService.swift
│   ├── TimeEntryService.swift
│   ├── JiraService.swift
│   ├── BitbucketService.swift
│   ├── SyncService.swift
│   ├── KeychainService.swift
│   └── WindowDetectionService.swift
├── Views/
│   ├── Sidebar/
│   ├── TodoList/
│   ├── TodoDetail/
│   ├── TimeTracking/
│   ├── Settings/
│   ├── MenuBar/
│   └── ContentView.swift
├── Networking/
│   ├── HTTPClient.swift
│   ├── JiraAPI.swift
│   └── BitbucketAPI.swift
└── Tests/
    └── TaskManagementTests/
```

**Structure Decision**: Single Xcode project, no SPM packages. All code
in one target with logical directory grouping. Tests in a separate test
target. This is the simplest structure for a single-developer macOS app.

## Complexity Tracking

> No constitution violations. No entries needed.
