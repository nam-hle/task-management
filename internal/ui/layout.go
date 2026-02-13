package ui

import (
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/theme"
)

// Layout manages the multi-panel terminal layout dimensions.
type Layout struct {
	Width           int
	Height          int
	HeaderHeight    int
	StatusBarHeight int
}

// NewLayout creates a Layout with the given terminal dimensions.
// HeaderHeight and StatusBarHeight default to 1.
func NewLayout(width, height int) Layout {
	return Layout{
		Width:           width,
		Height:          height,
		HeaderHeight:    1,
		StatusBarHeight: 1,
	}
}

// ContentWidth returns the full available width.
func (l Layout) ContentWidth() int {
	return l.Width
}

// ContentHeight returns the height available for the main content area,
// accounting for the header and status bar.
func (l Layout) ContentHeight() int {
	return l.Height - l.HeaderHeight - l.StatusBarHeight
}

// RenderHeader renders the top header bar with a title and sync status.
func (l Layout) RenderHeader(title string, syncStatus string) string {
	titleRendered := theme.HeaderStyle.Render(title)

	statusRendered := theme.HeaderStyle.
		Align(lipgloss.Right).
		Render(syncStatus)

	gap := l.Width -
		lipgloss.Width(titleRendered) -
		lipgloss.Width(statusRendered)
	if gap < 0 {
		gap = 0
	}

	filler := theme.HeaderStyle.Render(
		lipgloss.NewStyle().
			Width(gap).
			Background(theme.HeaderStyle.GetBackground()).
			Render(""),
	)

	return lipgloss.JoinHorizontal(
		lipgloss.Top,
		titleRendered,
		filler,
		statusRendered,
	)
}

// RenderStatusBar renders the bottom status bar with keyboard hints.
func (l Layout) RenderStatusBar(hints string) string {
	rendered := theme.StatusBarStyle.Render(hints)

	gap := l.Width - lipgloss.Width(rendered)
	if gap < 0 {
		gap = 0
	}

	filler := theme.StatusBarStyle.Render(
		lipgloss.NewStyle().
			Width(gap).
			Background(theme.StatusBarStyle.GetBackground()).
			Render(""),
	)

	return lipgloss.JoinHorizontal(lipgloss.Top, rendered, filler)
}

// RenderWithFrame composes a full terminal view by vertically joining
// the header, content area, and status bar.
func (l Layout) RenderWithFrame(
	header string,
	content string,
	statusBar string,
) string {
	return lipgloss.JoinVertical(
		lipgloss.Left,
		header,
		content,
		statusBar,
	)
}
