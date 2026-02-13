package tasklist

import (
	"context"
	"sort"

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

// defaultPageSize is the number of items loaded per page.
const defaultPageSize = 50

// ItemsLoadedMsg is sent when items have been loaded from the store.
type ItemsLoadedMsg struct {
	Items  []model.ListItem
	Append bool
}

// TasksLoadedMsg is kept for backward compatibility with the poller/sync layer.
type TasksLoadedMsg struct {
	Tasks  []model.Task
	Append bool
}

// SelectedTaskMsg is sent when a user selects a task to view details.
type SelectedTaskMsg struct {
	TaskID string
}

// SelectedTodoMsg is sent when a user selects a local todo to view details.
type SelectedTodoMsg struct {
	TodoID string
}

// TodoToggleCompleteMsg is sent when user toggles the complete status.
type TodoToggleCompleteMsg struct {
	TodoID    string
	NewStatus string
}

// TodoDeleteRequestMsg is sent when user requests deletion of a todo.
type TodoDeleteRequestMsg struct {
	TodoID string
	Title  string
}

// sortModes defines the available sort modes cycled by Tab.
var sortModes = []string{
	"updated_at",
	"priority",
	"title",
	"status",
	"created_at",
}

// sourceFilterModes defines the available source filter values cycled by number keys.
var sourceFilterModes = []string{
	"all",
	"local",
	"jira",
	"bitbucket",
	"email",
}

// dateFilterModes defines the available date filter values.
var dateFilterModes = []string{
	"",         // none
	"today",
	"upcoming", // next 7 days
	"overdue",
}

// Model is the main task list view component.
type Model struct {
	list               list.Model
	store              store.Store
	keys               *keys.KeyMap
	taskFilter         store.TaskFilter
	todoFilter         store.TodoFilter
	sourceFilterIndex  int    // index into sourceFilterModes
	activeProjectFilter *string  // nil=all, ""=inbox (no project), UUID=specific
	activeTagFilter    []string // tag IDs to filter by
	staleSources       map[string]bool // shared with delegate by reference
	dateFilterIndex    int    // index into dateFilterModes
	sortIndex          int
	searchMode         bool
	searchInput        textinput.Model
	showCompleted      bool
	width              int
	height             int
	hasMore            bool
	loadingMore        bool
	currentOffset      int
}

// New creates a new task list model.
func New(s store.Store, k *keys.KeyMap, width, height int) Model {
	stale := make(map[string]bool)
	delegate := ItemDelegate{staleSources: stale}
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
		taskFilter: store.TaskFilter{
			SortBy:   "updated_at",
			SortDesc: true,
		},
		todoFilter: store.TodoFilter{
			SortBy:   "updated_at",
			SortDesc: true,
		},
		staleSources: stale,
		sortIndex:    0,
		searchInput:  si,
		showCompleted: true,
		width:        width,
		height:       height,
	}
}

// Init returns a command that loads the initial set of items.
func (m Model) Init() tea.Cmd {
	return m.LoadItems()
}

// Update handles messages for the task list view.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case ItemsLoadedMsg:
		return m.handleItemsLoaded(msg)

	case TasksLoadedMsg:
		// Convert old-style TasksLoadedMsg to ItemsLoadedMsg for compatibility
		items := make([]model.ListItem, len(msg.Tasks))
		for i, task := range msg.Tasks {
			items[i] = task
		}
		return m.handleItemsLoaded(ItemsLoadedMsg{Items: items, Append: msg.Append})

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

func (m Model) handleItemsLoaded(msg ItemsLoadedMsg) (Model, tea.Cmd) {
	// Filter out completed items if showCompleted is false
	var filtered []model.ListItem
	for _, item := range msg.Items {
		if !m.showCompleted && item.IsCompleted() {
			continue
		}
		filtered = append(filtered, item)
	}

	newItems := make([]list.Item, len(filtered))
	for i, item := range filtered {
		newItems[i] = ListItemWrapper{Item: item}
	}

	if msg.Append {
		existing := m.list.Items()
		combined := append(existing, newItems...)
		cmd := m.list.SetItems(combined)
		m.loadingMore = false
		m.currentOffset = len(combined)
		m.hasMore = len(msg.Items) >= defaultPageSize
		return m, cmd
	}
	cmd := m.list.SetItems(newItems)
	m.currentOffset = len(newItems)
	m.hasMore = len(msg.Items) >= defaultPageSize
	m.loadingMore = false
	return m, cmd
}

