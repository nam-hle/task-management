package tagmgr

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

// TagListCloseMsg signals the parent to close the tag view.
type TagListCloseMsg struct{}

// TagChangedMsg signals that tags were modified.
type TagChangedMsg struct{}

type tagMode int

const (
	modeList tagMode = iota
	modeForm
	modeConfirmDelete
)

type formBindings struct {
	name    string
	color   string
	confirm bool
}

type tagsLoadedMsg struct {
	tags []model.Tag
}

type tagSavedMsg struct{ err error }
type tagDeletedMsg struct{ err error }

// Model is the Bubble Tea model for tag management.
type Model struct {
	mode        tagMode
	store       store.Store
	keys        *keys.KeyMap
	tags        []model.Tag
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

// New creates a new tag manager model.
func New(s store.Store, k *keys.KeyMap, width, height int) Model {
	return Model{
		mode:  modeList,
		store: s,
		keys:  k,
		fb:    &formBindings{},
		width: width, height: height,
	}
}

// Init loads tags from the store.
func (m Model) Init() tea.Cmd {
	return m.loadTags()
}

// Update handles messages.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tagsLoadedMsg:
		m.tags = msg.tags
		if m.selectedIdx >= len(m.tags) && m.selectedIdx > 0 {
			m.selectedIdx = len(m.tags) - 1
		}
		return m, nil

	case tagSavedMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error: %v", msg.err)
		} else {
			m.statusMsg = "Tag saved"
		}
		m.mode = modeList
		return m, tea.Batch(m.loadTags(), func() tea.Msg { return TagChangedMsg{} })

	case tagDeletedMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error: %v", msg.err)
		} else {
			m.statusMsg = "Tag deleted"
		}
		m.mode = modeList
		return m, tea.Batch(m.loadTags(), func() tea.Msg { return TagChangedMsg{} })

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
		return m, func() tea.Msg { return TagListCloseMsg{} }

	case key.Matches(msg, m.keys.Down):
		if len(m.tags) > 0 {
			m.selectedIdx = (m.selectedIdx + 1) % len(m.tags)
		}
		return m, nil

	case key.Matches(msg, m.keys.Up):
		if len(m.tags) > 0 {
			m.selectedIdx--
			if m.selectedIdx < 0 {
				m.selectedIdx = len(m.tags) - 1
			}
		}
		return m, nil

	case msg.String() == "n":
		m.isNew = true
		m.editingID = ""
		m.fb.name = ""
		m.fb.color = "#6BCB77"
		m.form = m.buildForm()
		m.mode = modeForm
		return m, m.form.Init()

	case msg.String() == "e":
		if len(m.tags) == 0 {
			return m, nil
		}
		t := m.tags[m.selectedIdx]
		m.isNew = false
		m.editingID = t.ID
		m.fb.name = t.Name
		m.fb.color = t.Color
		m.form = m.buildForm()
		m.mode = modeForm
		return m, m.form.Init()

	case msg.String() == "d":
		if len(m.tags) == 0 {
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
				Placeholder("Tag name").
				Value(&m.fb.name).
				Validate(func(s string) error {
					if strings.TrimSpace(s) == "" {
						return fmt.Errorf("name is required")
					}
					return nil
				}),
			huh.NewInput().
				Title("Color").
				Placeholder("#6BCB77").
				Value(&m.fb.color),
		),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight())
}

func (m Model) buildConfirmForm() *huh.Form {
	name := ""
	if m.selectedIdx < len(m.tags) {
		name = m.tags[m.selectedIdx].Name
	}
	return huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().
				Title(fmt.Sprintf("Delete tag %q?", name)).
				Description("This tag will be removed from all todos.").
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
		return m, m.saveTag()
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
			t := m.tags[m.selectedIdx]
			return m, m.deleteTag(t.ID)
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

// View renders the tag manager.
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
	b.WriteString(titleStyle.Render("Tags"))
	b.WriteString("\n\n")

	if len(m.tags) == 0 {
		emptyStyle := lipgloss.NewStyle().Foreground(theme.ColorGray).Italic(true)
		b.WriteString(emptyStyle.Render("No tags yet. Press 'n' to create one."))
	} else {
		for i, t := range m.tags {
			label := fmt.Sprintf("🏷  %s", t.Name)

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
		"n new | e edit | d delete | esc back",
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

func (m Model) loadTags() tea.Cmd {
	s := m.store
	return func() tea.Msg {
		tags, err := s.GetTags(context.Background())
		if err != nil {
			return tagsLoadedMsg{tags: nil}
		}
		return tagsLoadedMsg{tags: tags}
	}
}

func (m Model) saveTag() tea.Cmd {
	s := m.store
	fb := m.fb
	editID := m.editingID
	isNew := m.isNew
	return func() tea.Msg {
		t := model.Tag{
			Name:  fb.name,
			Color: fb.color,
		}
		if isNew {
			err := s.CreateTag(context.Background(), t)
			return tagSavedMsg{err: err}
		}
		t.ID = editID
		err := s.UpdateTag(context.Background(), t)
		return tagSavedMsg{err: err}
	}
}

func (m Model) deleteTag(id string) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		err := s.DeleteTag(context.Background(), id)
		return tagDeletedMsg{err: err}
	}
}
