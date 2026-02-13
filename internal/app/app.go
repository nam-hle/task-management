package app

import (
	"context"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	aiservice "github.com/nhle/task-management/internal/ai"
	"github.com/nhle/task-management/internal/credential"
	"github.com/nhle/task-management/internal/store"
	appsync "github.com/nhle/task-management/internal/sync"
	"github.com/nhle/task-management/internal/ui"
	aiview "github.com/nhle/task-management/internal/ui/ai"
	"github.com/nhle/task-management/internal/ui/command"
	configview "github.com/nhle/task-management/internal/ui/config"
	"github.com/nhle/task-management/internal/ui/detail"
	helpview "github.com/nhle/task-management/internal/ui/help"
	"github.com/nhle/task-management/internal/ui/projectmgr"
	"github.com/nhle/task-management/internal/ui/tagmgr"
	"github.com/nhle/task-management/internal/ui/tasklist"
	"github.com/nhle/task-management/internal/ui/todoform"
)

// unreadCountMsg carries the number of unread notifications to the UI.
type unreadCountMsg struct {
	count int
}

// ViewState represents the current active view in the application.
type ViewState int

const (
	ViewList ViewState = iota
	ViewDetail
	ViewConfig
	ViewAI
	ViewHelp
	ViewCommand
	ViewTodoCreate
	ViewTodoEdit
	ViewProjectList
	ViewTagList
)

// Model is the root Bubble Tea model that manages view routing,
// layout, and access to the persistence layer.
type Model struct {
	currentView      ViewState
	previousView     ViewState
	layout           ui.Layout
	store            *store.SQLiteStore
	keys             *KeyMap
	taskList         tasklist.Model
	detail           detail.Model
	helpView         helpview.Model
	commandView      command.Model
	configView       configview.Model
	aiView           aiview.Model
	todoFormView     todoform.Model
	projectView      projectmgr.Model
	tagView          tagmgr.Model
	poller           *appsync.Poller
	ready            bool
	unreadCount      int
	authErrorMessage string
}

// New creates a new root application model with the given store.
func New(s *store.SQLiteStore) Model {
	keys := DefaultKeyMap()
	p := appsync.New(s)

	// Try to load the Claude API key for the AI assistant.
	assistant := loadAIAssistant(s)

	return Model{
		currentView: ViewList,
		store:       s,
		keys:        keys,
		taskList:    tasklist.New(s, keys, 80, 24),
		detail:      detail.New(s, keys, 80, 24),
		helpView:    helpview.New(keys, 80, 24),
		commandView:  command.New(80, 24),
		configView:   configview.New(s, keys, 80, 24),
		aiView:       aiview.New(assistant, keys, 80, 24),
		todoFormView: todoform.New(80, 24),
		projectView:  projectmgr.New(s, keys, 80, 24),
		tagView:      tagmgr.New(s, keys, 80, 24),
		poller:       p,
	}
}

// loadAIAssistant attempts to create an AI assistant by loading the API key
// from the environment variable or system keyring. Returns nil if no key
// is available.
func loadAIAssistant(s *store.SQLiteStore) *aiservice.Assistant {
	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		var err error
		apiKey, err = credential.Get("claude-api-key")
		if err != nil || apiKey == "" {
			return nil
		}
	}

	return aiservice.New(apiKey, s, "", 0)
}

// Init returns the initial commands to load tasks and start polling.
// It also registers any configured sources (e.g., Jira) before starting
// the poller so that all adapters are available for the first sync.
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.taskList.Init(),
		m.registerSources(),
	)
}