// handleSearchKeys processes key input while in search mode.
func (m Model) handleSearchKeys(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		m.searchMode = false
		query := m.searchInput.Value()
		if query != "" {
			m.taskFilter.Query = &query
			m.todoFilter.Query = &query
		} else {
			m.taskFilter.Query = nil
			m.todoFilter.Query = nil
		}
		return m, m.LoadItems()

	case "esc":
		m.searchMode = false
		m.searchInput.Reset()
		m.taskFilter.Query = nil
		m.todoFilter.Query = nil
		return m, m.LoadItems()
	}

	var cmd tea.Cmd
	m.searchInput, cmd = m.searchInput.Update(msg)
	return m, cmd
}

// handleNormalKeys processes key input in normal (non-search) mode.
func (m Model) handleNormalKeys(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Select):
		item, ok := m.list.SelectedItem().(ListItemWrapper)
		if !ok {
			return m, nil
		}
		if item.Item.IsLocal() {
			return m, func() tea.Msg {
				return SelectedTodoMsg{TodoID: item.Item.GetID()}
			}
		}
		return m, func() tea.Msg {
			return SelectedTaskMsg{TaskID: item.Item.GetID()}
		}

	case key.Matches(msg, m.keys.Search):
		m.searchMode = true
		m.searchInput.Reset()
		return m, m.searchInput.Focus()

	case key.Matches(msg, m.keys.FilterJira):
		// 1 = cycle source filter: all → local → jira → bitbucket → email → all
		m.sourceFilterIndex = (m.sourceFilterIndex + 1) % len(sourceFilterModes)
		m.applySourceFilter()
		return m, m.LoadItems()

	case key.Matches(msg, m.keys.FilterBitbucket):
		// 2 = cycle date filter: none → today → upcoming → overdue → none
		m.dateFilterIndex = (m.dateFilterIndex + 1) % len(dateFilterModes)
		m.applyDateFilter()
		return m, m.LoadItems()

	case key.Matches(msg, m.keys.FilterEmail):
		// 3 = clear all filters
		return m, m.ClearFilters()

	case key.Matches(msg, m.keys.CycleSort):
		m.sortIndex = (m.sortIndex + 1) % len(sortModes)
		m.taskFilter.SortBy = sortModes[m.sortIndex]
		m.todoFilter.SortBy = sortModes[m.sortIndex]
		return m, m.LoadItems()
	}

	// Delegate to the list for navigation keys (up/down/pgup/pgdn)
	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)

	// Check if user scrolled near the bottom to trigger loading more.
	if m.hasMore && !m.loadingMore {
		totalItems := len(m.list.Items())
		cursorIdx := m.list.Index()
		if totalItems > 0 && cursorIdx >= totalItems-3 {
			m.loadingMore = true
			loadMoreCmd := m.loadMoreItems()
			return m, tea.Batch(cmd, loadMoreCmd)
		}
	}

	return m, cmd
}

// applySourceFilter updates the task/todo filters based on sourceFilterIndex.
func (m *Model) applySourceFilter() {
	mode := sourceFilterModes[m.sourceFilterIndex]
	switch mode {
	case "all", "local":
		m.taskFilter.SourceType = nil
	default:
		m.taskFilter.SourceType = &mode
	}
}

// applyDateFilter updates the todo filter based on dateFilterIndex.
func (m *Model) applyDateFilter() {
	mode := dateFilterModes[m.dateFilterIndex]
	if mode == "" {
		m.todoFilter.DueDate = nil
	} else {
		m.todoFilter.DueDate = &mode
	}
}

