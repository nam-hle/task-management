package config

import (
	"context"
	"fmt"
	"net/url"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"
	"github.com/google/uuid"

	"github.com/nhle/task-management/internal/credential"
	"github.com/nhle/task-management/internal/keys"
	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source"
	"github.com/nhle/task-management/internal/source/bitbucket"
	"github.com/nhle/task-management/internal/source/email"
	"github.com/nhle/task-management/internal/source/jira"
	"github.com/nhle/task-management/internal/store"
	"github.com/nhle/task-management/internal/theme"
)

// ConfigMode represents the current state of the configuration view.
type ConfigMode int

const (
	ModeList           ConfigMode = iota // List configured sources
	ModeSelectType                       // Select source type to add
	ModeFormJira                         // Jira-specific form
	ModeFormBitbucket                    // Bitbucket-specific form
	ModeFormEmail                        // Email-specific form
	ModeValidating                       // Testing connection
	ModeValidateResult                   // Show validation result
	ModeConfirmDelete                    // Confirm source deletion
)

// ConfigDoneMsg signals the config view should close and return to the main app.
type ConfigDoneMsg struct{}

// SourceSavedMsg signals a source was saved successfully.
type SourceSavedMsg struct {
	Source model.SourceConfig
}

// SourceDeletedMsg signals a source was deleted.
type SourceDeletedMsg struct {
	ID string
}

// ValidateResultMsg carries the result of a connection validation attempt.
type ValidateResultMsg struct {
	Name string
	Err  error
}

// sourcesLoadedMsg is sent when sources have been loaded from the store.
type sourcesLoadedMsg struct {
	sources []model.SourceConfig
	err     error
}

// sourceSavedInternalMsg is sent after a source is persisted.
type sourceSavedInternalMsg struct {
	source model.SourceConfig
	err    error
}

// sourceDeletedInternalMsg is sent after a source is removed.
type sourceDeletedInternalMsg struct {
	id  string
	err error
}

// formBindings holds form field values on the heap so that huh's Value()
// pointers remain valid across Bubble Tea model copies.
type formBindings struct {
	name    string
	baseURL string
	token   string
	jql     string

	imapHost string
	imapPort string
	smtpHost string
	smtpPort string
	username string
	password string
	tls      bool

	selectedType  string
	deleteConfirm bool
}

// Model is the Bubble Tea model for the source configuration UI.
type Model struct {
	mode          ConfigMode
	store         store.Store
	sources       []model.SourceConfig
	selectedIdx   int
	editingSource *model.SourceConfig
	isNewSource   bool

	// Huh forms for each source type
	jiraForm   *huh.Form
	bbForm     *huh.Form
	emailForm  *huh.Form
	typeSelect *huh.Form

	// Heap-allocated form bindings (survives model copies)
	fb *formBindings

	// Validation
	validating  bool
	validResult string
	validError  error
	spinner     spinner.Model

	// Delete confirmation
	confirmDelete *huh.Form

	// Status message for transient feedback
	statusMsg string

	keys          *keys.KeyMap
	width, height int
}

// New creates a new configuration view model.
func New(s store.Store, k *keys.KeyMap, width, height int) Model {
	sp := spinner.New()
	sp.Spinner = spinner.Dot

	return Model{
		mode:    ModeList,
		store:   s,
		keys:    k,
		spinner: sp,
		fb:      &formBindings{tls: true},
		width:   width,
		height:  height,
	}
}

// Init loads sources from the store on first render.
func (m Model) Init() tea.Cmd {
	return m.loadSources()
}

// Update handles messages and dispatches based on current mode.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		// Forward to active huh form so it can calculate its layout.
		return m.updateActiveForm(msg)

	case sourcesLoadedMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error loading sources: %v", msg.err)
			return m, nil
		}
		m.sources = msg.sources
		return m, nil

	case sourceSavedInternalMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error saving source: %v", msg.err)
			m.mode = ModeList
			return m, nil
		}
		m.statusMsg = fmt.Sprintf("Source %q saved", msg.source.Name)
		m.mode = ModeList
		return m, tea.Batch(
			m.loadSources(),
			func() tea.Msg { return SourceSavedMsg{Source: msg.source} },
		)

	case sourceDeletedInternalMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error deleting source: %v", msg.err)
			m.mode = ModeList
			return m, nil
		}
		m.statusMsg = "Source deleted"
		m.mode = ModeList
		if m.selectedIdx >= len(m.sources)-1 && m.selectedIdx > 0 {
			m.selectedIdx--
		}
		return m, tea.Batch(
			m.loadSources(),
			func() tea.Msg { return SourceDeletedMsg{ID: msg.id} },
		)

	case ValidateResultMsg:
		m.validating = false
		m.validResult = msg.Name
		m.validError = msg.Err
		m.mode = ModeValidateResult
		return m, nil

	case spinner.TickMsg:
		if m.mode == ModeValidating {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
		return m, nil

	case tea.KeyMsg:
		return m.handleKeyMsg(msg)
	}

	// Delegate to active form
	return m.updateActiveForm(msg)
}