// Update handles messages and dispatches to the active view.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.layout = ui.NewLayout(msg.Width, msg.Height)
		m.ready = true
		contentWidth := m.layout.ContentWidth()
		contentHeight := m.layout.ContentHeight()
		m.taskList.SetSize(contentWidth, contentHeight)
		m.detail.SetSize(contentWidth, contentHeight)
		m.helpView.SetSize(contentWidth, contentHeight)
		m.commandView.SetSize(contentWidth, contentHeight)
		m.configView.SetSize(contentWidth, contentHeight)
		m.aiView.SetSize(contentWidth, contentHeight)
		m.todoFormView.SetSize(contentWidth, contentHeight)
		m.projectView.SetSize(contentWidth, contentHeight)
		m.tagView.SetSize(contentWidth, contentHeight)
		// Forward to active view so huh forms can calculate their layout.
		return m.updateActiveView(msg)

	case sourcesRegisteredMsg:
		// If no sources are configured, enter first-run config setup.
		if msg.count == 0 {
			m.previousView = m.currentView
			m.currentView = ViewConfig
			return m, m.configView.Init()
		}
		// Sources are registered; now start the poller.
		return m, m.poller.Start()

	case appsync.SyncResultMsg:
		// Handle auth errors by showing a status bar message.
		if msg.AuthError != nil {
			m.authErrorMessage = msg.AuthError.Message
		} else if msg.Error == nil {
			// Clear auth error for this source on successful sync.
			m.authErrorMessage = ""
		}

		// Track stale sources for the list renderer.
		src := string(msg.Source)
		if msg.Error != nil || msg.AuthError != nil {
			m.taskList.MarkSourceStale(src)
		} else {
			m.taskList.ClearSourceStale(src)
		}

		// After a sync completes, reload the task list and update
		// the unread notification count.
		cmd := m.taskList.LoadTasks()
		waitCmd := m.poller.WaitForNextResult()
		countCmd := m.fetchUnreadCount()
		return m, tea.Batch(cmd, waitCmd, countCmd)

	case unreadCountMsg:
		m.unreadCount = msg.count
		return m, nil

	case tasklist.SelectedTaskMsg:
		m.previousView = m.currentView
		m.currentView = ViewDetail
		m.detail.SetLoading(true)
		m.detail.SetIsLocalTodo(false)
		return m, tea.Batch(
			m.loadTaskDetail(msg.TaskID),
			m.loadLinksForItem(msg.TaskID, false),
		)

	case tasklist.SelectedTodoMsg:
		m.previousView = m.currentView
		m.currentView = ViewDetail
		m.detail.SetLoading(true)
		m.detail.SetIsLocalTodo(true)
		return m, tea.Batch(
			m.loadTodoDetail(msg.TodoID),
			m.loadLinksForItem(msg.TodoID, true),
		)

	case todoform.TodoCreatedMsg:
		m.currentView = ViewList
		return m, m.createTodo(msg.Todo, msg.TagIDs)

	case todoform.TodoUpdatedMsg:
		m.currentView = ViewList
		return m, m.updateTodo(msg.Todo, msg.TagIDs)

	case todoform.TodoFormCancelMsg:
		m.currentView = ViewList
		return m, nil

	case todoCreatedResultMsg:
		return m, m.taskList.LoadItems()

	case todoUpdatedResultMsg:
		return m, m.taskList.LoadItems()

	case todoDeletedResultMsg:
		return m, m.taskList.LoadItems()

	case todoDetailLoadedMsg:
		m.detail.SetLoading(false)
		if msg.detail != nil {
			m.detail.SetTask(msg.detail)
		}
		return m, nil

	case todoFormOptionsLoadedMsg:
		m.todoFormView.SetOptions(msg.projects, msg.tags)
		if m.currentView == ViewTodoCreate {
			return m, m.todoFormView.StartCreate()
		}
		return m, nil

	case todoEditReadyMsg:
		return m, m.todoFormView.StartEdit(msg.todo)

	case detail.LinkRequestMsg:
		// User pressed l in detail view to link a todo to an external task
		return m, m.loadAvailableTasksForLinking()

	case detail.UnlinkRequestMsg:
		// User pressed u in detail view to unlink
		return m, m.deleteLink(msg.LinkID)

	case detail.LinkCreatedResultMsg:
		// Link created; reload links for the current item
		var cmd tea.Cmd
		m.detail, cmd = m.detail.Update(msg)
		if m.detail.IsLocalTodo() {
			return m, tea.Batch(cmd, m.loadLinksForItem(m.detail.CurrentItemID(), true))
		}
		return m, cmd

	case detail.LinkDeletedResultMsg:
		// Link deleted; reload links for the current item
		if m.detail.IsLocalTodo() {
			return m, m.loadLinksForItem(m.detail.CurrentItemID(), true)
		}
		return m, m.loadLinksForItem(m.detail.CurrentItemID(), false)

	case detail.NavigateToLinkedItemMsg:
		m.detail.SetLoading(true)
		m.detail.SetIsLocalTodo(msg.IsLocal)
		if msg.IsLocal {
			return m, tea.Batch(
				m.loadTodoDetail(msg.ItemID),
				m.loadLinksForItem(msg.ItemID, true),
			)
		}
		return m, tea.Batch(
			m.loadTaskDetail(msg.ItemID),
			m.loadLinksForItem(msg.ItemID, false),
		)

	case detail.DetailLoadedMsg:
		var cmd tea.Cmd
		m.detail, cmd = m.detail.Update(msg)
		return m, cmd

	case detail.BackMsg:
		m.currentView = ViewList
		return m, nil

	case detail.ActionMsg:
		// Actions like comment/transition/approve
		// will be handled by source adapters in a future phase
		return m, nil

	case command.CommandMsg:
		m.currentView = m.previousView
		return m, m.executeCommand(string(msg))

	case configview.ConfigDoneMsg:
		m.currentView = ViewList
		// Re-register sources and restart polling after config changes
		return m, tea.Batch(
			m.taskList.LoadTasks(),
			m.registerSources(),
		)

	case configview.SourceSavedMsg:
		// Source was saved in config view; re-register and poll
		return m, tea.Batch(
			m.taskList.LoadTasks(),
			m.registerSources(),
		)

	case configview.SourceDeletedMsg:
		// Source was deleted; re-register and reload tasks
		return m, tea.Batch(
			m.taskList.LoadTasks(),
			m.registerSources(),
		)

	case aiview.AIPanelCloseMsg:
		m.aiView.Reset()
		m.currentView = ViewList
		return m, nil

	case aiview.AIResponseChunkMsg:
		if m.currentView == ViewAI {
			var cmd tea.Cmd
			m.aiView, cmd = m.aiView.Update(msg)
			return m, cmd
		}
		return m, nil

	case projectmgr.ProjectListCloseMsg:
		m.currentView = ViewList
		return m, nil

	case projectmgr.ProjectChangedMsg:
		return m, m.taskList.LoadItems()

	case tagmgr.TagListCloseMsg:
		m.currentView = ViewList
		return m, nil

	case tagmgr.TagChangedMsg:
		return m, m.taskList.LoadItems()

	case aiview.AINavigateTaskMsg:
		m.previousView = m.currentView
		m.currentView = ViewDetail
		m.detail.SetLoading(true)
		return m, m.loadTaskDetail(msg.TaskID)

	case tea.KeyMsg:
		// Global keys that work regardless of current view
		switch msg.String() {
		case "ctrl+c":
			m.poller.Stop()
			return m, tea.Quit

		case "q":
			if m.currentView == ViewList {
				m.poller.Stop()
				return m, tea.Quit
			}

		case "?":
			// Do not intercept when AI panel has input focus
			if m.currentView == ViewAI {
				break
			}
			if m.currentView == ViewHelp {
				m.currentView = m.previousView
				return m, nil
			}
			m.previousView = m.currentView
			m.currentView = ViewHelp
			return m, nil

		case ":":
			// Do not intercept when AI panel has input focus
			if m.currentView == ViewAI {
				break
			}
			if m.currentView == ViewCommand {
				m.currentView = m.previousView
				return m, nil
			}
			m.previousView = m.currentView
			m.currentView = ViewCommand
			return m, m.commandView.Focus()

		case "c":
			if m.currentView == ViewList {
				m.previousView = m.currentView
				m.currentView = ViewConfig
				return m, m.configView.Init()
			}

		case "a":
			if m.currentView == ViewList {
				m.previousView = m.currentView
				m.currentView = ViewAI
				return m, m.aiView.Focus()
			}

		case "r":
			if m.currentView == ViewList {
				m.poller.RefreshAll()
				return m, m.taskList.LoadItems()
			}

		case "n":
			if m.currentView == ViewList {
				m.previousView = m.currentView
				m.currentView = ViewTodoCreate
				return m, m.loadFormOptions()
			}

		case "e":
			if m.currentView == ViewList {
				item, ok := m.taskList.SelectedItem()
				if ok && item.IsLocal() {
					m.previousView = m.currentView
					m.currentView = ViewTodoEdit
					return m, tea.Batch(
						m.loadFormOptions(),
						m.startEditSelectedTodo(item.GetID()),
					)
				}
			}

		case "x":
			if m.currentView == ViewList {
				item, ok := m.taskList.SelectedItem()
				if ok && item.IsLocal() {
					return m, m.toggleTodoComplete(item)
				}
			}

		case "d":
			if m.currentView == ViewList {
				item, ok := m.taskList.SelectedItem()
				if ok && item.IsLocal() {
					return m, m.deleteTodo(item.GetID())
				}
			}

		case "H":
			if m.currentView == ViewList {
				return m, m.taskList.ToggleShowCompleted()
			}

		case "p":
			if m.currentView == ViewList {
				m.previousView = m.currentView
				m.currentView = ViewProjectList
				return m, m.projectView.Init()
			}

		case "t":
			if m.currentView == ViewList {
				m.previousView = m.currentView
				m.currentView = ViewTagList
				return m, m.tagView.Init()
			}
		}
	}

	// Delegate to active sub-view
	return m.updateActiveView(msg)
}

