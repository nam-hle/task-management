package detail

import (
	"context"
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/keys"
	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source"
	"github.com/nhle/task-management/internal/store"
	"github.com/nhle/task-management/internal/theme"
)

// BackMsg signals the parent to navigate back to the list view.
type BackMsg struct{}

// DetailLoadedMsg carries the loaded item detail.
type DetailLoadedMsg struct {
	Detail *source.ItemDetail
}

// ActionMsg signals the parent to execute an action on the current task.
type ActionMsg struct {
	Action string
	TaskID string
}

// LinksLoadedMsg carries loaded links for the current item.
type LinksLoadedMsg struct {
	Links []model.Link
}

// LinkPickerOpenMsg carries available tasks for the link picker.
type LinkPickerOpenMsg struct {
	Tasks []model.Task
}

// LinkRequestMsg signals the app to open the link picker.
type LinkRequestMsg struct {
	TodoID string
}

// UnlinkRequestMsg signals the app to delete a link.
type UnlinkRequestMsg struct {
	LinkID string
}

// LinkCreatedResultMsg is sent after a link is created.
type LinkCreatedResultMsg struct {
	Err error
}

// LinkDeletedResultMsg is sent after a link is deleted.
type LinkDeletedResultMsg struct {
	Err error
}

// NavigateToLinkedItemMsg signals the app to navigate to a linked item.
type NavigateToLinkedItemMsg struct {
	ItemID  string
	IsLocal bool
}

// Model is the task detail view component.
type Model struct {
	task     *source.ItemDetail
	viewport viewport.Model
	store    store.Store
	keys     *keys.KeyMap
	width    int
	height   int
	loading  bool

	// Link management
	links       []model.Link
	isLocalTodo bool

	// Link picker state
	pickerMode   bool
	pickerTasks  []model.Task
	pickerCursor int
}

// New creates a new detail view model.
func New(s store.Store, keys *keys.KeyMap, width, height int) Model {
	vp := viewport.New(width, height-2)
	vp.Style = lipgloss.NewStyle()

	return Model{
		viewport: vp,
		store:    s,
		keys:     keys,
		width:    width,
		height:   height,
	}
}

// Init returns the initial command for the detail view.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles messages for the detail view.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case DetailLoadedMsg:
		m.task = msg.Detail
		m.loading = false
		m.links = nil
		m.isLocalTodo = false
		m.pickerMode = false
		m.viewport.SetContent(m.renderContent())
		m.viewport.GotoTop()
		return m, nil

	case LinksLoadedMsg:
		m.links = msg.Links
		m.viewport.SetContent(m.renderContent())
		return m, nil

	case LinkPickerOpenMsg:
		m.pickerMode = true
		m.pickerTasks = msg.Tasks
		m.pickerCursor = 0
		m.viewport.SetContent(m.renderContent())
		m.viewport.GotoTop()
		return m, nil

	case LinkCreatedResultMsg:
		m.pickerMode = false
		m.pickerTasks = nil
		return m, nil

	case LinkDeletedResultMsg:
		return m, nil

	case tea.KeyMsg:
		if m.pickerMode {
			return m.handlePickerKeys(msg)
		}
		return m.handleNormalKeys(msg)
	}

	// Delegate to viewport for scrolling (j/k, up/down, pgup/pgdn)
	var cmd tea.Cmd
	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

