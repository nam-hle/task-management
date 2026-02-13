package tasklist

import (
	"context"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/keys"
	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/store"
	"github.com/nhle/task-management/internal/theme"
)

// TasksLoadedMsg is sent when tasks have been loaded from the store.
type TasksLoadedMsg struct {
	Tasks []model.Task
}

// SelectedTaskMsg is sent when a user selects a task to view details.
type SelectedTaskMsg struct {
	TaskID string
}

// sortModes defines the available sort modes cycled by Tab.
var sortModes = []string{
	"updated_at",
	"priority",
	"title",
	"status",
	"created_at",
}

// Model is the main task list view component.
type Model struct {
	list          list.Model
	store         store.Store
	keys          *keys.KeyMap
	filter        store.TaskFilter
	sourceFilters map[model.SourceType]bool
	sortIndex     int
	searchMode    bool
	searchInput   textinput.Model
	width         int
	height        int
}

// New creates a new task list model.
func New(s store.Store, k *keys.KeyMap, width, height int) Model {
	delegate := TaskDelegate{}
	l := list.New([]list.Item{}, delegate, width, height-2)
	l.Title = "Tasks"
	l.SetShowStatusBar(true)
	l.SetShowHelp(false)
	l.SetFilteringEnabled(false)
	l.Styles.Title = theme.HeaderStyle

	si := textinput.New()
	si.Placeholder = "search tasks..."
	si.Prompt = "/ "
	si.Width = width - 4

	return Model{
		list:  l,
		store: s,
		keys:  k,
		filter: store.TaskFilter{
			SortBy:   "updated_at",
			SortDesc: true,
		},
		sourceFilters: make(map[model.SourceType]bool),
		sortIndex:     0,
		searchInput:   si,
		width:         width,
		height:        height,
	}
}

// Init returns a command that loads the initial set of tasks.
func (m Model) Init() tea.Cmd {
	return m.LoadTasks()
}

// Update handles messages for the task list view.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case TasksLoadedMsg:
		items := make([]list.Item, len(msg.Tasks))
		for i, task := range msg.Tasks {
			items[i] = TaskItem{Task: task}
		}
		cmd := m.list.SetItems(items)
		return m, cmd

	case tea.KeyMsg:
		if m.searchMode {
			return m.handleSearchKeys(msg)
		}
		return m.handleNormalKeys(msg)
	}

	// Delegate to list model for other messages
	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

// handleSearchKeys processes key input while in search mode.
func (m Model) handleSearchKeys(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		m.searchMode = false
		query := m.searchInput.Value()
		if query != "" {
			m.filter.Query = &query
		} else {
			m.filter.Query = nil
		}
		return m, m.LoadTasks()

	case "esc":
		m.searchMode = false
		m.searchInput.Reset()
		m.filter.Query = nil
		return m, m.LoadTasks()
	}

	var cmd tea.Cmd
	m.searchInput, cmd = m.searchInput.Update(msg)
	return m, cmd
}

// handleNormalKeys processes key input in normal (non-search) mode.
func (m Model) handleNormalKeys(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Select):
		item, ok := m.list.SelectedItem().(TaskItem)
		if !ok {
			return m, nil
		}
		return m, func() tea.Msg {
			return SelectedTaskMsg{TaskID: item.Task.ID}
		}

	case key.Matches(msg, m.keys.Search):
		m.searchMode = true
		m.searchInput.Reset()
		return m, m.searchInput.Focus()

	case key.Matches(msg, m.keys.FilterJira):
		m.toggleSourceFilter(model.SourceTypeJira)
		return m, m.LoadTasks()

	case key.Matches(msg, m.keys.FilterBitbucket):
		m.toggleSourceFilter(model.SourceTypeBitbucket)
		return m, m.LoadTasks()

	case key.Matches(msg, m.keys.FilterEmail):
		m.toggleSourceFilter(model.SourceTypeEmail)
		return m, m.LoadTasks()

	case key.Matches(msg, m.keys.CycleSort):
		m.sortIndex = (m.sortIndex + 1) % len(sortModes)
		m.filter.SortBy = sortModes[m.sortIndex]
		return m, m.LoadTasks()
	}

	// Delegate to the list for navigation keys (up/down/pgup/pgdn)
	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

// toggleSourceFilter toggles a source type filter on or off and
// updates the filter struct accordingly.
func (m *Model) toggleSourceFilter(st model.SourceType) {
	if m.sourceFilters[st] {
		delete(m.sourceFilters, st)
	} else {
		m.sourceFilters[st] = true
	}

	// Count active source filters
	var activeTypes []model.SourceType
	for st, active := range m.sourceFilters {
		if active {
			activeTypes = append(activeTypes, st)
		}
	}

	// If exactly one source filter is active, apply it; otherwise show all
	if len(activeTypes) == 1 {
		s := string(activeTypes[0])
		m.filter.SourceType = &s
	} else {
		m.filter.SourceType = nil
	}
}

// View renders the task list view.
func (m Model) View() string {
	if m.searchMode {
		searchBar := lipgloss.NewStyle().
			Foreground(theme.ColorWhite).
			Padding(0, 1).
			Render(m.searchInput.View())
		return lipgloss.JoinVertical(lipgloss.Left, searchBar, m.list.View())
	}

	if len(m.list.Items()) == 0 {
		return m.renderEmptyState()
	}

	return m.list.View()
}

// renderEmptyState shows guidance text when no tasks are available.
func (m Model) renderEmptyState() string {
	hasFilters := m.filter.SourceType != nil ||
		m.filter.Status != nil ||
		m.filter.Priority != nil ||
		m.filter.Query != nil

	style := lipgloss.NewStyle().
		Width(m.width).
		Height(m.height).
		Align(lipgloss.Center, lipgloss.Center).
		Foreground(theme.ColorGray)

	if hasFilters {
		return style.Render("No matching tasks.\nTry adjusting your filters.")
	}

	return style.Render(
		"No tasks found.\n\n" +
			"Press : then type 'configure' to add a source.",
	)
}

// LoadTasks returns a tea.Cmd that queries the store with the current filter.
func (m Model) LoadTasks() tea.Cmd {
	filter := m.filter
	s := m.store
	return func() tea.Msg {
		tasks, err := s.GetTasks(context.Background(), filter)
		if err != nil {
			return TasksLoadedMsg{Tasks: nil}
		}
		return TasksLoadedMsg{Tasks: tasks}
	}
}

// SetSize updates the list dimensions.
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.list.SetSize(width, height-2)
	m.searchInput.Width = width - 4
}
