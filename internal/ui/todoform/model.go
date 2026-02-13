package todoform

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/theme"
)

// TodoCreatedMsg is dispatched when a new todo is created via the form.
type TodoCreatedMsg struct {
	Todo   model.Todo
	TagIDs []string
}

// TodoUpdatedMsg is dispatched when an existing todo is updated via the form.
type TodoUpdatedMsg struct {
	Todo   model.Todo
	TagIDs []string
}

// TodoFormCancelMsg is dispatched when the user cancels the form.
type TodoFormCancelMsg struct{}

// formBindings holds form field values on the heap so that huh's Value()
// pointers remain valid across Bubble Tea model copies.
type formBindings struct {
	title       string
	description string
	priority    int
	dueDate     string
	status      string
	projectID   string
	tagIDs      []string
}

// Model is the Bubble Tea model for the todo create/edit form.
type Model struct {
	form     *huh.Form
	fb       *formBindings
	editMode bool
	editID   string
	projects []model.Project
	tags     []model.Tag
	width    int
	height   int
}

// New creates a new todo form model.
func New(width, height int) Model {
	return Model{
		fb:     &formBindings{priority: model.PriorityMedium, status: model.TodoStatusOpen},
		width:  width,
		height: height,
	}
}

// SetOptions sets the available projects and tags for the form selectors.
func (m *Model) SetOptions(projects []model.Project, tags []model.Tag) {
	m.projects = projects
	m.tags = tags
}

// StartCreate initializes the form for creating a new todo.
func (m *Model) StartCreate() tea.Cmd {
	m.editMode = false
	m.editID = ""
	m.fb.title = ""
	m.fb.description = ""
	m.fb.priority = model.PriorityMedium
	m.fb.dueDate = ""
	m.fb.status = model.TodoStatusOpen
	m.fb.projectID = ""
	m.fb.tagIDs = nil
	m.form = m.buildCreateForm()
	return m.form.Init()
}

// StartEdit initializes the form for editing an existing todo.
func (m *Model) StartEdit(todo model.Todo) tea.Cmd {
	m.editMode = true
	m.editID = todo.ID
	m.fb.title = todo.Title
	m.fb.description = todo.Description
	m.fb.priority = todo.Priority
	m.fb.status = todo.Status
	if todo.DueDate != nil {
		m.fb.dueDate = todo.DueDate.Format("2006-01-02")
	} else {
		m.fb.dueDate = ""
	}
	if todo.ProjectID != nil {
		m.fb.projectID = *todo.ProjectID
	} else {
		m.fb.projectID = ""
	}
	// Extract tag IDs from the todo's tags
	m.fb.tagIDs = nil
	for _, t := range todo.Tags {
		m.fb.tagIDs = append(m.fb.tagIDs, t.ID)
	}
	m.form = m.buildEditForm()
	return m.form.Init()
}

// Update handles messages for the todo form.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	if m.form == nil {
		return m, nil
	}

	mdl, cmd := m.form.Update(msg)
	if f, ok := mdl.(*huh.Form); ok {
		m.form = f
	}

	if m.form.State == huh.StateCompleted {
		return m, m.handleSubmit()
	}
	if m.form.State == huh.StateAborted {
		return m, func() tea.Msg { return TodoFormCancelMsg{} }
	}

	return m, cmd
}

// View renders the todo form.
func (m Model) View() string {
	if m.form == nil {
		return ""
	}

	titleText := "New Todo"
	if m.editMode {
		titleText = "Edit Todo"
	}

	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(theme.ColorWhite).
		MarginBottom(1)

	content := titleStyle.Render(titleText) + "\n" + m.form.View()

	return lipgloss.NewStyle().
		Padding(1, 2).
		Render(content)
}

// SetSize updates the form dimensions.
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
}

func (m *Model) buildCreateForm() *huh.Form {
	fields := m.coreFields()
	fields = append(fields, m.projectField())
	if tagField := m.tagField(); tagField != nil {
		fields = append(fields, tagField)
	}

	return huh.NewForm(
		huh.NewGroup(fields...),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight())
}