// activeSourceFilter returns the current source filter mode name.
func (m Model) activeSourceFilter() string {
	return sourceFilterModes[m.sourceFilterIndex]
}

// activeDateFilter returns the current date filter mode name.
func (m Model) activeDateFilter() string {
	return dateFilterModes[m.dateFilterIndex]
}

// ToggleShowCompleted flips the showCompleted flag and reloads.
func (m *Model) ToggleShowCompleted() tea.Cmd {
	m.showCompleted = !m.showCompleted
	return m.LoadItems()
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

	// Show filter summary bar if any filters are active
	summary := m.FilterSummary()
	if summary != "" {
		filterBar := lipgloss.NewStyle().
			Foreground(theme.ColorYellow).
			Padding(0, 1).
			Render(summary)
		return lipgloss.JoinVertical(lipgloss.Left, filterBar, m.list.View())
	}

	return m.list.View()
}

// renderEmptyState shows guidance text when no tasks are available.
func (m Model) renderEmptyState() string {
	hasFilters := m.taskFilter.SourceType != nil ||
		m.taskFilter.Status != nil ||
		m.taskFilter.Priority != nil ||
		m.taskFilter.Query != nil ||
		m.sourceFilterIndex != 0 ||
		m.dateFilterIndex != 0 ||
		m.activeProjectFilter != nil ||
		len(m.activeTagFilter) > 0

	style := lipgloss.NewStyle().
		Width(m.width).
		Height(m.height).
		Align(lipgloss.Center, lipgloss.Center).
		Foreground(theme.ColorGray)

	if hasFilters {
		return style.Render("No matching items.\nTry adjusting your filters.")
	}

	return style.Render(
		"No items found.\n\n" +
			"Press n to create a new todo, or\n" +
			"press c to configure an external source.",
	)
}

// SetProjectFilter sets the active project filter.
// nil=all, ""=inbox (no project), UUID=specific project.
func (m *Model) SetProjectFilter(projectID *string) tea.Cmd {
	m.activeProjectFilter = projectID
	return m.LoadItems()
}

// SetTagFilter sets the active tag filter.
func (m *Model) SetTagFilter(tagIDs []string) tea.Cmd {
	m.activeTagFilter = tagIDs
	return m.LoadItems()
}

// MarkSourceStale flags a source as having a sync error.
// The delegate shares this map by reference and renders a ⚠ badge.
func (m *Model) MarkSourceStale(source string) {
	m.staleSources[source] = true
}

// ClearSourceStale removes the stale flag for a source after a successful sync.
func (m *Model) ClearSourceStale(source string) {
	delete(m.staleSources, source)
}

// GetStaleSources returns the set of sources currently marked stale.
func (m Model) GetStaleSources() map[string]bool {
	return m.staleSources
}

// SetDateFilter sets the date filter by name (today/upcoming/overdue/"").
func (m *Model) SetDateFilter(mode string) tea.Cmd {
	for i, df := range dateFilterModes {
		if df == mode {
			m.dateFilterIndex = i
			break
		}
	}
	m.applyDateFilter()
	return m.LoadItems()
}

// SetSourceFilter sets the source filter by name (all/local/jira/bitbucket/email).
func (m *Model) SetSourceFilter(mode string) tea.Cmd {
	for i, sf := range sourceFilterModes {
		if sf == mode {
			m.sourceFilterIndex = i
			break
		}
	}
	m.applySourceFilter()
	return m.LoadItems()
}

// ClearFilters clears all active filters.
func (m *Model) ClearFilters() tea.Cmd {
	m.activeProjectFilter = nil
	m.activeTagFilter = nil
	m.sourceFilterIndex = 0
	m.dateFilterIndex = 0
	m.taskFilter.SourceType = nil
	m.taskFilter.Query = nil
	m.todoFilter.Query = nil
	m.todoFilter.DueDate = nil
	return m.LoadItems()
}

