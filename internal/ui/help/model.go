package help

import (
	"github.com/charmbracelet/bubbles/help"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/keys"
	"github.com/nhle/task-management/internal/theme"
)

// Model is the help overlay view.
type Model struct {
	keys   *keys.KeyMap
	help   help.Model
	width  int
	height int
}

// New creates a new help view model.
func New(keys *keys.KeyMap, width, height int) Model {
	h := help.New()
	h.Width = width
	return Model{
		keys:   keys,
		help:   h,
		width:  width,
		height: height,
	}
}

// Init returns the initial command.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles messages for the help view.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	return m, nil
}

// View renders the help overlay.
func (m Model) View() string {
	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(theme.ColorWhite).
		MarginBottom(1)

	title := titleStyle.Render("Keyboard Shortcuts")

	m.help.Width = m.width - 4
	m.help.ShowAll = true
	helpText := m.help.View(m.keys)

	content := lipgloss.JoinVertical(lipgloss.Left, title, helpText)

	return theme.DetailPanelStyle.
		Width(m.width - 4).
		Height(m.height - 4).
		Render(content)
}

// SetSize updates the help view dimensions.
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.help.Width = width - 4
}
