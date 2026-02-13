package tasklist

import (
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/theme"
)

// StalenessThreshold defines how old FetchedAt can be before
// a task is considered stale. Defaults to 5 minutes.
var StalenessThreshold = 5 * time.Minute

// TaskItem wraps a model.Task so it can be used in a bubbles/list.
type TaskItem struct {
	Task model.Task
}

// FilterValue returns the string used for fuzzy filtering.
func (i TaskItem) FilterValue() string {
	return i.Task.Title
}

// Title returns the task title for the list.
func (i TaskItem) Title() string {
	return i.Task.Title
}

// Description returns a short summary line for the list.
func (i TaskItem) Description() string {
	parts := []string{
		string(i.Task.SourceType),
		i.Task.Status,
		relativeTime(i.Task.UpdatedAt),
	}
	return strings.Join(parts, " | ")
}

// TaskDelegate implements list.ItemDelegate for rendering task items.
type TaskDelegate struct{}

// Height returns the number of lines each item takes.
func (d TaskDelegate) Height() int { return 1 }

// Spacing returns the number of blank lines between items.
func (d TaskDelegate) Spacing() int { return 0 }

// Update handles per-item messages (unused for now).
func (d TaskDelegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd {
	return nil
}

// Render draws a single task item line.
func (d TaskDelegate) Render(w io.Writer, m list.Model, index int, item list.Item) {
	taskItem, ok := item.(TaskItem)
	if !ok {
		return
	}

	task := taskItem.Task

	isSelected := index == m.Index()

	// Source badge
	srcStyle := theme.SourceLabelStyle(string(task.SourceType))
	srcBadge := srcStyle.Render(strings.ToUpper(string(task.SourceType))[:3])

	// Status badge
	statusStyle := theme.StatusStyle(task.Status)
	statusBadge := statusStyle.Render(task.Status)

	// Priority indicator
	priStyle := theme.PriorityStyle(task.Priority)
	priLabel := priorityLabel(task.Priority)
	priBadge := priStyle.Render(priLabel)

	// Title
	title := task.Title

	// Staleness indicator
	staleIndicator := ""
	if time.Since(task.FetchedAt) > StalenessThreshold {
		staleIndicator = lipgloss.NewStyle().
			Foreground(theme.ColorGray).
			Render(" ●")
	}

	// Time
	timeStr := lipgloss.NewStyle().
		Foreground(theme.ColorGray).
		Render(relativeTime(task.UpdatedAt))

	line := fmt.Sprintf(
		"%s %s %s %s%s  %s",
		srcBadge, statusBadge, priBadge, title, staleIndicator, timeStr,
	)

	if isSelected {
		line = theme.SelectedItemStyle.Render(line)
	} else {
		line = theme.ListItemStyle.Render(line)
	}

	fmt.Fprint(w, line)
}

// relativeTime returns a human-friendly relative time string.
func relativeTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}

	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		mins := int(d.Minutes())
		if mins == 1 {
			return "1m ago"
		}
		return fmt.Sprintf("%dm ago", mins)
	case d < 24*time.Hour:
		hrs := int(d.Hours())
		if hrs == 1 {
			return "1h ago"
		}
		return fmt.Sprintf("%dh ago", hrs)
	case d < 7*24*time.Hour:
		days := int(d.Hours() / 24)
		if days == 1 {
			return "1d ago"
		}
		return fmt.Sprintf("%dd ago", days)
	default:
		weeks := int(d.Hours() / 24 / 7)
		if weeks == 1 {
			return "1w ago"
		}
		return fmt.Sprintf("%dw ago", weeks)
	}
}

// priorityLabel returns a short label for the given priority level.
func priorityLabel(p int) string {
	switch p {
	case model.PriorityCritical:
		return "P1"
	case model.PriorityHigh:
		return "P2"
	case model.PriorityMedium:
		return "P3"
	case model.PriorityLow:
		return "P4"
	case model.PriorityLowest:
		return "P5"
	default:
		return "P?"
	}
}