// handleKeyMsg processes key messages based on the current mode.
func (m Model) handleKeyMsg(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch m.mode {
	case ModeList:
		return m.handleListKeys(msg)
	case ModeSelectType:
		return m.updateTypeSelect(msg)
	case ModeFormJira:
		return m.updateJiraForm(msg)
	case ModeFormBitbucket:
		return m.updateBBForm(msg)
	case ModeFormEmail:
		return m.updateEmailForm(msg)
	case ModeValidateResult:
		return m.handleValidateResultKeys(msg)
	case ModeConfirmDelete:
		return m.updateConfirmDelete(msg)
	case ModeValidating:
		// Only allow escape during validation
		if msg.String() == "esc" {
			m.mode = ModeList
			m.validating = false
			return m, nil
		}
		return m, nil
	}
	return m, nil
}

// handleListKeys processes key events in the source list mode.
func (m Model) handleListKeys(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Back):
		return m, func() tea.Msg { return ConfigDoneMsg{} }

	case msg.String() == "a":
		m.isNewSource = true
		m.editingSource = nil
		m.mode = ModeSelectType
		m.fb.selectedType = ""
		m.typeSelect = m.buildTypeSelectForm()
		return m, m.typeSelect.Init()

	case msg.String() == "e":
		if len(m.sources) == 0 {
			return m, nil
		}
		src := m.sources[m.selectedIdx]
		m.isNewSource = false
		m.editingSource = &src
		return m, m.startEditForm(src)

	case msg.String() == "d":
		if len(m.sources) == 0 {
			return m, nil
		}
		m.fb.deleteConfirm = false
		m.confirmDelete = m.buildDeleteConfirmForm()
		m.mode = ModeConfirmDelete
		return m, m.confirmDelete.Init()

	case msg.String() == "enter":
		if len(m.sources) == 0 {
			// No sources yet — treat Enter like 'a' to add one.
			m.isNewSource = true
			m.editingSource = nil
			m.mode = ModeSelectType
			m.fb.selectedType = ""
			m.typeSelect = m.buildTypeSelectForm()
			return m, m.typeSelect.Init()
		}
		src := m.sources[m.selectedIdx]
		m.mode = ModeValidating
		m.validating = true
		return m, tea.Batch(
			m.spinner.Tick,
			m.validateSource(src),
		)

	case key.Matches(msg, m.keys.Down):
		if len(m.sources) > 0 {
			m.selectedIdx = (m.selectedIdx + 1) % len(m.sources)
		}
		return m, nil

	case key.Matches(msg, m.keys.Up):
		if len(m.sources) > 0 {
			m.selectedIdx--
			if m.selectedIdx < 0 {
				m.selectedIdx = len(m.sources) - 1
			}
		}
		return m, nil
	}

	return m, nil
}

// handleValidateResultKeys processes key events on the validation result screen.
func (m Model) handleValidateResultKeys(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch msg.String() {
	case "enter", "esc":
		m.mode = ModeList
		m.validResult = ""
		m.validError = nil
		return m, nil
	case "r":
		if m.validError != nil && len(m.sources) > 0 {
			src := m.sources[m.selectedIdx]
			m.mode = ModeValidating
			m.validating = true
			return m, tea.Batch(
				m.spinner.Tick,
				m.validateSource(src),
			)
		}
		return m, nil
	}
	return m, nil
}

