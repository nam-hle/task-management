package ai

import (
	"context"
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	aiservice "github.com/nhle/task-management/internal/ai"
	"github.com/nhle/task-management/internal/keys"
	"github.com/nhle/task-management/internal/theme"
)

// AIPanelCloseMsg signals the parent to close the AI panel.
type AIPanelCloseMsg struct{}

// AIResponseChunkMsg carries a streaming response chunk from the assistant.
type AIResponseChunkMsg struct {
	Text string
	Done bool
}

// AINavigateTaskMsg signals the parent to navigate to a specific task.
type AINavigateTaskMsg struct {
	TaskID string
}

// displayMessage represents a message rendered in the conversation viewport.
type displayMessage struct {
	Role    string
	Content string
}

// Model is the AI panel Bubble Tea model that provides a chat interface
// to the AI assistant.
type Model struct {
	assistant *aiservice.Assistant
	input     textarea.Model
	viewport  viewport.Model
	messages  []displayMessage
	streaming bool
	keys      *keys.KeyMap
	width     int
	height    int
	noAPIKey  bool
}

// New creates a new AI panel model. If assistant is nil (no API key),
// the panel displays a configuration prompt instead.
func New(
	assistant *aiservice.Assistant,
	k *keys.KeyMap,
	width, height int,
) Model {
	ta := textarea.New()
	ta.Placeholder = "Ask about your tasks..."
	ta.Prompt = "> "
	ta.ShowLineNumbers = false
	ta.SetWidth(width - 4)
	ta.SetHeight(3)
	ta.CharLimit = 2000
	ta.Focus()

	vpHeight := height - 8 // space for input area + borders
	if vpHeight < 4 {
		vpHeight = 4
	}

	vp := viewport.New(width-4, vpHeight)
	vp.Style = lipgloss.NewStyle()

	return Model{
		assistant: assistant,
		input:     ta,
		viewport:  vp,
		messages:  make([]displayMessage, 0),
		keys:      k,
		width:     width,
		height:    height,
		noAPIKey:  assistant == nil,
	}
}

// Init returns the initial command for the AI panel.
func (m Model) Init() tea.Cmd {
	return textarea.Blink
}

// Update handles messages for the AI panel.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case AIResponseChunkMsg:
		return m.handleResponseChunk(msg)

	case tea.KeyMsg:
		return m.handleKeyMsg(msg)
	}

	// Delegate to textarea and viewport
	var cmds []tea.Cmd

	var taCmd tea.Cmd
	m.input, taCmd = m.input.Update(msg)
	if taCmd != nil {
		cmds = append(cmds, taCmd)
	}

	var vpCmd tea.Cmd
	m.viewport, vpCmd = m.viewport.Update(msg)
	if vpCmd != nil {
		cmds = append(cmds, vpCmd)
	}

	return m, tea.Batch(cmds...)
}

// handleKeyMsg processes keyboard input for the AI panel.
func (m Model) handleKeyMsg(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		if m.streaming {
			return m, nil
		}
		return m, func() tea.Msg {
			return AIPanelCloseMsg{}
		}

	case "enter":
		if m.noAPIKey || m.streaming {
			return m, nil
		}

		text := strings.TrimSpace(m.input.Value())
		if text == "" {
			return m, nil
		}

		m.input.Reset()
		m.messages = append(m.messages, displayMessage{
			Role:    "You",
			Content: text,
		})
		m.streaming = true
		m.refreshViewport()

		return m, m.sendMessage(text)
	}

	// Let textarea handle other keys
	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

// handleResponseChunk processes an incoming AI response chunk.
func (m Model) handleResponseChunk(msg AIResponseChunkMsg) (Model, tea.Cmd) {
	if msg.Done {
		m.streaming = false

		// Append or finalize the assistant message
		if len(m.messages) > 0 &&
			m.messages[len(m.messages)-1].Role == "Assistant" {
			// Already has content from previous chunk; just mark done
		} else if msg.Text != "" {
			m.messages = append(m.messages, displayMessage{
				Role:    "Assistant",
				Content: msg.Text,
			})
		}

		// If the last message already exists, append remaining text
		if msg.Text != "" && len(m.messages) > 0 &&
			m.messages[len(m.messages)-1].Role == "Assistant" {
			last := &m.messages[len(m.messages)-1]
			if !strings.HasSuffix(last.Content, msg.Text) {
				last.Content += msg.Text
			}
		}

		m.refreshViewport()
		return m, nil
	}

	// Append text to the current assistant message
	if len(m.messages) > 0 &&
		m.messages[len(m.messages)-1].Role == "Assistant" {
		m.messages[len(m.messages)-1].Content += msg.Text
	} else {
		m.messages = append(m.messages, displayMessage{
			Role:    "Assistant",
			Content: msg.Text,
		})
	}

	m.refreshViewport()
	return m, nil
}