// handleNormalKeys processes keys in the normal detail view.
func (m Model) handleNormalKeys(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Back):
		return m, func() tea.Msg {
			return BackMsg{}
		}

	case key.Matches(msg, m.keys.Comment):
		if m.task != nil {
			return m, func() tea.Msg {
				return ActionMsg{
					Action: "comment",
					TaskID: m.task.ID,
				}
			}
		}

	case key.Matches(msg, m.keys.Transition):
		if m.task != nil {
			return m, func() tea.Msg {
				return ActionMsg{
					Action: "transition",
					TaskID: m.task.ID,
				}
			}
		}

	case key.Matches(msg, m.keys.Approve):
		if m.task != nil {
			return m, func() tea.Msg {
				return ActionMsg{
					Action: "approve",
					TaskID: m.task.ID,
				}
			}
		}
	}

	// Link management keys
	switch msg.String() {
	case "l":
		// Link: only for local todos
		if m.task != nil && m.isLocalTodo {
			todoID := m.task.ID
			return m, func() tea.Msg {
				return LinkRequestMsg{TodoID: todoID}
			}
		}

	case "u":
		// Unlink: remove the last link if any exist
		if len(m.links) > 0 {
			linkID := m.links[len(m.links)-1].ID
			return m, func() tea.Msg {
				return UnlinkRequestMsg{LinkID: linkID}
			}
		}

	case "enter":
		// Navigate to a linked item (first link)
		if len(m.links) > 0 {
			link := m.links[0]
			if m.isLocalTodo {
				// We're viewing a todo, navigate to the linked task
				return m, func() tea.Msg {
					return NavigateToLinkedItemMsg{
						ItemID:  link.TaskID,
						IsLocal: false,
					}
				}
			}
			// We're viewing a task, navigate to the linked todo
			return m, func() tea.Msg {
				return NavigateToLinkedItemMsg{
					ItemID:  link.TodoID,
					IsLocal: true,
				}
			}
		}
	}

	// Delegate to viewport for scrolling
	var cmd tea.Cmd
	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

// handlePickerKeys processes keys in the link picker mode.
func (m Model) handlePickerKeys(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.pickerMode = false
		m.pickerTasks = nil
		m.viewport.SetContent(m.renderContent())
		return m, nil

	case "j", "down":
		if m.pickerCursor < len(m.pickerTasks)-1 {
			m.pickerCursor++
			m.viewport.SetContent(m.renderContent())
		}
		return m, nil

	case "k", "up":
		if m.pickerCursor > 0 {
			m.pickerCursor--
			m.viewport.SetContent(m.renderContent())
		}
		return m, nil

	case "enter":
		if len(m.pickerTasks) > 0 && m.pickerCursor < len(m.pickerTasks) {
			selectedTask := m.pickerTasks[m.pickerCursor]
			todoID := m.task.ID
			taskID := selectedTask.ID
			s := m.store
			return m, func() tea.Msg {
				link := model.Link{
					TodoID:   todoID,
					TaskID:   taskID,
					LinkType: model.LinkTypeManual,
				}
				err := s.CreateLink(context.Background(), link)
				return LinkCreatedResultMsg{Err: err}
			}
		}
		return m, nil
	}

	return m, nil
}

// View renders the detail view.
func (m Model) View() string {
	if m.loading {
		loadingStyle := lipgloss.NewStyle().
			Width(m.width).
			Height(m.height).
			Align(lipgloss.Center, lipgloss.Center).
			Foreground(theme.ColorGray)
		return loadingStyle.Render("Loading task details...")
	}

	if m.task == nil {
		emptyStyle := lipgloss.NewStyle().
			Width(m.width).
			Height(m.height).
			Align(lipgloss.Center, lipgloss.Center).
			Foreground(theme.ColorGray)
		return emptyStyle.Render("No task selected")
	}

	return m.viewport.View()
}