// updateActiveView dispatches the message to the currently active view.
func (m Model) updateActiveView(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch m.currentView {
	case ViewList:
		m.taskList, cmd = m.taskList.Update(msg)
	case ViewDetail:
		m.detail, cmd = m.detail.Update(msg)
	case ViewConfig:
		m.configView, cmd = m.configView.Update(msg)
	case ViewAI:
		m.aiView, cmd = m.aiView.Update(msg)
	case ViewHelp:
		m.helpView, cmd = m.helpView.Update(msg)
	case ViewCommand:
		m.commandView, cmd = m.commandView.Update(msg)
	case ViewTodoCreate, ViewTodoEdit:
		m.todoFormView, cmd = m.todoFormView.Update(msg)
	case ViewProjectList:
		m.projectView, cmd = m.projectView.Update(msg)
	case ViewTagList:
		m.tagView, cmd = m.tagView.Update(msg)
	}

	return m, cmd
}

// View renders the full terminal UI using the layout manager.
func (m Model) View() string {
	if !m.ready {
		return "Loading..."
	}

	headerTitle := "Task Manager"
	if m.unreadCount > 0 {
		headerTitle = fmt.Sprintf("Task Manager [%d new]", m.unreadCount)
	}
	header := m.layout.RenderHeader(headerTitle, m.syncStatus())
	content := m.renderContent()
	statusBar := m.layout.RenderStatusBar(m.keyHints())

	return m.layout.RenderWithFrame(header, content, statusBar)
}

