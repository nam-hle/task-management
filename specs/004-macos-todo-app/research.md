# Research: Native macOS Todo App

**Feature**: `004-macos-todo-app`
**Date**: 2026-02-14

## 1. Storage: SwiftData

**Decision**: SwiftData (macOS 14 Sonoma+)

**Rationale**: SwiftData provides clean SwiftUI integration, supports all
required relationship types (1:1, 1:many, many:many), and aligns with
Apple's future direction. The app's data model is straightforward enough
for SwiftData's current maturity level.

**Alternatives considered**:
- Core Data: More mature, better for complex queries, but heavier API
  surface and less SwiftUI-native. Would be the fallback if SwiftData
  limitations are hit.
- SQLite via GRDB/SQLite.swift: Maximum control but loses SwiftUI
  integration benefits and requires more boilerplate.

**Key constraints**:
- Minimum macOS 14 Sonoma required
- Many-to-many (Todo ↔ Tag) requires explicit `@Relationship(inverse:)`
- All relationships must be `var`, not `let`
- No built-in soft delete — implement via `deletedAt: Date?` field
- Array ordering not preserved — use explicit timestamps/sort fields
- Must call `context.save()` explicitly for timer auto-save (don't rely
  on autosave for critical data)
- No GROUP BY/HAVING/DISTINCT — aggregate in Swift code

## 2. UI Framework: SwiftUI with MenuBarExtra

**Decision**: SwiftUI WindowGroup + MenuBarExtra (macOS 13+)

**Rationale**: MenuBarExtra provides native menu bar integration without
AppKit workarounds. The `.window` style supports full SwiftUI views for
timer controls. State sharing between window and menu bar uses
`@Observable` pattern.

**Alternatives considered**:
- AppKit NSStatusItem: More control but requires bridging to SwiftUI.
- Agent app (LSUIElement): Would hide from Dock, but todo managers
  benefit from Dock presence for quick access.

**Key decisions**:
- Normal app (shows in Dock) — not an agent/background-only app
- MenuBarExtra with `.window` style for timer popover
- Dynamic label on MenuBarExtra shows running timer text
- `@Observable` class shared between WindowGroup and MenuBarExtra via
  `.environment()`
- Timer updates every 1 second via `Timer.publish()`

## 3. Jira REST API Integration

**Decision**: Support both Jira Cloud (API v3) and Server/Data Center
(API v2), auto-detected from URL

**Rationale**: Users may be on either platform. The endpoints are
structurally similar — the main differences are API version prefix and
auth method.

**Alternatives considered**:
- Cloud-only: Would exclude Server/DC users.
- Webhook-based sync: More efficient but requires server-side setup
  inappropriate for a local-first app.

**Key details**:
- Cloud: `GET /rest/api/3/issue/{key}` with Basic auth (email + API token)
- Server: `GET /rest/api/2/issue/{key}` with Bearer PAT
- Search: `GET /rest/api/{version}/search?jql={query}&fields=summary,status,assignee`
- Rate limits: ~10 req/s (Cloud), handle 429 with exponential backoff
- Sync interval: 15 minutes via `NSBackgroundActivityScheduler`

## 4. Bitbucket REST API Integration

**Decision**: Support both Bitbucket Cloud (API 2.0) and Server/DC

**Rationale**: Same reasoning as Jira — users may be on either platform.

**Key details**:
- Cloud: `GET /2.0/repositories/{workspace}/{repo}/pullrequests/{id}`
  with Basic auth (username + API token)
- Server: `GET /rest/api/1.0/projects/{project}/repos/{repo}/pull-requests/{id}`
  with Bearer PAT
- Rate limits: 1,000 req/hour (Cloud), handle 429
- App passwords deprecated June 2026 — use API tokens

**Critical note**: Bitbucket Cloud app passwords stop working June 9,
2026. Must use API tokens or OAuth 2.0.

## 5. Credential Storage

**Decision**: macOS Keychain via Security framework

**Rationale**: Native, secure, no third-party dependencies. Aligns with
constitution principle of preferring Apple frameworks.

**Alternatives considered**:
- KeychainAccess library: Nicer API but adds unnecessary dependency.
- UserDefaults: Not secure for tokens.

**Key details**:
- Use `SecItemAdd`/`SecItemCopyMatching` with `kSecClassGenericPassword`
- Service identifier per integration (e.g., `com.app.jira`, `com.app.bitbucket`)
- `kSecAttrAccessibleWhenUnlocked` for accessibility level

## 6. Active Window Detection (P5)

**Decision**: NSWorkspace notifications + Accessibility API + ScriptingBridge

**Rationale**: Event-based detection (NSWorkspace notifications) is
energy-efficient and Apple-recommended. ScriptingBridge provides
browser-specific tab title access for Safari and Chrome.

**Alternatives considered**:
- CGWindowListCopyWindowInfo: Can list windows but doesn't indicate
  which is focused without combining with NSWorkspace.
- Polling-based: Energy inefficient, Apple explicitly discourages.
- Swindler library: Comprehensive but adds dependency for what's
  achievable with native APIs.

**Key details**:
- `NSWorkspace.didActivateApplicationNotification` for app switches
- Accessibility API (`AXUIElement`) for window titles
- ScriptingBridge for Safari/Chrome tab URL and title
- Firefox: fallback to Accessibility API window title parsing
- IOKit `HIDIdleTime` for idle detection (check every 30s)
- Requires Accessibility permission (`AXIsProcessTrusted()`)
- Requires Apple Events entitlement for browser scripting

## 7. Background Sync

**Decision**: `NSBackgroundActivityScheduler` for periodic sync

**Rationale**: Native macOS API designed for energy-efficient background
tasks. Supports configurable intervals with system-managed tolerance.

**Key details**:
- 15-minute default interval with 3-minute tolerance
- `.utility` quality of service
- Handles both Jira and Bitbucket sync in single scheduled task
- Falls back gracefully when offline (skip sync, retain cache)
- Explicit `context.save()` after sync completes

## 8. Minimum macOS Version

**Decision**: macOS 14 Sonoma

**Rationale**: SwiftData requires macOS 14 for best stability.
MenuBarExtra requires macOS 13 but SwiftData is the binding constraint.
macOS 14 also provides `@Observable` macro which simplifies state
management between WindowGroup and MenuBarExtra.