// updateActiveForm dispatches non-key messages to the currently active form.
func (m Model) updateActiveForm(msg tea.Msg) (Model, tea.Cmd) {
	switch m.mode {
	case ModeSelectType:
		return m.updateTypeSelect(msg)
	case ModeFormJira:
		return m.updateJiraForm(msg)
	case ModeFormBitbucket:
		return m.updateBBForm(msg)
	case ModeFormEmail:
		return m.updateEmailForm(msg)
	case ModeConfirmDelete:
		return m.updateConfirmDelete(msg)
	}
	return m, nil
}

// --- Type Selection ---

func (m Model) buildTypeSelectForm() *huh.Form {
	return huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Select Source Type").
				Description("Choose the type of source to add").
				Options(
					huh.NewOption("Jira - Issue tracking and project management", "jira"),
					huh.NewOption("Bitbucket - Code review and pull requests", "bitbucket"),
					huh.NewOption("Email - IMAP mailbox integration", "email"),
				).
				Value(&m.fb.selectedType),
		),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight()).WithHeight(m.formHeight())
}

func (m Model) updateTypeSelect(msg tea.Msg) (Model, tea.Cmd) {
	if m.typeSelect == nil {
		return m, nil
	}

	mdl, cmd := m.typeSelect.Update(msg)
	if f, ok := mdl.(*huh.Form); ok {
		m.typeSelect = f
	}

	if m.typeSelect.State == huh.StateCompleted {
		return m.handleTypeSelected()
	}
	if m.typeSelect.State == huh.StateAborted {
		m.mode = ModeList
		return m, nil
	}

	return m, cmd
}

func (m Model) handleTypeSelected() (Model, tea.Cmd) {
	m.resetFormFields()

	switch m.fb.selectedType {
	case "jira":
		m.mode = ModeFormJira
		m.jiraForm = m.buildJiraForm()
		return m, m.jiraForm.Init()
	case "bitbucket":
		m.mode = ModeFormBitbucket
		m.bbForm = m.buildBBForm()
		return m, m.bbForm.Init()
	case "email":
		m.mode = ModeFormEmail
		m.emailForm = m.buildEmailForm()
		return m, m.emailForm.Init()
	default:
		m.mode = ModeList
		return m, nil
	}
}

// --- Jira Form (T037) ---

func (m *Model) buildJiraForm() *huh.Form {
	return huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Name").
				Description("A label for this Jira instance").
				Placeholder("My Jira").
				Value(&m.fb.name).
				Validate(validateRequired("Name")),
			huh.NewInput().
				Title("Base URL").
				Description("Jira server URL (e.g., https://jira.example.com)").
				Placeholder("https://jira.example.com").
				Value(&m.fb.baseURL).
				Validate(validateURL),
			huh.NewInput().
				Title("Personal Access Token").
				Description("Your Jira PAT for authentication").
				EchoMode(huh.EchoModePassword).
				Value(&m.fb.token).
				Validate(validateRequired("Token")),
			huh.NewInput().
				Title("Default JQL").
				Description("Optional custom JQL filter").
				Placeholder("assignee=currentUser() AND resolution=Unresolved").
				Value(&m.fb.jql),
		),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight()).WithHeight(m.formHeight())
}

func (m Model) updateJiraForm(msg tea.Msg) (Model, tea.Cmd) {
	if m.jiraForm == nil {
		return m, nil
	}

	mdl, cmd := m.jiraForm.Update(msg)
	if f, ok := mdl.(*huh.Form); ok {
		m.jiraForm = f
	}

	if m.jiraForm.State == huh.StateCompleted {
		return m.saveJiraSource()
	}
	if m.jiraForm.State == huh.StateAborted {
		m.mode = ModeList
		return m, nil
	}

	return m, cmd
}

func (m Model) saveJiraSource() (Model, tea.Cmd) {
	src := m.buildSourceConfig("jira")
	if m.fb.jql != "" {
		if src.Config == nil {
			src.Config = make(map[string]string)
		}
		src.Config["jql"] = m.fb.jql
	}

	// Store token in keyring
	credKey := "jira-" + src.ID
	if err := credential.Set(credKey, m.fb.token); err != nil {
		m.statusMsg = fmt.Sprintf("Error saving credential: %v", err)
		m.mode = ModeList
		return m, nil
	}

	// Store keyring reference in config
	if src.Config == nil {
		src.Config = make(map[string]string)
	}
	src.Config["token_ref"] = "keyring:" + credKey

	m.mode = ModeValidating
	m.validating = true
	return m, tea.Batch(
		m.spinner.Tick,
		m.validateAndSave(src),
	)
}

