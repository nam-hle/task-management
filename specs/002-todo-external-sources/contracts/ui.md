# UI Interface Contract

**Feature Branch**: `002-todo-external-sources`
**Date**: 2026-02-13

## Overview

The unified list view needs to display both local todos and external tasks in a single list. A `ListItem` interface provides the abstraction layer. Both `model.Todo` and `model.Task` implement this interface.

## ListItem Interface

```go
// ListItem is the common interface for items displayed in the unified list view.
// Both Todo (local) and Task (external) implement this interface.
type ListItem interface {
    // Identity
    GetID() string          // Unique identifier
    GetTitle() string       // Display title
    GetDescription() string // Longer description text

    // State
    GetStatus() string      // Normalized: "open", "complete", "in_progress", "review", "done"
    GetPriority() int       // 1-5 (1=highest)
    IsCompleted() bool      // Convenience: status is "complete" or "done"

    // Source
    GetSource() string      // "local", "jira", "bitbucket", "email"
    IsLocal() bool          // Convenience: source == "local"

    // Timestamps
    GetCreatedAt() time.Time
    GetUpdatedAt() time.Time

    // Todo-specific (return zero values for external tasks)
    GetDueDate() *time.Time // nil if no due date
    IsOverdue() bool        // due_date < now && !IsCompleted()
    GetProjectID() *string  // nil if no project
    GetSortOrder() int      // Custom sort position (0 for external tasks)
}
```

## Implementation: Todo → ListItem

```go
func (t Todo) GetID() string          { return t.ID }
func (t Todo) GetTitle() string       { return t.Title }
func (t Todo) GetDescription() string { return t.Description }
func (t Todo) GetStatus() string      { return t.Status } // "open" or "complete"
func (t Todo) GetPriority() int       { return t.Priority }
func (t Todo) IsCompleted() bool      { return t.Status == "complete" }
func (t Todo) GetSource() string      { return "local" }
func (t Todo) IsLocal() bool          { return true }
func (t Todo) GetCreatedAt() time.Time { return t.CreatedAt }
func (t Todo) GetUpdatedAt() time.Time { return t.UpdatedAt }
func (t Todo) GetDueDate() *time.Time { return t.DueDate }
func (t Todo) IsOverdue() bool {
    return t.DueDate != nil && t.DueDate.Before(time.Now()) && t.Status != "complete"
}
func (t Todo) GetProjectID() *string  { return t.ProjectID }
func (t Todo) GetSortOrder() int      { return t.SortOrder }
```

## Implementation: Task → ListItem

```go
func (t Task) GetID() string          { return t.ID }
func (t Task) GetTitle() string       { return t.Title }
func (t Task) GetDescription() string { return t.Description }
func (t Task) GetStatus() string      { return t.Status } // "open", "in_progress", "review", "done"
func (t Task) GetPriority() int       { return t.Priority }
func (t Task) IsCompleted() bool      { return t.Status == "done" }
func (t Task) GetSource() string      { return string(t.SourceType) }
func (t Task) IsLocal() bool          { return false }
func (t Task) GetCreatedAt() time.Time { return t.CreatedAt }
func (t Task) GetUpdatedAt() time.Time { return t.UpdatedAt }
func (t Task) GetDueDate() *time.Time { return nil } // External tasks don't expose due dates
func (t Task) IsOverdue() bool        { return false }
func (t Task) GetProjectID() *string  { return nil }
func (t Task) GetSortOrder() int      { return 0 }
```

## Unified List Merge Strategy

```text
1. Fetch local todos from store (filtered by TodoFilter)
2. Fetch external tasks from store (filtered by TaskFilter)
3. Convert both to []ListItem
4. Merge into single slice
5. Apply unified sort:
   - If sort_by == "sort_order": local todos by sort_order, external by updated_at (interleaved)
   - If sort_by == "priority": all items by priority (ascending)
   - If sort_by == "updated_at": all items by updated_at (descending)
   - If sort_by == "due_date": items with due dates first (ascending), then items without
6. Apply completed visibility toggle:
   - If show_completed == false: filter out items where IsCompleted() == true
```

## View States (Extended)

```text
Existing views (unchanged):
  ViewList, ViewDetail, ViewConfig, ViewAI, ViewHelp, ViewCommand

New views:
  ViewTodoCreate    - Huh form for creating a new todo
  ViewTodoEdit      - Huh form for editing an existing todo
  ViewProjectList   - Project management (list, create, edit, archive)
  ViewTagList       - Tag management (list, create, edit, delete)
```

## Key Bindings (Extended)

```text
Global (added):
  n         → New todo (opens ViewTodoCreate)
  p         → Project list (opens ViewProjectList)
  t         → Tag list (opens ViewTagList)

List view (added):
  x         → Toggle complete on selected item (local todos only)
  e         → Edit selected item (local todos only, opens ViewTodoEdit)
  d         → Delete selected item with confirmation (local todos only)
  Tab       → Cycle sort mode (existing, add "due_date" option)
  H         → Toggle show/hide completed items
  1-5       → Filter by source (extend: 1=all, 2=local, 3=jira, 4=bitbucket, 5=email)

Todo form:
  Enter     → Submit form
  Esc       → Cancel and return to list
  Tab       → Next field
  Shift+Tab → Previous field
```

## List Item Rendering

```text
Local todo (open):
  ○ [P2] Buy groceries                          📁 Personal  🏷 errands  📅 Feb 15

Local todo (complete, dimmed):
  ✓ [P3] Fix leaky faucet                       📁 Home      🏷 urgent       (dim)

Local todo (overdue):
  ○ [P1] Submit tax return                       📁 Finance   🏷 deadline 🔴 OVERDUE

External item (Jira):
  ● [P2] PROJ-123: Fix login timeout             🔷 Jira      In Progress

External item (Bitbucket):
  ● [P3] PR #45: Refactor auth module            🟠 Bitbucket  Needs Review

External item (Email):
  ● [P4] Re: Meeting agenda                      📧 Email     Unread
```
