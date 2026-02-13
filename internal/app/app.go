package app

import (
	"context"
	"fmt"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nhle/task-management/internal/store"
	appsync "github.com/nhle/task-management/internal/sync"
	"github.com/nhle/task-management/internal/ui"
	"github.com/nhle/task-management/internal/ui/command"
	configview "github.com/nhle/task-management/internal/ui/config"
	"github.com/nhle/task-management/internal/ui/detail"
	helpview "github.com/nhle/task-management/internal/ui/help"
	"github.com/nhle/task-management/internal/ui/tasklist"
)

// ViewState represents the current active view in the application.
type ViewState int

const (
	ViewList ViewState = iota
	ViewDetail
	ViewConfig
	ViewAI
	ViewHelp
	ViewCommand
)

// Model is the root Bubble Tea model that manages view routing,
// layout, and access to the persistence layer.
type Model struct {
	currentView  ViewState
	previousView ViewState
	layout       ui.Layout
	store        *store.SQLiteStore
	keys         *KeyMap
	taskList     tasklist.Model
	detail       detail.Model
	helpView     helpview.Model
	commandView  command.Model
	configView   configview.Model
	poller       *appsync.Poller
	ready        bool
}

// New creates a new root application model with the given store.
func New(s *store.SQLiteStore) Model {
	keys := DefaultKeyMap()
	p := appsync.New(s)

	return Model{
		currentView: ViewList,
		store:       s,
		keys:        keys,
		taskList:    tasklist.New(s, keys, 80, 24),
		detail:      detail.New(s, keys, 80, 24),
		helpView:    helpview.New(keys, 80, 24),
		commandView: command.New(80, 24),
		configView:  configview.New(s, keys, 80, 24),
		poller:      p,
	}
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
		return m, nil

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
		// After a sync completes, reload the task list
		cmd := m.taskList.LoadTasks()
		// Keep listening for more results
		waitCmd := m.poller.WaitForNextResult()
		return m, tea.Batch(cmd, waitCmd)

	case tasklist.SelectedTaskMsg:
		m.previousView = m.currentView
		m.currentView = ViewDetail
		m.detail.SetLoading(true)
		// Load task detail from store
		return m, m.loadTaskDetail(msg.TaskID)

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
			if m.currentView == ViewHelp {
				m.currentView = m.previousView
				return m, nil
			}
			m.previousView = m.currentView
			m.currentView = ViewHelp
			return m, nil

		case ":":
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

		case "r":
			if m.currentView == ViewList {
				m.poller.RefreshAll()
				return m, m.taskList.LoadTasks()
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
	case ViewHelp:
		m.helpView, cmd = m.helpView.Update(msg)
	case ViewCommand:
		m.commandView, cmd = m.commandView.Update(msg)
	}

	return m, cmd
}

// View renders the full terminal UI using the layout manager.
func (m Model) View() string {
	if !m.ready {
		return "Loading..."
	}

	header := m.layout.RenderHeader("Task Manager", m.syncStatus())
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
		return "AI assistant view"
	case ViewHelp:
		return m.helpView.View()
	case ViewCommand:
		return m.commandView.View()
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
	for _, s := range statuses {
		switch s.State {
		case appsync.SyncRunning:
			running++
		case appsync.SyncError:
			errCount++
		}
	}

	if running > 0 {
		return fmt.Sprintf("syncing (%d)", running)
	}
	if errCount > 0 {
		return fmt.Sprintf("errors (%d)", errCount)
	}
	return "idle"
}

// keyHints returns keyboard shortcut hints for the status bar.
func (m Model) keyHints() string {
	switch m.currentView {
	case ViewHelp:
		return "? close help | esc back"
	case ViewCommand:
		return ": close command | enter execute | esc back"
	case ViewDetail:
		return "esc back | c comment | t transition | p approve | j/k scroll"
	case ViewConfig:
		return "a add | e edit | d delete | enter test | esc back"
	default:
		return "q quit | ? help | c config | : command | / search | tab sort | 1/2/3 filter"
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

// executeCommand handles a command string from the command palette.
func (m *Model) executeCommand(cmd string) tea.Cmd {
	switch cmd {
	case "refresh", "sync":
		m.poller.RefreshAll()
		return m.taskList.LoadTasks()
	case "quit", "q":
		m.poller.Stop()
		return tea.Quit
	case "configure", "config":
		m.previousView = m.currentView
		m.currentView = ViewConfig
		return m.configView.Init()
	default:
		return nil
	}
}