// --- Bitbucket Form (T038) ---

func (m *Model) buildBBForm() *huh.Form {
	return huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Name").
				Description("A label for this Bitbucket instance").
				Placeholder("My Bitbucket").
				Value(&m.fb.name).
				Validate(validateRequired("Name")),
			huh.NewInput().
				Title("Base URL").
				Description("Bitbucket server URL (e.g., https://bitbucket.example.com)").
				Placeholder("https://bitbucket.example.com").
				Value(&m.fb.baseURL).
				Validate(validateURL),
			huh.NewInput().
				Title("Personal Access Token").
				Description("Your Bitbucket PAT for authentication").
				EchoMode(huh.EchoModePassword).
				Value(&m.fb.token).
				Validate(validateRequired("Token")),
		),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight())
}

func (m Model) updateBBForm(msg tea.Msg) (Model, tea.Cmd) {
	if m.bbForm == nil {
		return m, nil
	}

	mdl, cmd := m.bbForm.Update(msg)
	if f, ok := mdl.(*huh.Form); ok {
		m.bbForm = f
	}

	if m.bbForm.State == huh.StateCompleted {
		return m.saveBBSource()
	}
	if m.bbForm.State == huh.StateAborted {
		m.mode = ModeList
		return m, nil
	}

	return m, cmd
}

func (m Model) saveBBSource() (Model, tea.Cmd) {
	src := m.buildSourceConfig("bitbucket")

	credKey := "bitbucket-" + src.ID
	if err := credential.Set(credKey, m.fb.token); err != nil {
		m.statusMsg = fmt.Sprintf("Error saving credential: %v", err)
		m.mode = ModeList
		return m, nil
	}

	if src.Config == nil {
		src.Config = make(map[string]string)
	}
	src.Config["token_ref"] = "keyring:" + credKey

	m.mode = ModeValidating
	m.validating = true
	return m, tea.Batch(
		m.spinner.Tick,
		m.validateAndSave(src),
	)
}

// --- Email Form (T039) ---

func (m *Model) buildEmailForm() *huh.Form {
	m.fb.tls = true // Default TLS on

	return huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Name").
				Description("A label for this email source").
				Placeholder("Work Email").
				Value(&m.fb.name).
				Validate(validateRequired("Name")),
			huh.NewInput().
				Title("IMAP Host").
				Description("IMAP server hostname").
				Placeholder("imap.example.com").
				Value(&m.fb.imapHost).
				Validate(validateRequired("IMAP Host")),
			huh.NewInput().
				Title("IMAP Port").
				Description("IMAP server port (e.g., 993)").
				Placeholder("993").
				Value(&m.fb.imapPort).
				Validate(validatePort),
			huh.NewInput().
				Title("SMTP Host").
				Description("SMTP server hostname").
				Placeholder("smtp.example.com").
				Value(&m.fb.smtpHost).
				Validate(validateRequired("SMTP Host")),
			huh.NewInput().
				Title("SMTP Port").
				Description("SMTP server port (e.g., 587)").
				Placeholder("587").
				Value(&m.fb.smtpPort).
				Validate(validatePort),
			huh.NewInput().
				Title("Username").
				Description("Email account username").
				Placeholder("user@example.com").
				Value(&m.fb.username).
				Validate(validateRequired("Username")),
			huh.NewInput().
				Title("Password").
				Description("Email account password or app password").
				EchoMode(huh.EchoModePassword).
				Value(&m.fb.password).
				Validate(validateRequired("Password")),
			huh.NewConfirm().
				Title("Use TLS").
				Description("Enable TLS encryption for connections").
				Affirmative("Yes").
				Negative("No").
				Value(&m.fb.tls),
		),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight())
}

func (m Model) updateEmailForm(msg tea.Msg) (Model, tea.Cmd) {
	if m.emailForm == nil {
		return m, nil
	}

	mdl, cmd := m.emailForm.Update(msg)
	if f, ok := mdl.(*huh.Form); ok {
		m.emailForm = f
	}

	if m.emailForm.State == huh.StateCompleted {
		return m.saveEmailSource()
	}
	if m.emailForm.State == huh.StateAborted {
		m.mode = ModeList
		return m, nil
	}

	return m, cmd
}