// LoadItems returns a tea.Cmd that loads both todos and tasks from the store.
func (m Model) LoadItems() tea.Cmd {
	taskFilter := m.taskFilter
	if taskFilter.Limit == 0 {
		taskFilter.Limit = defaultPageSize
	}
	taskFilter.Offset = 0

	todoFilter := m.todoFilter
	if todoFilter.Limit == 0 {
		todoFilter.Limit = defaultPageSize
	}
	todoFilter.Offset = 0

	// Apply project and tag filters to todo filter.
	todoFilter.ProjectID = m.activeProjectFilter
	todoFilter.TagIDs = m.activeTagFilter

	srcMode := m.activeSourceFilter()
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()

		var items []model.ListItem

		// Load local todos (skip when filtering to a specific external source)
		if srcMode == "all" || srcMode == "local" {
			todos, err := s.GetTodos(ctx, todoFilter)
			if err == nil {
				for _, todo := range todos {
					items = append(items, todo)
				}
			}
		}

		// Load external tasks (skip when filtering to local only)
		if srcMode != "local" {
			tasks, err := s.GetTasks(ctx, taskFilter)
			if err == nil {
				for _, task := range tasks {
					items = append(items, task)
				}
			}
		}

		// Sort the merged list
		sort.Slice(items, func(i, j int) bool {
			return items[i].GetUpdatedAt().After(items[j].GetUpdatedAt())
		})

		return ItemsLoadedMsg{Items: items}
	}
}

// LoadTasks returns a tea.Cmd that loads items. Kept for backward compatibility
// with the sync layer which dispatches LoadTasks() after poll results.
func (m Model) LoadTasks() tea.Cmd {
	return m.LoadItems()
}

// loadMoreItems returns a tea.Cmd that loads the next page.
func (m Model) loadMoreItems() tea.Cmd {
	taskFilter := m.taskFilter
	if taskFilter.Limit == 0 {
		taskFilter.Limit = defaultPageSize
	}
	taskFilter.Offset = m.currentOffset

	todoFilter := m.todoFilter
	if todoFilter.Limit == 0 {
		todoFilter.Limit = defaultPageSize
	}
	todoFilter.Offset = m.currentOffset
	todoFilter.ProjectID = m.activeProjectFilter
	todoFilter.TagIDs = m.activeTagFilter

	srcMode := m.activeSourceFilter()
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()

		var items []model.ListItem

		if srcMode == "all" || srcMode == "local" {
			todos, err := s.GetTodos(ctx, todoFilter)
			if err == nil {
				for _, todo := range todos {
					items = append(items, todo)
				}
			}
		}

		if srcMode != "local" {
			tasks, err := s.GetTasks(ctx, taskFilter)
			if err == nil {
				for _, task := range tasks {
					items = append(items, task)
				}
			}
		}

		sort.Slice(items, func(i, j int) bool {
			return items[i].GetUpdatedAt().After(items[j].GetUpdatedAt())
		})

		return ItemsLoadedMsg{Items: items, Append: true}
	}
}

// FilterSummary returns a string describing all active filters for the status bar.
func (m Model) FilterSummary() string {
	var parts []string

	if src := m.activeSourceFilter(); src != "all" {
		parts = append(parts, src)
	}
	if df := m.activeDateFilter(); df != "" {
		parts = append(parts, df)
	}
	if m.taskFilter.Query != nil {
		parts = append(parts, "\""+*m.taskFilter.Query+"\"")
	}
	if m.activeProjectFilter != nil {
		parts = append(parts, "project")
	}
	if len(m.activeTagFilter) > 0 {
		parts = append(parts, "tags")
	}
	if !m.showCompleted {
		parts = append(parts, "hide-done")
	}

	if len(parts) == 0 {
		return ""
	}
	result := "Filters: "
	for i, p := range parts {
		if i > 0 {
			result += " | "
		}
		result += p
	}
	return result
}

// SelectedItem returns the currently selected ListItem, if any.
func (m Model) SelectedItem() (model.ListItem, bool) {
	item, ok := m.list.SelectedItem().(ListItemWrapper)
	if !ok {
		return nil, false
	}
	return item.Item, true
}

// SetSize updates the list dimensions.
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.list.SetSize(width, height-2)
	m.searchInput.Width = width - 4
}