// renderContent returns the rendered string for the current active view.
func (m Model) renderContent() string {
	switch m.currentView {
	case ViewList:
		return m.taskList.View()
	case ViewDetail:
		return m.detail.View()
	case ViewConfig:
		return m.configView.View()
	case ViewAI:
		return m.aiView.View()
	case ViewHelp:
		return m.helpView.View()
	case ViewCommand:
		return m.commandView.View()
	case ViewTodoCreate, ViewTodoEdit:
		return m.todoFormView.View()
	case ViewProjectList:
		return m.projectView.View()
	case ViewTagList:
		return m.tagView.View()
	default:
		return ""
	}
}

// syncStatus returns a short string describing the combined sync state.
func (m Model) syncStatus() string {
	statuses := m.poller.GetStatuses()
	if len(statuses) == 0 {
		return "no sources"
	}

	running := 0
	errCount := 0
	var staleNames []string
	for _, s := range statuses {
		switch s.State {
		case appsync.SyncRunning:
			running++
		case appsync.SyncError:
			errCount++
			staleNames = append(staleNames, string(s.SourceType))
		}
	}

	if running > 0 {
		return fmt.Sprintf("syncing (%d)", running)
	}
	if errCount > 0 {
		return fmt.Sprintf("⚠ unreachable: %s", joinStaleNames(staleNames))
	}
	return "idle"
}

