package projectmgr

import (
	"context"
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"

	"github.com/nhle/task-management/internal/keys"
	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/store"
	"github.com/nhle/task-management/internal/theme"
)

// ProjectListCloseMsg signals the parent to close the project view.
type ProjectListCloseMsg struct{}

// ProjectChangedMsg signals that projects were modified (created/updated/deleted).
type ProjectChangedMsg struct{}

type projectMode int

const (
	modeList projectMode = iota
	modeForm
	modeConfirmDelete
)

type formBindings struct {
	name        string
	description string
	color       string
	icon        string
	confirm     bool
}

type projectsLoadedMsg struct {
	projects []model.Project
}

type projectSavedMsg struct{ err error }
type projectDeletedMsg struct{ err error }
type projectArchivedMsg struct{ err error }

// Model is the Bubble Tea model for project management.
type Model struct {
	mode        projectMode
	store       store.Store
	keys        *keys.KeyMap
	projects    []model.Project
	selectedIdx int
	editingID   string
	isNew       bool
	form        *huh.Form
	confirmForm *huh.Form
	fb          *formBindings
	statusMsg   string
	width       int
	height      int
}

// New creates a new project manager model.
func New(s store.Store, k *keys.KeyMap, width, height int) Model {
	return Model{
		mode:  modeList,
		store: s,
		keys:  k,
		fb:    &formBindings{},
		width: width, height: height,
	}
}

// Init loads projects from the store.
func (m Model) Init() tea.Cmd {
	return m.loadProjects()
}

// Update handles messages.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case projectsLoadedMsg:
		m.projects = msg.projects
		if m.selectedIdx >= len(m.projects) && m.selectedIdx > 0 {
			m.selectedIdx = len(m.projects) - 1
		}
		return m, nil

	case projectSavedMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error: %v", msg.err)
		} else {
			m.statusMsg = "Project saved"
		}
		m.mode = modeList
		return m, tea.Batch(m.loadProjects(), func() tea.Msg { return ProjectChangedMsg{} })

	case projectDeletedMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error: %v", msg.err)
		} else {
			m.statusMsg = "Project deleted"
		}
		m.mode = modeList
		return m, tea.Batch(m.loadProjects(), func() tea.Msg { return ProjectChangedMsg{} })

	case projectArchivedMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error: %v", msg.err)
		}
		m.mode = modeList
		return m, tea.Batch(m.loadProjects(), func() tea.Msg { return ProjectChangedMsg{} })

	case tea.KeyMsg:
		return m.handleKey(msg)
	}

	return m.updateActiveForm(msg)
}

func (m Model) handleKey(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch m.mode {
	case modeList:
		return m.handleListKey(msg)
	case modeForm:
		return m.updateForm(msg)
	case modeConfirmDelete:
		return m.updateConfirm(msg)
	}
	return m, nil
}

func (m Model) handleListKey(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Back):
		return m, func() tea.Msg { return ProjectListCloseMsg{} }

	case key.Matches(msg, m.keys.Down):
		if len(m.projects) > 0 {
			m.selectedIdx = (m.selectedIdx + 1) % len(m.projects)
		}
		return m, nil

	case key.Matches(msg, m.keys.Up):
		if len(m.projects) > 0 {
			m.selectedIdx--
			if m.selectedIdx < 0 {
				m.selectedIdx = len(m.projects) - 1
			}
		}
		return m, nil

	case msg.String() == "n":
		m.isNew = true
		m.editingID = ""
		m.fb.name = ""
		m.fb.description = ""
		m.fb.color = "#5B9BD5"
		m.fb.icon = "📁"
		m.form = m.buildForm()
		m.mode = modeForm
		return m, m.form.Init()

	case msg.String() == "e":
		if len(m.projects) == 0 {
			return m, nil
		}
		p := m.projects[m.selectedIdx]
		m.isNew = false
		m.editingID = p.ID
		m.fb.name = p.Name
		m.fb.description = p.Description
		m.fb.color = p.Color
		m.fb.icon = p.Icon
		m.form = m.buildForm()
		m.mode = modeForm
		return m, m.form.Init()

	case msg.String() == "a":
		if len(m.projects) == 0 {
			return m, nil
		}
		p := m.projects[m.selectedIdx]
		return m, m.toggleArchive(p)

	case msg.String() == "d":
		if len(m.projects) == 0 {
			return m, nil
		}
		m.fb.confirm = false
		m.confirmForm = m.buildConfirmForm()
		m.mode = modeConfirmDelete
		return m, m.confirmForm.Init()
	}
	return m, nil
}

func (m Model) buildForm() *huh.Form {
	return huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Name").
				Placeholder("Project name").
				Value(&m.fb.name).
				Validate(func(s string) error {
					if strings.TrimSpace(s) == "" {
						return fmt.Errorf("name is required")
					}
					return nil
				}),
			huh.NewText().
				Title("Description").
				Placeholder("Optional description").
				Value(&m.fb.description),
			huh.NewInput().
				Title("Color").
				Placeholder("#5B9BD5").
				Value(&m.fb.color),
			huh.NewInput().
				Title("Icon").
				Placeholder("📁").
				Value(&m.fb.icon),
		),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight())
}

