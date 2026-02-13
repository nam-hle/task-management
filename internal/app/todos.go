package app

import (
	"context"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source"
	"github.com/nhle/task-management/internal/store"
	"github.com/nhle/task-management/internal/ui/detail"
)

// todoCreatedResultMsg is sent after a todo is persisted.
type todoCreatedResultMsg struct{ err error }

// todoUpdatedResultMsg is sent after a todo is updated.
type todoUpdatedResultMsg struct{ err error }

// todoDeletedResultMsg is sent after a todo is deleted.
type todoDeletedResultMsg struct{ err error }

// todoDetailLoadedMsg carries a loaded todo converted to ItemDetail.
type todoDetailLoadedMsg struct {
	detail *source.ItemDetail
}

// todoEditReadyMsg carries the todo to be edited.
type todoEditReadyMsg struct {
	todo model.Todo
}

// todoFormOptionsLoadedMsg carries projects and tags for the form.
type todoFormOptionsLoadedMsg struct {
	projects []model.Project
	tags     []model.Tag
}

// createTodo persists a new todo and sets its tags.
func (m *Model) createTodo(todo model.Todo, tagIDs []string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		err := s.CreateTodo(ctx, todo)
		if err != nil {
			return todoCreatedResultMsg{err: err}
		}
		if len(tagIDs) > 0 {
			_ = s.SetTodoTags(ctx, todo.ID, tagIDs)
		}
		return todoCreatedResultMsg{err: nil}
	}
}

// updateTodo persists an updated todo and sets its tags.
func (m *Model) updateTodo(todo model.Todo, tagIDs []string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		existing, err := s.GetTodoByID(ctx, todo.ID)
		if err != nil {
			return todoUpdatedResultMsg{err: err}
		}

		existing.Title = todo.Title
		existing.Description = todo.Description
		existing.Priority = todo.Priority
		existing.Status = todo.Status
		existing.DueDate = todo.DueDate
		existing.ProjectID = todo.ProjectID

		err = s.UpdateTodo(ctx, *existing)
		if err != nil {
			return todoUpdatedResultMsg{err: err}
		}
		_ = s.SetTodoTags(ctx, todo.ID, tagIDs)
		return todoUpdatedResultMsg{err: nil}
	}
}

// deleteTodo removes a todo from the store.
func (m *Model) deleteTodo(id string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		err := s.DeleteTodo(context.Background(), id)
		return todoDeletedResultMsg{err: err}
	}
}

// toggleTodoComplete toggles a todo between open and complete.
func (m *Model) toggleTodoComplete(item model.ListItem) tea.Cmd {
	s := m.store
	id := item.GetID()
	return func() tea.Msg {
		todo, err := s.GetTodoByID(context.Background(), id)
		if err != nil {
			return todoUpdatedResultMsg{err: err}
		}
		if todo.Status == model.TodoStatusComplete {
			todo.Status = model.TodoStatusOpen
		} else {
			todo.Status = model.TodoStatusComplete
		}
		err = s.UpdateTodo(context.Background(), *todo)
		return todoUpdatedResultMsg{err: err}
	}
}

// loadFormOptions loads projects and tags for the todo form.
func (m *Model) loadFormOptions() tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		projects, _ := s.GetProjects(ctx, false)
		tags, _ := s.GetTags(ctx)
		return todoFormOptionsLoadedMsg{projects: projects, tags: tags}
	}
}

// startEditSelectedTodo loads a todo by ID and prepares for edit.
func (m *Model) startEditSelectedTodo(id string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		todo, err := s.GetTodoByID(ctx, id)
		if err != nil || todo == nil {
			return todoDetailLoadedMsg{detail: nil}
		}
		// Load tags for this todo
		tags, _ := s.GetTagsForTodo(ctx, id)
		todo.Tags = tags
		return todoEditReadyMsg{todo: *todo}
	}
}

// loadTodoDetail loads a todo and converts it to an ItemDetail for the detail view.
func (m *Model) loadTodoDetail(id string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		todo, err := s.GetTodoByID(ctx, id)
		if err != nil || todo == nil {
			return todoDetailLoadedMsg{detail: nil}
		}

		// Load checklist items
		checklist, _ := s.GetChecklistItems(ctx, id)

		// Load tags
		tags, _ := s.GetTagsForTodo(ctx, id)

		// Build description with checklist
		desc := todo.Description
		if len(checklist) > 0 {
			desc += "\n\n--- Checklist ---\n"
			for _, item := range checklist {
				check := "☐"
				if item.Checked {
					check = "☑"
				}
				desc += check + " " + item.Text + "\n"
			}
		}

		detail := &source.ItemDetail{
			Task: model.Task{
				ID:          todo.ID,
				Title:       todo.Title,
				Description: todo.Description,
				Status:      todo.Status,
				Priority:    todo.Priority,
				SourceType:  "local",
				CreatedAt:   todo.CreatedAt,
				UpdatedAt:   todo.UpdatedAt,
			},
			RenderedBody: desc,
			Metadata:     make(map[string]string),
		}

		if todo.DueDate != nil {
			detail.Metadata["Due Date"] = todo.DueDate.Format("2006-01-02")
		}
		if todo.CompletedAt != nil {
			detail.Metadata["Completed"] = todo.CompletedAt.Format("2006-01-02 15:04")
		}
		if todo.ProjectID != nil {
			// Load project name
			project, err := s.GetProjectByID(ctx, *todo.ProjectID)
			if err == nil && project != nil {
				detail.Metadata["Project"] = project.Name
			}
		}
		if len(tags) > 0 {
			var tagNames []string
			for _, t := range tags {
				tagNames = append(tagNames, t.Name)
			}
			detail.Metadata["Tags"] = joinStrings(tagNames, ", ")
		}

		return todoDetailLoadedMsg{detail: detail}
	}
}

// loadLinksForItem loads links for a todo or task and sends them to the detail view.
func (m *Model) loadLinksForItem(itemID string, isLocal bool) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		var links []model.Link
		var err error
		if isLocal {
			links, err = s.GetLinksForTodo(ctx, itemID)
		} else {
			links, err = s.GetLinksForTask(ctx, itemID)
		}
		if err != nil {
			return detail.LinksLoadedMsg{Links: nil}
		}
		return detail.LinksLoadedMsg{Links: links}
	}
}

// loadAvailableTasksForLinking loads external tasks for the link picker.
func (m *Model) loadAvailableTasksForLinking() tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		tasks, err := s.GetTasks(ctx, store.TaskFilter{Limit: 100})
		if err != nil {
			return detail.LinkPickerOpenMsg{Tasks: nil}
		}
		return detail.LinkPickerOpenMsg{Tasks: tasks}
	}
}

// deleteLink removes a link and reloads links.
func (m *Model) deleteLink(linkID string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		err := s.DeleteLink(context.Background(), linkID)
		return detail.LinkDeletedResultMsg{Err: err}
	}
}

func joinStrings(strs []string, sep string) string {
	result := ""
	for i, s := range strs {
		if i > 0 {
			result += sep
		}
		result += s
	}
	return result
}