func (m *Model) buildEditForm() *huh.Form {
	fields := m.coreFields()
	fields = append(fields, m.projectField())
	if tagField := m.tagField(); tagField != nil {
		fields = append(fields, tagField)
	}
	fields = append(fields,
		huh.NewSelect[string]().
			Title("Status").
			Options(
				huh.NewOption("Open", model.TodoStatusOpen),
				huh.NewOption("Complete", model.TodoStatusComplete),
			).
			Value(&m.fb.status),
	)

	return huh.NewForm(
		huh.NewGroup(fields...),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight())
}

func (m *Model) coreFields() []huh.Field {
	return []huh.Field{
		huh.NewInput().
			Title("Title").
			Placeholder("What needs to be done?").
			Value(&m.fb.title).
			Validate(validateRequired("Title")),
		huh.NewText().
			Title("Description").
			Placeholder("Optional details...").
			Value(&m.fb.description),
		huh.NewSelect[int]().
			Title("Priority").
			Options(
				huh.NewOption("P1 - Critical", model.PriorityCritical),
				huh.NewOption("P2 - High", model.PriorityHigh),
				huh.NewOption("P3 - Medium", model.PriorityMedium),
				huh.NewOption("P4 - Low", model.PriorityLow),
				huh.NewOption("P5 - Lowest", model.PriorityLowest),
			).
			Value(&m.fb.priority),
		huh.NewInput().
			Title("Due Date").
			Placeholder("YYYY-MM-DD (optional)").
			Value(&m.fb.dueDate).
			Validate(validateOptionalDate),
	}
}

func (m *Model) projectField() huh.Field {
	opts := []huh.Option[string]{
		huh.NewOption("None (Inbox)", ""),
	}
	for _, p := range m.projects {
		if !p.Archived {
			opts = append(opts, huh.NewOption(p.Name, p.ID))
		}
	}
	return huh.NewSelect[string]().
		Title("Project").
		Options(opts...).
		Value(&m.fb.projectID)
}

func (m *Model) tagField() huh.Field {
	if len(m.tags) == 0 {
		return nil
	}
	opts := make([]huh.Option[string], len(m.tags))
	for i, t := range m.tags {
		opts[i] = huh.NewOption(t.Name, t.ID)
	}
	return huh.NewMultiSelect[string]().
		Title("Tags").
		Options(opts...).
		Value(&m.fb.tagIDs)
}

func (m Model) handleSubmit() tea.Cmd {
	todo := model.Todo{
		Title:       m.fb.title,
		Description: m.fb.description,
		Priority:    m.fb.priority,
		Status:      m.fb.status,
	}

	if m.fb.projectID != "" {
		todo.ProjectID = &m.fb.projectID
	}

	if m.fb.dueDate != "" {
		t, err := time.Parse("2006-01-02", m.fb.dueDate)
		if err == nil {
			todo.DueDate = &t
		}
	}

	tagIDs := m.fb.tagIDs

	if m.editMode {
		todo.ID = m.editID
		return func() tea.Msg { return TodoUpdatedMsg{Todo: todo, TagIDs: tagIDs} }
	}
	return func() tea.Msg { return TodoCreatedMsg{Todo: todo, TagIDs: tagIDs} }
}

func (m Model) formWidth() int {
	w := m.width - 4
	if w < 40 {
		w = 40
	}
	if w > 100 {
		w = 100
	}
	return w
}

func (m Model) formHeight() int {
	h := m.height - 4
	if h < 10 {
		h = 10
	}
	return h
}

func validateRequired(fieldName string) func(string) error {
	return func(s string) error {
		if strings.TrimSpace(s) == "" {
			return fmt.Errorf("%s is required", fieldName)
		}
		return nil
	}
}

func validateOptionalDate(s string) error {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	_, err := time.Parse("2006-01-02", s)
	if err != nil {
		return fmt.Errorf("invalid date format, use YYYY-MM-DD")
	}
	return nil
}