func (m Model) saveEmailSource() (Model, tea.Cmd) {
	src := m.buildSourceConfig("email")
	src.Config = map[string]string{
		"imap_host": m.fb.imapHost,
		"imap_port": m.fb.imapPort,
		"smtp_host": m.fb.smtpHost,
		"smtp_port": m.fb.smtpPort,
		"username":  m.fb.username,
		"tls":       fmt.Sprintf("%t", m.fb.tls),
	}

	credKey := "email-" + src.ID
	if err := credential.Set(credKey, m.fb.password); err != nil {
		m.statusMsg = fmt.Sprintf("Error saving credential: %v", err)
		m.mode = ModeList
		return m, nil
	}
	src.Config["password_ref"] = "keyring:" + credKey

	return m, m.saveSource(src)
}

// --- Delete Confirmation ---

func (m *Model) buildDeleteConfirmForm() *huh.Form {
	sourceName := ""
	if m.selectedIdx < len(m.sources) {
		sourceName = m.sources[m.selectedIdx].Name
	}

	return huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().
				Title(fmt.Sprintf("Delete source %q?", sourceName)).
				Description(
					"This will remove the source configuration and " +
						"clear cached tasks.",
				).
				Affirmative("Yes, delete").
				Negative("Cancel").
				Value(&m.fb.deleteConfirm),
		),
	).WithWidth(m.formWidth()).WithHeight(m.formHeight())
}

func (m Model) updateConfirmDelete(msg tea.Msg) (Model, tea.Cmd) {
	if m.confirmDelete == nil {
		return m, nil
	}

	mdl, cmd := m.confirmDelete.Update(msg)
	if f, ok := mdl.(*huh.Form); ok {
		m.confirmDelete = f
	}

	if m.confirmDelete.State == huh.StateCompleted {
		if m.fb.deleteConfirm {
			src := m.sources[m.selectedIdx]
			return m, m.deleteSource(src)
		}
		m.mode = ModeList
		return m, nil
	}
	if m.confirmDelete.State == huh.StateAborted {
		m.mode = ModeList
		return m, nil
	}

	return m, cmd
}

// --- View ---

// View renders the configuration UI based on the current mode.
func (m Model) View() string {
	switch m.mode {
	case ModeList:
		return m.viewList()
	case ModeSelectType:
		return m.viewForm(m.typeSelect)
	case ModeFormJira:
		return m.viewForm(m.jiraForm)
	case ModeFormBitbucket:
		return m.viewForm(m.bbForm)
	case ModeFormEmail:
		return m.viewForm(m.emailForm)
	case ModeValidating:
		return m.viewValidating()
	case ModeValidateResult:
		return m.viewValidateResult()
	case ModeConfirmDelete:
		return m.viewForm(m.confirmDelete)
	default:
		return ""
	}
}

func (m Model) viewList() string {
	var b strings.Builder

	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(theme.ColorWhite).
		MarginBottom(1)

	b.WriteString(titleStyle.Render("Source Configuration"))
	b.WriteString("\n\n")

	if len(m.sources) == 0 {
		emptyStyle := lipgloss.NewStyle().
			Foreground(theme.ColorGray).
			Italic(true)
		b.WriteString(emptyStyle.Render(
			"No sources configured.\nPress 'a' to add a new source.",
		))
	} else {
		for i, src := range m.sources {
			b.WriteString(m.renderSourceItem(i, src))
			b.WriteString("\n")
		}
	}

	if m.statusMsg != "" {
		b.WriteString("\n")
		statusStyle := lipgloss.NewStyle().
			Foreground(theme.ColorYellow).
			Italic(true)
		b.WriteString(statusStyle.Render(m.statusMsg))
	}

	b.WriteString("\n\n")
	hintStyle := lipgloss.NewStyle().Foreground(theme.ColorGray)
	b.WriteString(hintStyle.Render(
		"a add | e edit | d delete | enter test | esc back",
	))

	return lipgloss.NewStyle().
		Padding(1, 2).
		Width(m.width).
		Height(m.height).
		Render(b.String())
}