// joinStaleNames joins source names for display.
func joinStaleNames(names []string) string {
	if len(names) == 0 {
		return ""
	}
	result := names[0]
	for i := 1; i < len(names); i++ {
		result += ", " + names[i]
	}
	return result
}

// keyHints returns keyboard shortcut hints for the status bar.
func (m Model) keyHints() string {
	// Show auth error prominently when present.
	if m.authErrorMessage != "" && m.currentView == ViewList {
		return m.authErrorMessage
	}

	switch m.currentView {
	case ViewHelp:
		return "? close help | esc back"
	case ViewCommand:
		return ": close command | enter execute | esc back"
	case ViewDetail:
		return "esc back | l link | u unlink | c comment | t transition | j/k scroll"
	case ViewConfig:
		return "a add | e edit | d delete | enter test | esc back"
	case ViewAI:
		return "enter send | esc close"
	case ViewTodoCreate, ViewTodoEdit:
		return "enter submit | esc cancel"
	case ViewProjectList:
		return "n new | e edit | a archive | d delete | esc back"
	case ViewTagList:
		return "n new | e edit | d delete | esc back"
	default:
		filterSummary := m.taskList.FilterSummary()
		if filterSummary != "" {
			return filterSummary + " | 3 clear"
		}
		return "q quit | ? help | n new | / search | 1 source | 2 date | tab sort"
	}
}

// loadTaskDetail returns a command that loads a task by ID from the store.
func (m Model) loadTaskDetail(taskID string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		task, err := s.GetTaskByID(
			context.Background(),
			taskID,
		)
		if err != nil || task == nil {
			return detail.DetailLoadedMsg{Detail: nil}
		}
		// Convert store task to source.ItemDetail
		itemDetail := taskToItemDetail(task)
		return detail.DetailLoadedMsg{Detail: itemDetail}
	}
}

// fetchUnreadCount returns a tea.Cmd that queries the store for the
// number of unread notifications.
func (m Model) fetchUnreadCount() tea.Cmd {
	s := m.store
	return func() tea.Msg {
		notifications, err := s.GetUnreadNotifications(context.Background())
		if err != nil {
			return unreadCountMsg{count: 0}
		}
		return unreadCountMsg{count: len(notifications)}
	}
}

// executeCommand handles a command string from the command palette.
func (m *Model) executeCommand(cmd string) tea.Cmd {
	switch cmd {
	case "refresh", "sync":
		m.poller.RefreshAll()
		return m.taskList.LoadItems()
	case "quit", "q":
		m.poller.Stop()
		return tea.Quit
	case "configure", "config":
		m.previousView = m.currentView
		m.currentView = ViewConfig
		return m.configView.Init()
	case "new todo", "todo":
		m.previousView = m.currentView
		m.currentView = ViewTodoCreate
		return m.loadFormOptions()
	case "toggle completed", "hide completed":
		return m.taskList.ToggleShowCompleted()
	case "projects":
		m.previousView = m.currentView
		m.currentView = ViewProjectList
		return m.projectView.Init()
	case "tags":
		m.previousView = m.currentView
		m.currentView = ViewTagList
		return m.tagView.Init()
	case "filter today", "today":
		return m.taskList.SetDateFilter("today")
	case "filter upcoming", "upcoming":
		return m.taskList.SetDateFilter("upcoming")
	case "filter overdue", "overdue":
		return m.taskList.SetDateFilter("overdue")
	case "filter local", "local":
		return m.taskList.SetSourceFilter("local")
	case "clear filters", "clear":
		return m.taskList.ClearFilters()
	default:
		return nil
	}
}