// renderContent builds the full detail content string for the viewport.
func (m Model) renderContent() string {
	if m.task == nil {
		return ""
	}

	// If in picker mode, render the picker
	if m.pickerMode {
		return m.renderLinkPicker()
	}

	task := m.task
	var sections []string

	// Title
	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(theme.ColorWhite)
	sections = append(sections, titleStyle.Render(task.Title))

	// Badges line: source + status + priority
	srcBadge := theme.SourceLabelStyle(
		string(task.SourceType),
	).Render(strings.ToUpper(string(task.SourceType)))

	statusBadge := theme.StatusStyle(task.Status).Render(task.Status)

	priBadge := theme.PriorityStyle(task.Priority).Render(
		priorityName(task.Priority),
	)

	badgeLine := lipgloss.JoinHorizontal(
		lipgloss.Top, srcBadge, "  ", statusBadge, "  ", priBadge,
	)
	sections = append(sections, badgeLine)
	sections = append(sections, "")

	// Metadata table
	metaStyle := lipgloss.NewStyle().Foreground(theme.ColorGray)
	valStyle := lipgloss.NewStyle().Foreground(theme.ColorWhite)

	if task.Assignee != "" {
		sections = append(sections, fmt.Sprintf(
			"%s  %s",
			metaStyle.Render("Assignee:"),
			valStyle.Render(task.Assignee),
		))
	}
	if task.Author != "" {
		sections = append(sections, fmt.Sprintf(
			"%s    %s",
			metaStyle.Render("Author:"),
			valStyle.Render(task.Author),
		))
	}
	if !task.CreatedAt.IsZero() {
		sections = append(sections, fmt.Sprintf(
			"%s   %s",
			metaStyle.Render("Created:"),
			valStyle.Render(task.CreatedAt.Format("2006-01-02 15:04")),
		))
	}
	if !task.UpdatedAt.IsZero() {
		sections = append(sections, fmt.Sprintf(
			"%s   %s",
			metaStyle.Render("Updated:"),
			valStyle.Render(task.UpdatedAt.Format("2006-01-02 15:04")),
		))
	}
	if task.SourceURL != "" {
		sections = append(sections, fmt.Sprintf(
			"%s       %s",
			metaStyle.Render("URL:"),
			valStyle.Render(task.SourceURL),
		))
	}

	// Extra metadata from source
	if len(task.Metadata) > 0 {
		for k, v := range task.Metadata {
			sections = append(sections, fmt.Sprintf(
				"%s  %s",
				metaStyle.Render(k+":"),
				valStyle.Render(v),
			))
		}
	}

	// Separator
	sepStyle := lipgloss.NewStyle().Foreground(theme.ColorSubtle)
	separator := sepStyle.Render(strings.Repeat("─", min(m.width-4, 80)))
	sections = append(sections, "")
	sections = append(sections, separator)
	sections = append(sections, "")

	// Description / body
	descHeaderStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(theme.ColorWhite).
		MarginBottom(1)

	sections = append(sections, descHeaderStyle.Render("Description"))

	body := task.RenderedBody
	if body == "" {
		body = task.Description
	}
	if body == "" {
		body = lipgloss.NewStyle().
			Foreground(theme.ColorGray).
			Italic(true).
			Render("No description")
	}
	sections = append(sections, body)

	// Links section
	if len(m.links) > 0 {
		sections = append(sections, "")
		sections = append(sections, separator)
		sections = append(sections, "")

		linkHeaderStyle := lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.ColorWhite)

		if m.isLocalTodo {
			sections = append(sections, linkHeaderStyle.Render(
				fmt.Sprintf("Linked Items (%d)", len(m.links)),
			))
		} else {
			sections = append(sections, linkHeaderStyle.Render(
				fmt.Sprintf("Linked Todos (%d)", len(m.links)),
			))
		}
		sections = append(sections, "")

		linkStyle := lipgloss.NewStyle().Foreground(theme.ColorBlue)
		typeStyle := lipgloss.NewStyle().Foreground(theme.ColorGray)

		for _, link := range m.links {
			title := link.TaskTitle
			if !m.isLocalTodo {
				title = link.TodoTitle
			}
			if title == "" {
				title = "(untitled)"
			}
			linkLine := fmt.Sprintf(
				"  %s  %s",
				linkStyle.Render(title),
				typeStyle.Render("["+link.LinkType+"]"),
			)
			sections = append(sections, linkLine)
		}

		if m.isLocalTodo {
			sections = append(sections, "")
			hintStyle := lipgloss.NewStyle().Foreground(theme.ColorGray).Italic(true)
			sections = append(sections, hintStyle.Render(
				"  l=link to task  u=unlink  enter=navigate",
			))
		}
	} else if m.isLocalTodo {
		sections = append(sections, "")
		sections = append(sections, separator)
		sections = append(sections, "")
		hintStyle := lipgloss.NewStyle().Foreground(theme.ColorGray).Italic(true)
		sections = append(sections, hintStyle.Render(
			"  No linked items. Press l to link to an external task.",
		))
	}

	// Comments section
	if len(task.Comments) > 0 {
		sections = append(sections, "")
		sections = append(sections, separator)
		sections = append(sections, "")

		commentHeaderStyle := lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.ColorWhite)

		sections = append(sections, commentHeaderStyle.Render(
			fmt.Sprintf("Comments (%d)", len(task.Comments)),
		))
		sections = append(sections, "")

		authorStyle := lipgloss.NewStyle().Bold(true).Foreground(theme.ColorBlue)
		timeStyle := lipgloss.NewStyle().Foreground(theme.ColorGray)

		for _, c := range task.Comments {
			header := fmt.Sprintf(
				"%s  %s",
				authorStyle.Render(c.Author),
				timeStyle.Render(c.CreatedAt),
			)
			sections = append(sections, header)
			sections = append(sections, c.Body)
			sections = append(sections, "")
		}
	}

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

