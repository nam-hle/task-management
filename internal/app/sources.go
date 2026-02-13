package app

import (
	"context"
	"log"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nhle/task-management/internal/credential"
	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source/jira"
)

// sourcesRegisteredMsg is sent when all configured sources have been
// registered with the poller.
type sourcesRegisteredMsg struct {
	count int
}

// registerSources queries the store for configured sources and registers
// each enabled Jira source with the poller. Credentials are loaded from
// the system keyring.
func (m *Model) registerSources() tea.Cmd {
	s := m.store
	p := m.poller

	return func() tea.Msg {
		ctx := context.Background()

		sources, err := s.GetSources(ctx)
		if err != nil {
			log.Printf("failed to load sources: %v", err)
			return sourcesRegisteredMsg{count: 0}
		}

		registered := 0
		for _, src := range sources {
			if !src.Enabled {
				continue
			}

			switch src.Type {
			case string(model.SourceTypeJira):
				adapter := createJiraAdapter(src)
				if adapter == nil {
					continue
				}
				p.RegisterSource(adapter, src)
				registered++
			}
		}

		return sourcesRegisteredMsg{count: registered}
	}
}

// createJiraAdapter builds a Jira adapter from a source configuration,
// loading the PAT from the system keyring.
func createJiraAdapter(src model.SourceConfig) *jira.Adapter {
	token, err := credential.Get("jira-" + src.ID)
	if err != nil {
		log.Printf(
			"skipping Jira source %q (%s): credential not found: %v",
			src.Name, src.ID, err,
		)
		return nil
	}

	jql := ""
	if src.Config != nil {
		jql = src.Config["jql"]
	}

	return jira.NewAdapter(src.BaseURL, token, src.ID, jql)
}
