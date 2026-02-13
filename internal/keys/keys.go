package keys

import "github.com/charmbracelet/bubbles/key"

// KeyMap defines the global keybindings for the application.
type KeyMap struct {
	// Navigation
	Down key.Binding
	Up   key.Binding

	// Selection
	Select key.Binding

	// Back / Quit
	Back key.Binding
	Quit key.Binding

	// Search
	Search key.Binding

	// Command palette
	Command key.Binding

	// Help toggle
	Help key.Binding

	// Manual refresh
	Refresh key.Binding

	// Source filters
	FilterJira      key.Binding
	FilterBitbucket key.Binding
	FilterEmail     key.Binding

	// AI panel
	AI key.Binding

	// Actions
	Comment    key.Binding
	Transition key.Binding
	Approve    key.Binding

	// Sort
	CycleSort key.Binding
}

// DefaultKeyMap returns the default set of keybindings.
func DefaultKeyMap() *KeyMap {
	return &KeyMap{
		Down: key.NewBinding(
			key.WithKeys("j", "down"),
			key.WithHelp("j/↓", "down"),
		),
		Up: key.NewBinding(
			key.WithKeys("k", "up"),
			key.WithHelp("k/↑", "up"),
		),
		Select: key.NewBinding(
			key.WithKeys("enter"),
			key.WithHelp("enter", "open detail"),
		),
		Back: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("esc", "back"),
		),
		Quit: key.NewBinding(
			key.WithKeys("q"),
			key.WithHelp("q", "quit"),
		),
		Search: key.NewBinding(
			key.WithKeys("/"),
			key.WithHelp("/", "search"),
		),
		Command: key.NewBinding(
			key.WithKeys(":"),
			key.WithHelp(":", "command palette"),
		),
		Help: key.NewBinding(
			key.WithKeys("?"),
			key.WithHelp("?", "toggle help"),
		),
		Refresh: key.NewBinding(
			key.WithKeys("r"),
			key.WithHelp("r", "refresh"),
		),
		FilterJira: key.NewBinding(
			key.WithKeys("1"),
			key.WithHelp("1", "toggle jira"),
		),
		FilterBitbucket: key.NewBinding(
			key.WithKeys("2"),
			key.WithHelp("2", "toggle bitbucket"),
		),
		FilterEmail: key.NewBinding(
			key.WithKeys("3"),
			key.WithHelp("3", "toggle email"),
		),
		AI: key.NewBinding(
			key.WithKeys("a"),
			key.WithHelp("a", "AI panel"),
		),
		Comment: key.NewBinding(
			key.WithKeys("c"),
			key.WithHelp("c", "comment"),
		),
		Transition: key.NewBinding(
			key.WithKeys("t"),
			key.WithHelp("t", "transition"),
		),
		Approve: key.NewBinding(
			key.WithKeys("p"),
			key.WithHelp("p", "approve"),
		),
		CycleSort: key.NewBinding(
			key.WithKeys("tab"),
			key.WithHelp("tab", "cycle sort"),
		),
	}
}

// ShortHelp returns the most essential keybindings for the compact help view.
func (k *KeyMap) ShortHelp() []key.Binding {
	return []key.Binding{
		k.Up, k.Down, k.Select, k.Back,
		k.Quit, k.Help, k.Search,
	}
}

// FullHelp returns all keybindings grouped by category for the expanded
// help view.
func (k *KeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.Select, k.Back, k.Quit},
		{k.Search, k.Command, k.Help, k.Refresh},
		{k.FilterJira, k.FilterBitbucket, k.FilterEmail, k.CycleSort},
		{k.Comment, k.Transition, k.Approve, k.AI},
	}
}