// renderLinkPicker renders the task picker for linking.
func (m Model) renderLinkPicker() string {
	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(theme.ColorWhite)
	var sections []string

	sections = append(sections, titleStyle.Render("Link to External Task"))
	sections = append(sections, "")

	if len(m.pickerTasks) == 0 {
		emptyStyle := lipgloss.NewStyle().Foreground(theme.ColorGray).Italic(true)
		sections = append(sections, emptyStyle.Render(
			"No external tasks available to link.",
		))
		sections = append(sections, "")
		sections = append(sections, emptyStyle.Render("Press esc to go back."))
		return lipgloss.JoinVertical(lipgloss.Left, sections...)
	}

	hintStyle := lipgloss.NewStyle().Foreground(theme.ColorGray)
	sections = append(sections, hintStyle.Render(
		"j/k=navigate  enter=link  esc=cancel",
	))
	sections = append(sections, "")

	normalStyle := lipgloss.NewStyle().Foreground(theme.ColorWhite)
	selectedStyle := lipgloss.NewStyle().
		Foreground(theme.ColorWhite).
		Bold(true).
		Background(theme.ColorSubtle)
	srcStyle := lipgloss.NewStyle().Foreground(theme.ColorGray)

	for i, task := range m.pickerTasks {
		prefix := "  "
		style := normalStyle
		if i == m.pickerCursor {
			prefix = "> "
			style = selectedStyle
		}
		line := fmt.Sprintf(
			"%s%s  %s",
			prefix,
			style.Render(task.Title),
			srcStyle.Render("["+string(task.SourceType)+"]"),
		)
		sections = append(sections, line)
	}

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

// SetTask updates the task being displayed and re-renders the content.
func (m *Model) SetTask(detail *source.ItemDetail) {
	m.task = detail
	m.loading = false
	m.links = nil
	m.pickerMode = false
	m.viewport.SetContent(m.renderContent())
	m.viewport.GotoTop()
}

// SetLinks updates the links displayed in the detail view.
func (m *Model) SetLinks(links []model.Link) {
	m.links = links
	m.viewport.SetContent(m.renderContent())
}

// SetIsLocalTodo marks whether the current item is a local todo.
func (m *Model) SetIsLocalTodo(isLocal bool) {
	m.isLocalTodo = isLocal
}

// IsLocalTodo returns whether the current item is a local todo.
func (m Model) IsLocalTodo() bool {
	return m.isLocalTodo
}

// CurrentItemID returns the ID of the currently displayed item.
func (m Model) CurrentItemID() string {
	if m.task != nil {
		return m.task.ID
	}
	return ""
}

// SetLoading sets the loading state.
func (m *Model) SetLoading(loading bool) {
	m.loading = loading
}

// SetSize updates the detail view dimensions.
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.viewport.Width = width
	m.viewport.Height = height - 2
}

// priorityName returns a human-readable name for the priority level.
func priorityName(p int) string {
	switch p {
	case 1:
		return "Critical"
	case 2:
		return "High"
	case 3:
		return "Medium"
	case 4:
		return "Low"
	case 5:
		return "Lowest"
	default:
		return "Unknown"
	}
}
