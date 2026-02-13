# Store Interface Contract

**Feature Branch**: `002-todo-external-sources`
**Date**: 2026-02-13

## Overview

The existing `Store` interface is extended with methods for local todo management. New methods are grouped by entity. The existing Task/Source/Notification methods remain unchanged.

## Filter Types

### TodoFilter

```go
type TodoFilter struct {
    Status    *string    // "open", "complete", or nil (all)
    Priority  *int       // 1-5 or nil (all)
    ProjectID *string    // project UUID, "inbox" (NULL project_id), or nil (all)
    TagIDs    []string   // filter by any of these tags (OR logic)
    Query     *string    // search title + description
    DueDate   *string    // "today", "upcoming" (next 7 days), "overdue", or nil
    SortBy    string     // "sort_order", "priority", "due_date", "created_at", "updated_at", "title"
    SortDesc  bool       // descending sort
    Limit     int        // pagination limit (0 = all)
    Offset    int        // pagination offset
}
```

## Extended Store Interface

```go
type Store interface {
    // === Existing (unchanged) ===
    UpsertTasks(ctx context.Context, tasks []model.Task) error
    GetTasks(ctx context.Context, filter TaskFilter) ([]model.Task, error)
    GetTaskByID(ctx context.Context, id string) (*model.Task, error)
    UpsertSource(ctx context.Context, src model.SourceConfig) error
    GetSources(ctx context.Context) ([]model.SourceConfig, error)
    DeleteSource(ctx context.Context, id string) error
    CreateNotification(ctx context.Context, n model.Notification) error
    GetUnreadNotifications(ctx context.Context) ([]model.Notification, error)
    MarkNotificationRead(ctx context.Context, id string) error

    // === Todo CRUD (NEW) ===
    CreateTodo(ctx context.Context, todo model.Todo) error
    UpdateTodo(ctx context.Context, todo model.Todo) error
    DeleteTodo(ctx context.Context, id string) error
    GetTodoByID(ctx context.Context, id string) (*model.Todo, error)
    GetTodos(ctx context.Context, filter TodoFilter) ([]model.Todo, error)
    GetTodoCount(ctx context.Context, filter TodoFilter) (int, error)
    ReorderTodo(ctx context.Context, id string, newSortOrder int) error

    // === Project CRUD (NEW) ===
    CreateProject(ctx context.Context, project model.Project) error
    UpdateProject(ctx context.Context, project model.Project) error
    DeleteProject(ctx context.Context, id string) error
    GetProjectByID(ctx context.Context, id string) (*model.Project, error)
    GetProjects(ctx context.Context, includeArchived bool) ([]model.Project, error)
    ArchiveProject(ctx context.Context, id string) error
    RestoreProject(ctx context.Context, id string) error

    // === Tag CRUD (NEW) ===
    CreateTag(ctx context.Context, tag model.Tag) error
    UpdateTag(ctx context.Context, tag model.Tag) error
    DeleteTag(ctx context.Context, id string) error
    GetTags(ctx context.Context) ([]model.Tag, error)
    GetTagsForTodo(ctx context.Context, todoID string) ([]model.Tag, error)
    SetTodoTags(ctx context.Context, todoID string, tagIDs []string) error

    // === Checklist CRUD (NEW) ===
    AddChecklistItem(ctx context.Context, item model.ChecklistItem) error
    UpdateChecklistItem(ctx context.Context, item model.ChecklistItem) error
    DeleteChecklistItem(ctx context.Context, id string) error
    GetChecklistItems(ctx context.Context, todoID string) ([]model.ChecklistItem, error)
    ToggleChecklistItem(ctx context.Context, id string) error
    ReorderChecklistItem(ctx context.Context, id string, newSortOrder int) error

    // === Link Management (NEW) ===
    CreateLink(ctx context.Context, link model.Link) error
    DeleteLink(ctx context.Context, id string) error
    GetLinksForTodo(ctx context.Context, todoID string) ([]model.Link, error)
    GetLinksForTask(ctx context.Context, taskID string) ([]model.Link, error)
}
```

## Method Contracts

### CreateTodo
- **Input**: Todo with at least a non-empty title. ID is generated (UUID) if empty.
- **Behavior**: Sets created_at/updated_at to now. Sets sort_order to max+1 if 0. Validates priority 1-5, status open/complete.
- **Error**: If title is empty. If project_id references non-existent project.

### UpdateTodo
- **Input**: Todo with existing ID and updated fields.
- **Behavior**: Sets updated_at to now. If status changed to 'complete', sets completed_at. If status changed to 'open', clears completed_at.
- **Error**: If ID not found. If title is empty.

### DeleteTodo
- **Input**: Todo ID.
- **Behavior**: Deletes todo and cascades to checklist_items, todo_tags, links.
- **Error**: If ID not found.

### GetTodos
- **Input**: TodoFilter with optional constraints.
- **Behavior**: Returns todos matching all specified filters (AND logic). TagIDs filter uses OR (any matching tag). Includes associated tags and checklist item count in response.
- **Output**: Ordered slice of todos. Empty slice if no matches.

### SetTodoTags
- **Input**: Todo ID and list of tag IDs.
- **Behavior**: Replaces all tag associations for the todo. Empty list removes all tags.
- **Error**: If todo ID not found. If any tag ID not found.

### ToggleChecklistItem
- **Input**: Checklist item ID.
- **Behavior**: Flips checked state (0→1, 1→0).
- **Error**: If ID not found.

### ReorderTodo
- **Input**: Todo ID and new sort_order value.
- **Behavior**: Updates the sort_order for the specified todo. Does NOT reorder other todos (caller manages relative positioning).
- **Error**: If ID not found.