func (m Model) buildConfirmForm() *huh.Form {
	name := ""
	if m.selectedIdx < len(m.projects) {
		name = m.projects[m.selectedIdx].Name
	}
	return huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().
				Title(fmt.Sprintf("Delete project %q?", name)).
				Description("Todos in this project will move to Inbox.").
				Affirmative("Yes, delete").
				Negative("Cancel").
				Value(&m.fb.confirm),
		),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight())
}

func (m Model) updateForm(msg tea.Msg) (Model, tea.Cmd) {
	if m.form == nil {
		return m, nil
	}
	mdl, cmd := m.form.Update(msg)
	if f, ok := mdl.(*huh.Form); ok {
		m.form = f
	}
	if m.form.State == huh.StateCompleted {
		return m, m.saveProject()
	}
	if m.form.State == huh.StateAborted {
		m.mode = modeList
		return m, nil
	}
	return m, cmd
}

func (m Model) updateConfirm(msg tea.Msg) (Model, tea.Cmd) {
	if m.confirmForm == nil {
		return m, nil
	}
	mdl, cmd := m.confirmForm.Update(msg)
	if f, ok := mdl.(*huh.Form); ok {
		m.confirmForm = f
	}
	if m.confirmForm.State == huh.StateCompleted {
		if m.fb.confirm {
			p := m.projects[m.selectedIdx]
			return m, m.deleteProject(p.ID)
		}
		m.mode = modeList
		return m, nil
	}
	if m.confirmForm.State == huh.StateAborted {
		m.mode = modeList
		return m, nil
	}
	return m, cmd
}

func (m Model) updateActiveForm(msg tea.Msg) (Model, tea.Cmd) {
	switch m.mode {
	case modeForm:
		return m.updateForm(msg)
	case modeConfirmDelete:
		return m.updateConfirm(msg)
	}
	return m, nil
}

// View renders the project manager.
func (m Model) View() string {
	switch m.mode {
	case modeForm:
		return m.viewForm(m.form)
	case modeConfirmDelete:
		return m.viewForm(m.confirmForm)
	default:
		return m.viewList()
	}
}

func (m Model) viewList() string {
	var b strings.Builder

	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(theme.ColorWhite).MarginBottom(1)
	b.WriteString(titleStyle.Render("Projects"))
	b.WriteString("\n\n")

	if len(m.projects) == 0 {
		emptyStyle := lipgloss.NewStyle().Foreground(theme.ColorGray).Italic(true)
		b.WriteString(emptyStyle.Render("No projects yet. Press 'n' to create one."))
	} else {
		for i, p := range m.projects {
			icon := p.Icon
			if icon == "" {
				icon = "📁"
			}

			label := fmt.Sprintf("%s  %s", icon, p.Name)
			if p.Archived {
				label += " (archived)"
			}

			if i == m.selectedIdx {
				b.WriteString(theme.SelectedItemStyle.Render(label))
			} else {
				b.WriteString(theme.ListItemStyle.Render(label))
			}
			b.WriteString("\n")
		}
	}

	if m.statusMsg != "" {
		b.WriteString("\n")
		b.WriteString(lipgloss.NewStyle().Foreground(theme.ColorYellow).Italic(true).Render(m.statusMsg))
	}

	b.WriteString("\n\n")
	b.WriteString(lipgloss.NewStyle().Foreground(theme.ColorGray).Render(
		"n new | e edit | a archive/restore | d delete | esc back",
	))

	return lipgloss.NewStyle().Padding(1, 2).Width(m.width).Height(m.height).Render(b.String())
}

func (m Model) viewForm(f *huh.Form) string {
	if f == nil {
		return ""
	}
	return lipgloss.NewStyle().Padding(1, 2).Render(f.View())
}

// SetSize updates dimensions.
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
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

func (m Model) loadProjects() tea.Cmd {
	s := m.store
	return func() tea.Msg {
		projects, err := s.GetProjects(context.Background(), true)
		if err != nil {
			return projectsLoadedMsg{projects: nil}
		}
		return projectsLoadedMsg{projects: projects}
	}
}

func (m Model) saveProject() tea.Cmd {
	s := m.store
	fb := m.fb
	editID := m.editingID
	isNew := m.isNew
	return func() tea.Msg {
		p := model.Project{
			Name:        fb.name,
			Description: fb.description,
			Color:       fb.color,
			Icon:        fb.icon,
		}
		if isNew {
			err := s.CreateProject(context.Background(), p)
			return projectSavedMsg{err: err}
		}
		p.ID = editID
		err := s.UpdateProject(context.Background(), p)
		return projectSavedMsg{err: err}
	}
}

func (m Model) deleteProject(id string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		err := s.DeleteProject(context.Background(), id)
		return projectDeletedMsg{err: err}
	}
}

func (m Model) toggleArchive(p model.Project) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		var err error
		if p.Archived {
			err = s.RestoreProject(context.Background(), p.ID)
		} else {
			err = s.ArchiveProject(context.Background(), p.ID)
		}
		return projectArchivedMsg{err: err}
	}
}