// sendMessage returns a command that sends the user's message to the
// assistant and streams back the response.
func (m Model) sendMessage(text string) tea.Cmd {
	assistant := m.assistant
	return func() tea.Msg {
		ch, err := assistant.SendMessage(context.Background(), text)
		if err != nil {
			return AIResponseChunkMsg{
				Text: fmt.Sprintf("Error: %v", err),
				Done: true,
			}
		}

		// Read the first chunk to get things started
		chunk, ok := <-ch
		if !ok {
			return AIResponseChunkMsg{Text: "", Done: true}
		}
		return AIResponseChunkMsg{
			Text: chunk.Text,
			Done: chunk.Done,
		}
	}
}

// waitForNextChunk returns a command that waits for the next chunk from
// the streaming channel.
func waitForNextChunk(
	ch <-chan aiservice.StreamChunk,
) tea.Cmd {
	return func() tea.Msg {
		chunk, ok := <-ch
		if !ok {
			return AIResponseChunkMsg{Text: "", Done: true}
		}
		return AIResponseChunkMsg{
			Text: chunk.Text,
			Done: chunk.Done,
		}
	}
}

// refreshViewport re-renders the conversation content and scrolls to bottom.
func (m *Model) refreshViewport() {
	m.viewport.SetContent(m.renderConversation())
	m.viewport.GotoBottom()
}

// renderConversation builds the conversation display string.
func (m Model) renderConversation() string {
	if len(m.messages) == 0 && !m.noAPIKey {
		return lipgloss.NewStyle().
			Foreground(theme.ColorGray).
			Italic(true).
			Render("Ask me about your tasks. I can search, filter, " +
				"and summarize items from all your connected sources.")
	}

	var sections []string

	roleStyle := lipgloss.NewStyle().Bold(true)
	userStyle := roleStyle.Foreground(theme.ColorBlue)
	assistantStyle := roleStyle.Foreground(theme.ColorGreen)
	contentStyle := lipgloss.NewStyle().Foreground(theme.ColorWhite)

	for _, msg := range m.messages {
		var label string
		switch msg.Role {
		case "You":
			label = userStyle.Render("You:")
		case "Assistant":
			label = assistantStyle.Render("Assistant:")
		default:
			label = roleStyle.Render(msg.Role + ":")
		}

		sections = append(sections, label)
		sections = append(sections, contentStyle.Render(msg.Content))
		sections = append(sections, "")
	}

	if m.streaming {
		thinkingStyle := lipgloss.NewStyle().
			Foreground(theme.ColorGray).
			Italic(true)
		sections = append(sections, thinkingStyle.Render("..."))
	}

	return strings.Join(sections, "\n")
}

// View renders the AI panel.
func (m Model) View() string {
	if m.noAPIKey {
		return m.renderNoAPIKey()
	}

	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(theme.ColorWhite).
		MarginBottom(1)

	title := titleStyle.Render("AI Assistant")

	sepStyle := lipgloss.NewStyle().Foreground(theme.ColorSubtle)
	separator := sepStyle.Render(
		strings.Repeat("─", min(m.width-6, 80)),
	)

	content := lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		m.viewport.View(),
		separator,
		m.input.View(),
	)

	return theme.DetailPanelStyle.
		Width(m.width - 4).
		Render(content)
}

// renderNoAPIKey shows a message when the API key is not configured.
func (m Model) renderNoAPIKey() string {
	style := lipgloss.NewStyle().
		Width(m.width - 4).
		Align(lipgloss.Center, lipgloss.Center).
		Foreground(theme.ColorGray)

	msg := "AI Assistant requires an Anthropic API key.\n\n" +
		"To configure, store your API key in the system keyring:\n" +
		"  Key name: claude-api-key\n\n" +
		"Or set the ANTHROPIC_API_KEY environment variable.\n\n" +
		"Press Esc to go back."

	return theme.DetailPanelStyle.
		Width(m.width - 4).
		Height(m.height - 4).
		Render(style.Render(msg))
}

// SetSize updates the AI panel dimensions.
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.input.SetWidth(width - 4)

	vpHeight := height - 8
	if vpHeight < 4 {
		vpHeight = 4
	}
	m.viewport.Width = width - 4
	m.viewport.Height = vpHeight
}

// Focus gives keyboard focus to the text input.
func (m *Model) Focus() tea.Cmd {
	return m.input.Focus()
}

// Reset clears the conversation and resets the assistant context.
func (m *Model) Reset() {
	m.messages = m.messages[:0]
	m.streaming = false
	m.input.Reset()
	m.refreshViewport()
	if m.assistant != nil {
		m.assistant.Reset()
	}
}
