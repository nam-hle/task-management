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

// ListItemWrapper wraps a model.ListItem so it can be used in a bubbles/list.
type ListItemWrapper struct {
	Item model.ListItem
}

// FilterValue returns the string used for fuzzy filtering.
func (w ListItemWrapper) FilterValue() string {
	return w.Item.GetTitle()
}

// Title returns the item title for the list.
func (w ListItemWrapper) Title() string {
	return w.Item.GetTitle()
}

// Description returns a short summary line for the list.
func (w ListItemWrapper) Description() string {
	parts := []string{
		w.Item.GetSource(),
		w.Item.GetStatus(),
		relativeTime(w.Item.GetUpdatedAt()),
	}
	return strings.Join(parts, " | ")
}

// TaskItem wraps a model.Task so it can be used in a bubbles/list.
// Kept for backward compatibility.
type TaskItem struct {
	Task model.Task
}

// FilterValue returns the string used for fuzzy filtering.
func (i TaskItem) FilterValue() string { return i.Task.Title }

// Title returns the task title for the list.
func (i TaskItem) Title() string { return i.Task.Title }

// Description returns a short summary line for the list.
func (i TaskItem) Description() string {
	parts := []string{
		string(i.Task.SourceType),
		i.Task.Status,
		relativeTime(i.Task.UpdatedAt),
	}
	return strings.Join(parts, " | ")
}

// ItemDelegate implements list.ItemDelegate for rendering list items.
type ItemDelegate struct {
	// staleSources maps source names to true when the source has a sync error.
	// Shared by reference with the tasklist Model so updates are visible.
	staleSources map[string]bool
}

// TaskDelegate is an alias for backward compatibility.
type TaskDelegate = ItemDelegate

// Height returns the number of lines each item takes.
func (d ItemDelegate) Height() int { return 1 }

// Spacing returns the number of blank lines between items.
func (d ItemDelegate) Spacing() int { return 0 }

// Update handles per-item messages (unused for now).
func (d ItemDelegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd {
	return nil
}

// Render draws a single list item line.
func (d ItemDelegate) Render(w io.Writer, m list.Model, index int, item list.Item) {
	wrapper, ok := item.(ListItemWrapper)
	if !ok {
		// Fallback for old TaskItem type
		if taskItem, ok := item.(TaskItem); ok {
			wrapper = ListItemWrapper{Item: taskItem.Task}
		} else {
			return
		}
	}

	li := wrapper.Item
	isSelected := index == m.Index()

	if li.IsLocal() {
		d.renderLocalTodo(w, li, isSelected)
	} else {
		d.renderExternalTask(w, li, isSelected)
	}
}

// renderLocalTodo draws a local todo item.
func (d ItemDelegate) renderLocalTodo(w io.Writer, li model.ListItem, isSelected bool) {
	// Prefix: ✓ for complete, ○ for open
	var prefix string
	if li.IsCompleted() {
		prefix = "✓"
	} else {
		prefix = "○"
	}

	// Source badge
	srcBadge := theme.LocalBadgeStyle.Render("LOC")

	// Status badge
	statusBadge := theme.StatusStyle(li.GetStatus()).Render(li.GetStatus())

	// Priority indicator
	priStyle := theme.PriorityStyle(li.GetPriority())
	priBadge := priStyle.Render(priorityLabel(li.GetPriority()))

	// Title
	title := li.GetTitle()

	// Due date
	dueDateStr := ""
	if dd := li.GetDueDate(); dd != nil {
		dueDateStr = theme.DueDateStyle.Render(" " + dd.Format("Jan 02"))
	}

	// Overdue indicator
	overdueStr := ""
	if li.IsOverdue() {
		overdueStr = theme.OverdueStyle.Render(" OVERDUE")
	}

	// Project and tag badges (only available via Todo type assertion)
	projectBadge := ""
	tagBadge := ""
	if todo, ok := li.(model.Todo); ok {
		if todo.ProjectID != nil {
			projectBadge = lipgloss.NewStyle().
				Foreground(theme.ColorBlue).
				Render(" 📁")
		}
		if len(todo.Tags) > 0 {
			var tagNames []string
			for _, t := range todo.Tags {
				tagNames = append(tagNames, t.Name)
			}
			// Show max 2 tags to avoid overflow
			display := tagNames
			if len(display) > 2 {
				display = display[:2]
				display = append(display, "…")
			}
			tagBadge = lipgloss.NewStyle().
				Foreground(theme.ColorMagenta).
				Render(" 🏷 " + strings.Join(display, ","))
		}
	}

	line := fmt.Sprintf(
		"%s %s %s %s %s%s%s%s%s",
		prefix, srcBadge, statusBadge, priBadge, title,
		projectBadge, tagBadge, dueDateStr, overdueStr,
	)

	// Apply dimmed style for completed items
	if li.IsCompleted() {
		line = theme.DimmedStyle.Render(line)
	}

	if isSelected {
		line = theme.SelectedItemStyle.Render(line)
	} else {
		line = theme.ListItemStyle.Render(line)
	}

	fmt.Fprint(w, line)
}

// renderExternalTask draws an external task item.
func (d ItemDelegate) renderExternalTask(w io.Writer, li model.ListItem, isSelected bool) {
	source := li.GetSource()

	// Source badge
	srcStyle := theme.SourceLabelStyle(source)
	srcBadge := srcStyle.Render(strings.ToUpper(source)[:min(3, len(source))])

	// Status badge
	statusStyle := theme.StatusStyle(li.GetStatus())
	statusBadge := statusStyle.Render(li.GetStatus())

	// Priority indicator
	priStyle := theme.PriorityStyle(li.GetPriority())
	priBadge := priStyle.Render(priorityLabel(li.GetPriority()))

	// Title
	title := li.GetTitle()

	// Staleness indicator (for external tasks)
	staleIndicator := ""
	if d.staleSources[source] {
		// Source has a sync error — show prominent warning
		staleIndicator = lipgloss.NewStyle().
			Foreground(theme.ColorYellow).
			Render(" ⚠")
	} else if task, ok := li.(model.Task); ok {
		if time.Since(task.FetchedAt) > StalenessThreshold {
			staleIndicator = lipgloss.NewStyle().
				Foreground(theme.ColorGray).
				Render(" ●")
		}
	}

	// Time
	timeStr := lipgloss.NewStyle().
		Foreground(theme.ColorGray).
		Render(relativeTime(li.GetUpdatedAt()))

	line := fmt.Sprintf(
		"● %s %s %s %s%s  %s",
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
