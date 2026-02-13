package theme

import "github.com/charmbracelet/lipgloss"

// Adaptive color pairs (dark terminal value, light terminal value).
var (
	ColorBlue    = lipgloss.AdaptiveColor{Dark: "#5B9BD5", Light: "#2B6CB0"}
	ColorGreen   = lipgloss.AdaptiveColor{Dark: "#6BCB77", Light: "#2F855A"}
	ColorYellow  = lipgloss.AdaptiveColor{Dark: "#FFD93D", Light: "#B7791F"}
	ColorRed     = lipgloss.AdaptiveColor{Dark: "#FF6B6B", Light: "#C53030"}
	ColorOrange  = lipgloss.AdaptiveColor{Dark: "#FFA94D", Light: "#C05621"}
	ColorMagenta = lipgloss.AdaptiveColor{Dark: "#CC5DE8", Light: "#805AD5"}
	ColorGray    = lipgloss.AdaptiveColor{Dark: "#868E96", Light: "#718096"}
	ColorWhite   = lipgloss.AdaptiveColor{Dark: "#F8F9FA", Light: "#1A202C"}
	ColorSubtle  = lipgloss.AdaptiveColor{Dark: "#495057", Light: "#CBD5E0"}
	ColorBorder  = lipgloss.AdaptiveColor{Dark: "#495057", Light: "#E2E8F0"}
)

// HeaderStyle is used for top-level section headers and the application title.
var HeaderStyle = lipgloss.NewStyle().
	Bold(true).
	Foreground(ColorWhite).
	Background(ColorBlue).
	Padding(0, 1)

// StatusBarStyle is used for the bottom status bar.
var StatusBarStyle = lipgloss.NewStyle().
	Foreground(ColorWhite).
	Background(ColorSubtle).
	Padding(0, 1)

// DetailPanelStyle wraps the detail view content area.
var DetailPanelStyle = lipgloss.NewStyle().
	Padding(1, 2).
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorBorder)

// ListItemStyle is the base style for items in a list.
var ListItemStyle = lipgloss.NewStyle().
	PaddingLeft(2)

// SelectedItemStyle highlights the currently focused list item.
var SelectedItemStyle = lipgloss.NewStyle().
	PaddingLeft(1).
	Bold(true).
	Foreground(ColorBlue).
	Border(lipgloss.NormalBorder(), false, false, false, true).
	BorderForeground(ColorBlue)

// HelpStyle is used for keyboard shortcut hints and help text.
var HelpStyle = lipgloss.NewStyle().
	Foreground(ColorGray).
	Italic(true)

// BorderStyle provides a standard rounded border for panels.
var BorderStyle = lipgloss.NewStyle().
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorBorder)

// StatusStyle returns a color-coded style for the given normalized task status.
func StatusStyle(status string) lipgloss.Style {
	base := lipgloss.NewStyle().Bold(true).Padding(0, 1)

	switch status {
	case "open":
		return base.Foreground(ColorBlue)
	case "in_progress":
		return base.Foreground(ColorYellow)
	case "review":
		return base.Foreground(ColorMagenta)
	case "done":
		return base.Foreground(ColorGreen)
	default:
		return base.Foreground(ColorGray)
	}
}

// PriorityStyle returns a color-coded style for the given numeric priority.
func PriorityStyle(priority int) lipgloss.Style {
	base := lipgloss.NewStyle().Bold(true)

	switch priority {
	case 1: // Critical
		return base.Foreground(ColorRed)
	case 2: // High
		return base.Foreground(ColorOrange)
	case 3: // Medium
		return base.Foreground(ColorYellow)
	case 4: // Low
		return base.Foreground(ColorBlue)
	case 5: // Lowest
		return base.Foreground(ColorGray)
	default:
		return base.Foreground(ColorGray)
	}
}

// SourceLabelStyle returns a color-coded style for the given source type label.
func SourceLabelStyle(sourceType string) lipgloss.Style {
	base := lipgloss.NewStyle().Bold(true).Padding(0, 1)

	switch sourceType {
	case "jira":
		return base.Foreground(ColorBlue)
	case "bitbucket":
		return base.Foreground(ColorBlue)
	case "email":
		return base.Foreground(ColorGreen)
	default:
		return base.Foreground(ColorGray)
	}
}
