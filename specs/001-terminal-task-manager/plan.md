# Implementation Plan: Terminal Task Manager

**Branch**: `001-terminal-task-manager` | **Date**: 2026-02-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-terminal-task-manager/spec.md`

## Summary

Build a k9s-inspired terminal UI for unified task management across Jira Server/DC, Bitbucket Server, and Email (IMAP). The application presents all items in a single flat list with vim-style keyboard navigation, source filtering, and a read-only AI assistant powered by Claude. Built with Go + Bubble Tea for native performance and single-binary distribution.

## Technical Context

**Language/Version**: Go 1.22+
**Primary Dependencies**: Bubble Tea v1.x (TUI), Lip Gloss v1.x (styling), Bubbles v0.20+ (components), Huh v0.6+ (forms), Glamour (markdown rendering)
**Storage**: SQLite via `modernc.org/sqlite` (pure Go, no CGo) + `sqlx` for typed queries
**Testing**: Go standard `testing` package + `testify` for assertions
**Target Platform**: macOS (primary), Linux (secondary), Windows via WSL (best-effort)
**Project Type**: Single CLI application
**Performance Goals**: <200ms input-to-render with 1,000+ items, <5s startup with cached data
**Constraints**: <100MB memory, offline-capable with cached data, single binary distribution
**Scale/Scope**: Single user, 3 source integrations, ~7 views, ~10,000 cached items max

## Constitution Check

*No constitution file defined. Proceeding with default gates.*

**Pre-Phase 0 Gate**: PASS (no violations)
- Single project structure: YES
- No unnecessary abstractions: YES (v1 uses hardcoded sources, no plugin system)
- Technology choice justified: YES (see research.md)

## Project Structure

### Documentation (this feature)

```text
specs/001-terminal-task-manager/
├── plan.md              # This file
├── research.md          # Phase 0: Technology & API research
├── data-model.md        # Phase 1: Entity schemas & relationships
├── quickstart.md        # Phase 1: Developer setup guide
├── contracts/           # Phase 1: API adapter interfaces
│   ├── jira.go          # Jira Server/DC adapter interface
│   ├── bitbucket.go     # Bitbucket Server adapter interface
│   ├── email.go         # IMAP/SMTP adapter interface
│   └── ai.go            # AI assistant interface
└── tasks.md             # Phase 2: Task breakdown (/speckit.tasks)
```

### Source Code (repository root)

```text
cmd/
└── taskmanager/
    └── main.go              # Entry point, Bubble Tea program setup

internal/
├── app/
│   ├── app.go               # Root Bubble Tea model, top-level routing
│   ├── keys.go              # Global keybinding definitions
│   └── theme.go             # Lip Gloss theme/style definitions
├── ui/
│   ├── layout.go            # Multi-panel layout manager
│   ├── tasklist/
│   │   ├── model.go         # Unified task list view (main dashboard)
│   │   └── item.go          # Task list item renderer
│   ├── detail/
│   │   └── model.go         # Task detail view
│   ├── config/
│   │   └── model.go         # Source configuration view (Huh forms)
│   ├── ai/
│   │   └── model.go         # AI assistant prompt panel
│   ├── help/
│   │   └── model.go         # Help overlay
│   └── command/
│       └── model.go         # Command palette (: mode)
├── source/
│   ├── source.go            # Common source interface & types
│   ├── jira/
│   │   ├── client.go        # Jira REST API client
│   │   ├── adapter.go       # Jira -> unified Task mapping
│   │   └── types.go         # Jira-specific types
│   ├── bitbucket/
│   │   ├── client.go        # Bitbucket REST API client
│   │   ├── adapter.go       # Bitbucket -> unified Task mapping
│   │   └── types.go         # Bitbucket-specific types
│   └── email/
│       ├── client.go        # IMAP/SMTP client wrapper
│       ├── adapter.go       # Email -> unified Task mapping
│       └── types.go         # Email-specific types
├── model/
│   ├── task.go              # Unified Task entity
│   ├── notification.go      # Notification entity
│   └── config.go            # Configuration entity
├── store/
│   ├── store.go             # SQLite store interface
│   ├── sqlite.go            # SQLite implementation
│   └── migrations.go        # Schema migrations
├── sync/
│   └── poller.go            # Background polling orchestrator
├── ai/
│   ├── assistant.go         # AI assistant service (Claude integration)
│   └── context.go           # Conversation context management
├── credential/
│   └── keyring.go           # System keychain wrapper
└── crossref/
    └── crossref.go          # Jira-Bitbucket cross-reference matcher

tests/
├── unit/
│   ├── model/
│   ├── source/
│   └── store/
├── integration/
│   ├── jira_test.go
│   ├── bitbucket_test.go
│   └── email_test.go
└── contract/
    └── source_contract_test.go
```

**Structure Decision**: Single project (Option 1) with Go's standard `cmd/` + `internal/` layout. The `internal/` package prevents external imports, keeping the API surface clean. Source adapters share a common interface (`source.Source`) to enable the v2 plugin architecture with minimal refactoring.

## Technology Decisions

### Language: Go + Bubble Tea

**Decision**: Go 1.22+ with the Charm ecosystem (Bubble Tea, Lip Gloss, Bubbles, Huh, Glamour)

**Rationale**:
- k9s itself is written in Go; the TUI ecosystem is most mature here
- Single binary distribution is essential for developer tools
- Goroutines map perfectly to concurrent source polling
- Charm ecosystem provides cohesive TUI toolkit (styling, components, forms, markdown rendering)
- Bubble Tea's Elm Architecture handles complex multi-source state management cleanly

**Alternatives considered**:
- **TypeScript + Ink**: User's primary language, but Ink struggles with complex k9s-style layouts, requires custom virtualization, and Node.js startup is 4-8x slower. Distribution requires bundling.
- **Rust + Ratatui**: Best performance, but no Jira/Bitbucket/Claude client libraries. 2x development time for the integration layer. Overkill for this use case.

### Key Library Choices

| Component | Library | Rationale |
|-----------|---------|-----------|
| TUI Framework | `charmbracelet/bubbletea` v1.x | Elm Architecture, excellent state management |
| Styling | `charmbracelet/lipgloss` v1.x | CSS-like terminal styling, table support |
| Components | `charmbracelet/bubbles` v0.20+ | List, table, text input, viewport, help |
| Forms | `charmbracelet/huh` v0.6+ | Declarative forms for source configuration |
| Markdown | `charmbracelet/glamour` | Render Jira descriptions, PR bodies, emails |
| Jira Client | `andygrunwald/go-jira` v2 | Battle-tested Jira Server/DC client |
| Bitbucket Client | Custom thin HTTP client | No adequate library for BB Server/DC |
| IMAP | `emersion/go-imap` v2 | De facto Go IMAP library, IDLE support |
| Email Parsing | `emersion/go-message` | MIME/multipart email body parsing |
| Claude AI | `anthropics/anthropic-sdk-go` | Official Go SDK (or `liushuangls/go-anthropic`) |
| Keychain | `99designs/keyring` | Cross-platform, encrypted file fallback |
| SQLite | `modernc.org/sqlite` | Pure Go, no CGo needed for cross-compilation |
| SQL Helper | `jmoiron/sqlx` | Struct scanning, named parameters |
| Config | `spf13/viper` | Config file management (YAML/TOML) |

## Complexity Tracking

> No constitution violations to justify.
