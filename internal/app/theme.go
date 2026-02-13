package app

import (
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/theme"
)

// Re-export theme styles so existing code that imports from app still works.
// New code should import from the theme package directly.
var (
	HeaderStyle       = theme.HeaderStyle
	StatusBarStyle    = theme.StatusBarStyle
	DetailPanelStyle  = theme.DetailPanelStyle
	ListItemStyle     = theme.ListItemStyle
	SelectedItemStyle = theme.SelectedItemStyle
	HelpStyle         = theme.HelpStyle
	BorderStyle       = theme.BorderStyle
	DimmedStyle       = theme.DimmedStyle
	OverdueStyle      = theme.OverdueStyle
	LocalBadgeStyle   = theme.LocalBadgeStyle
	DueDateStyle      = theme.DueDateStyle
)

// StatusStyle delegates to theme.StatusStyle.
func StatusStyle(status string) lipgloss.Style {
	return theme.StatusStyle(status)
}

// PriorityStyle delegates to theme.PriorityStyle.
func PriorityStyle(priority int) lipgloss.Style {
	return theme.PriorityStyle(priority)
}

// SourceLabelStyle delegates to theme.SourceLabelStyle.
func SourceLabelStyle(sourceType string) lipgloss.Style {
	return theme.SourceLabelStyle(sourceType)
}