func (m Model) renderSourceItem(idx int, src model.SourceConfig) string {
	icon := sourceTypeIcon(src.Type)
	enabledLabel := "enabled"
	enabledColor := theme.ColorGreen
	if !src.Enabled {
		enabledLabel = "disabled"
		enabledColor = theme.ColorGray
	}

	name := src.Name
	if name == "" {
		name = "(unnamed)"
	}

	statusLabel := lipgloss.NewStyle().
		Foreground(enabledColor).
		Render(enabledLabel)

	line := fmt.Sprintf("%s  %s  [%s]  %s",
		icon, name, src.Type, statusLabel,
	)

	if idx == m.selectedIdx {
		return theme.SelectedItemStyle.Render(line)
	}
	return theme.ListItemStyle.Render(line)
}

func (m Model) viewForm(f *huh.Form) string {
	if f == nil {
		return ""
	}

	content := f.View()

	return lipgloss.NewStyle().
		Padding(1, 2).
		Render(content)
}

func (m Model) viewValidating() string {
	style := lipgloss.NewStyle().
		Padding(1, 2).
		Width(m.width).
		Height(m.height)

	content := fmt.Sprintf(
		"%s Testing connection...\n\nPress esc to cancel.",
		m.spinner.View(),
	)

	return style.Render(content)
}

func (m Model) viewValidateResult() string {
	style := lipgloss.NewStyle().
		Padding(1, 2).
		Width(m.width).
		Height(m.height)

	var content string
	if m.validError != nil {
		errStyle := lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.ColorRed)
		content = errStyle.Render("Connection failed") + "\n\n" +
			m.validError.Error() + "\n\n" +
			lipgloss.NewStyle().Foreground(theme.ColorGray).
				Render("r retry | enter/esc back")
	} else {
		okStyle := lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.ColorGreen)
		displayName := m.validResult
		if displayName == "" {
			displayName = "OK"
		}
		content = okStyle.Render("Connection successful") + "\n\n" +
			fmt.Sprintf("Authenticated as: %s", displayName) + "\n\n" +
			lipgloss.NewStyle().Foreground(theme.ColorGray).
				Render("enter/esc back")
	}

	return style.Render(content)
}

// --- Helpers ---

// SetSize updates the view dimensions.
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

func (m *Model) resetFormFields() {
	m.fb.name = ""
	m.fb.baseURL = ""
	m.fb.token = ""
	m.fb.jql = ""
	m.fb.imapHost = ""
	m.fb.imapPort = ""
	m.fb.smtpHost = ""
	m.fb.smtpPort = ""
	m.fb.username = ""
	m.fb.password = ""
	m.fb.tls = true
}

func (m Model) startEditForm(src model.SourceConfig) tea.Cmd {
	m.fb.name = src.Name
	m.fb.baseURL = src.BaseURL
	m.fb.token = "" // Never pre-fill credentials

	if src.Config != nil {
		m.fb.jql = src.Config["jql"]
		m.fb.imapHost = src.Config["imap_host"]
		m.fb.imapPort = src.Config["imap_port"]
		m.fb.smtpHost = src.Config["smtp_host"]
		m.fb.smtpPort = src.Config["smtp_port"]
		m.fb.username = src.Config["username"]
		if src.Config["tls"] == "true" {
			m.fb.tls = true
		} else if src.Config["tls"] == "false" {
			m.fb.tls = false
		} else {
			m.fb.tls = true
		}
	}

	switch src.Type {
	case "jira":
		m.mode = ModeFormJira
		m.jiraForm = m.buildJiraForm()
		return m.jiraForm.Init()
	case "bitbucket":
		m.mode = ModeFormBitbucket
		m.bbForm = m.buildBBForm()
		return m.bbForm.Init()
	case "email":
		m.mode = ModeFormEmail
		m.emailForm = m.buildEmailForm()
		return m.emailForm.Init()
	default:
		return nil
	}
}

func (m Model) buildSourceConfig(sourceType string) model.SourceConfig {
	src := model.SourceConfig{
		Type:            sourceType,
		Name:            m.fb.name,
		BaseURL:         m.fb.baseURL,
		Enabled:         true,
		PollIntervalSec: 120,
		Config:          make(map[string]string),
	}

	if m.editingSource != nil {
		src.ID = m.editingSource.ID
	} else {
		src.ID = uuid.New().String()
	}

	return src
}

// loadSources returns a command that loads all sources from the store.
func (m Model) loadSources() tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		sources, err := s.GetSources(ctx)
		return sourcesLoadedMsg{sources: sources, err: err}
	}
}

