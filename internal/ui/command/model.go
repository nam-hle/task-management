package command

import (
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/theme"
)

// CommandMsg is emitted when the user executes a command.
type CommandMsg string

// Model is the command palette view.
type Model struct {
	input  textinput.Model
	width  int
	height int
}

// New creates a new command palette model.
func New(width, height int) Model {
	ti := textinput.New()
	ti.Placeholder = "type a command..."
	ti.Prompt = ": "
	ti.Focus()
	ti.Width = width - 6

	return Model{
		input:  ti,
		width:  width,
		height: height,
	}
}

// Init returns the initial command.
func (m Model) Init() tea.Cmd {
	return textinput.Blink
}

// Update handles messages for the command palette.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "enter":
			cmd := strings.TrimSpace(m.input.Value())
			m.input.Reset()
			if cmd != "" {
				return m, func() tea.Msg {
					return CommandMsg(cmd)
				}
			}
			return m, nil
		}
	}

	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

// View renders the command palette.
func (m Model) View() string {
	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(theme.ColorWhite).
		MarginBottom(1)

	title := titleStyle.Render("Command Palette")
	input := m.input.View()

	content := lipgloss.JoinVertical(lipgloss.Left, title, input)

	return theme.DetailPanelStyle.
		Width(m.width - 4).
		Render(content)
}

// SetSize updates the command palette dimensions.
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.input.Width = width - 6
}

// Focus gives keyboard focus to the text input.
func (m *Model) Focus() tea.Cmd {
	return m.input.Focus()
}
