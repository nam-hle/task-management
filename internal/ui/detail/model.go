package detail

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/keys"
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

// Model is the task detail view component.
type Model struct {
	task     *source.ItemDetail
	viewport viewport.Model
	store    store.Store
	keys     *keys.KeyMap
	width    int
	height   int
	loading  bool
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
		m.viewport.SetContent(m.renderContent())
		m.viewport.GotoTop()
		return m, nil

	case tea.KeyMsg:
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
	}

	// Delegate to viewport for scrolling (j/k, up/down, pgup/pgdn)
	var cmd tea.Cmd
	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
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

// SetTask updates the task being displayed and re-renders the content.
func (m *Model) SetTask(detail *source.ItemDetail) {
	m.task = detail
	m.loading = false
	m.viewport.SetContent(m.renderContent())
	m.viewport.GotoTop()
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