// saveSource returns a command that persists a source to the store.
func (m Model) saveSource(src model.SourceConfig) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()
		err := s.UpsertSource(ctx, src)
		return sourceSavedInternalMsg{source: src, err: err}
	}
}

// deleteSource returns a command that removes a source and its credential.
func (m Model) deleteSource(src model.SourceConfig) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()

		// Remove credential from keyring
		credKey := src.Type + "-" + src.ID
		_ = credential.Delete(credKey) // Best-effort deletion

		err := s.DeleteSource(ctx, src.ID)
		return sourceDeletedInternalMsg{id: src.ID, err: err}
	}
}

// validateSource tests the connection for an existing source.
func (m Model) validateSource(src model.SourceConfig) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()

		adapter, err := m.createAdapter(src)
		if err != nil {
			return ValidateResultMsg{Err: err}
		}

		name, err := adapter.ValidateConnection(ctx)
		return ValidateResultMsg{Name: name, Err: err}
	}
}

// validateAndSave validates the connection then saves the source if successful.
func (m Model) validateAndSave(src model.SourceConfig) tea.Cmd {
	s := m.store
	return func() tea.Msg {
		ctx := context.Background()

		adapter, err := m.createAdapter(src)
		if err != nil {
			return ValidateResultMsg{Err: err}
		}

		name, err := adapter.ValidateConnection(ctx)
		if err != nil {
			return ValidateResultMsg{Name: name, Err: err}
		}

		// Validation passed; persist the source
		if saveErr := s.UpsertSource(ctx, src); saveErr != nil {
			return ValidateResultMsg{
				Name: name,
				Err:  fmt.Errorf("connection OK but save failed: %w", saveErr),
			}
		}

		return sourceSavedInternalMsg{source: src, err: nil}
	}
}

// createAdapter builds a source adapter based on the source configuration.
func (m Model) createAdapter(src model.SourceConfig) (source.Source, error) {
	switch src.Type {
	case "jira":
		token, err := credential.Get("jira-" + src.ID)
		if err != nil {
			return nil, fmt.Errorf("credential not found: %w", err)
		}
		jql := ""
		if src.Config != nil {
			jql = src.Config["jql"]
		}
		return jira.NewAdapter(src.BaseURL, token, src.ID, jql), nil

	case "bitbucket":
		token, err := credential.Get("bitbucket-" + src.ID)
		if err != nil {
			return nil, fmt.Errorf("credential not found: %w", err)
		}
		return bitbucket.NewAdapter(
			src.BaseURL, token, src.ID,
		), nil

	case "email":
		password, err := credential.Get("email-" + src.ID)
		if err != nil {
			return nil, fmt.Errorf("credential not found: %w", err)
		}
		cfg := src.Config
		if cfg == nil {
			return nil, fmt.Errorf("missing email config")
		}
		useTLS := cfg["tls"] != "false"
		return email.NewAdapter(
			cfg["imap_host"], cfg["imap_port"],
			cfg["smtp_host"], cfg["smtp_port"],
			cfg["username"], password,
			useTLS,
			src.ID,
		), nil

	default:
		return nil, fmt.Errorf(
			"validation not yet supported for %s sources", src.Type,
		)
	}
}

// sourceTypeIcon returns a text icon for a source type.
func sourceTypeIcon(sourceType string) string {
	switch sourceType {
	case "jira":
		return "[J]"
	case "bitbucket":
		return "[B]"
	case "email":
		return "[E]"
	default:
		return "[?]"
	}
}

// --- Validators ---

func validateRequired(fieldName string) func(string) error {
	return func(s string) error {
		if strings.TrimSpace(s) == "" {
			return fmt.Errorf("%s is required", fieldName)
		}
		return nil
	}
}

func validateURL(s string) error {
	if strings.TrimSpace(s) == "" {
		return fmt.Errorf("URL is required")
	}
	parsed, err := url.Parse(s)
	if err != nil {
		return fmt.Errorf("invalid URL: %w", err)
	}
	if parsed.Scheme == "" || parsed.Host == "" {
		return fmt.Errorf("URL must include scheme and host (e.g., https://example.com)")
	}
	return nil
}

func validatePort(s string) error {
	if strings.TrimSpace(s) == "" {
		return fmt.Errorf("port is required")
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return fmt.Errorf("port must be a number")
		}
	}
	return nil
}
