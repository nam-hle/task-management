package sync

import (
	"context"
	"fmt"
	gosync "sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source"
	"github.com/nhle/task-management/internal/store"
)

// SyncState represents the current state of a source sync operation.
type SyncState int

const (
	SyncIdle    SyncState = iota
	SyncRunning
	SyncError
)

// SyncStatus holds the sync state for a single source.
type SyncStatus struct {
	SourceType model.SourceType
	State      SyncState
	LastSync   time.Time
	Error      error
}

// SyncResultMsg is a tea.Msg sent when a sync operation completes.
type SyncResultMsg struct {
	Tasks        []model.Task
	Source       model.SourceType
	Error        error
	AuthError    *AuthErrorMsg
	NewTaskCount int
}

// SyncStatusMsg is a tea.Msg with the current statuses of all sources.
type SyncStatusMsg struct {
	Statuses []SyncStatus
}

// AuthErrorMsg is a tea.Msg sent when a source returns an authentication error.
type AuthErrorMsg struct {
	SourceType model.SourceType
	Message    string
}

// NewTasksMsg is a tea.Msg sent when new tasks are detected during sync.
type NewTasksMsg struct {
	Count int
}

// fetchTimeout is the maximum time allowed for a single fetch operation.
const fetchTimeout = 30 * time.Second

// sourceEntry holds a registered source and its configuration.
type sourceEntry struct {
	src source.Source
	cfg model.SourceConfig
}

// Poller orchestrates background polling of registered sources.
type Poller struct {
	store         store.Store
	sources       []sourceEntry
	statuses      map[model.SourceType]*SyncStatus
	resultCh      chan SyncResultMsg
	triggerCh     chan model.SourceType
	stopCh        chan struct{}
	mu            gosync.Mutex
	running       bool
}

// New creates a new Poller with the given store.
func New(s store.Store) *Poller {
	return &Poller{
		store:    s,
		statuses: make(map[model.SourceType]*SyncStatus),
		resultCh: make(chan SyncResultMsg, 16),
		triggerCh: make(chan model.SourceType, 16),
		stopCh:   make(chan struct{}),
	}
}

// RegisterSource adds a source adapter and its configuration to the poller.
func (p *Poller) RegisterSource(src source.Source, cfg model.SourceConfig) {
	p.mu.Lock()
	defer p.mu.Unlock()

	st := model.SourceType(cfg.Type)
	p.sources = append(p.sources, sourceEntry{src: src, cfg: cfg})
	p.statuses[st] = &SyncStatus{
		SourceType: st,
		State:      SyncIdle,
	}
}

// Start returns a tea.Cmd that starts all polling goroutines and
// subscribes to results. The returned command waits on the result
// channel and returns SyncResultMsg messages to the Bubble Tea runtime.
func (p *Poller) Start() tea.Cmd {
	p.mu.Lock()
	if p.running {
		p.mu.Unlock()
		return nil
	}
	p.running = true
	p.mu.Unlock()

	// Start a polling goroutine for each source
	for _, entry := range p.sources {
		go p.pollSource(entry)
	}

	// Return a subscription command that listens for results
	return p.waitForResult()
}

// Stop halts all polling goroutines.
func (p *Poller) Stop() {
	p.mu.Lock()
	defer p.mu.Unlock()

	if !p.running {
		return
	}

	close(p.stopCh)
	p.running = false
}

// RefreshAll triggers an immediate poll of all registered sources.
func (p *Poller) RefreshAll() tea.Cmd {
	p.mu.Lock()
	sources := make([]sourceEntry, len(p.sources))
	copy(sources, p.sources)
	p.mu.Unlock()

	for _, entry := range sources {
		select {
		case p.triggerCh <- model.SourceType(entry.cfg.Type):
		default:
			// Channel full; skip to avoid blocking
		}
	}

	return nil
}

// RefreshSource triggers an immediate poll of a single source type.
func (p *Poller) RefreshSource(sourceType model.SourceType) tea.Cmd {
	select {
	case p.triggerCh <- sourceType:
	default:
	}
	return nil
}

// GetStatuses returns the current sync status of all registered sources.
func (p *Poller) GetStatuses() []SyncStatus {
	p.mu.Lock()
	defer p.mu.Unlock()

	statuses := make([]SyncStatus, 0, len(p.statuses))
	for _, s := range p.statuses {
		statuses = append(statuses, *s)
	}
	return statuses
}

// pollSource runs the polling loop for a single source.
func (p *Poller) pollSource(entry sourceEntry) {
	interval := time.Duration(entry.cfg.PollIntervalSec) * time.Second
	if interval <= 0 {
		interval = 120 * time.Second
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	st := model.SourceType(entry.cfg.Type)

	// Do an initial fetch immediately
	p.fetchAndUpsert(entry, st)

	for {
		select {
		case <-p.stopCh:
			return
		case <-ticker.C:
			p.fetchAndUpsert(entry, st)
		case triggerType := <-p.triggerCh:
			if triggerType == st {
				p.fetchAndUpsert(entry, st)
			}
		}
	}
}

// fetchAndUpsert performs a single fetch operation, upserts results to the
// store, and sends a SyncResultMsg on the result channel.
func (p *Poller) fetchAndUpsert(entry sourceEntry, st model.SourceType) {
	p.setStatus(st, SyncRunning, nil)

	ctx, cancel := context.WithTimeout(context.Background(), fetchTimeout)
	defer cancel()

	result, err := entry.src.FetchItems(ctx, source.FetchOptions{
		Page:     1,
		PageSize: 50,
	})

	if err != nil {
		p.setStatus(st, SyncError, err)

		// Detect auth errors and emit a specific message.
		if source.IsAuthError(err) {
			p.sendResult(SyncResultMsg{
				Source: st,
				Error:  err,
				AuthError: &AuthErrorMsg{
					SourceType: st,
					Message: fmt.Sprintf(
						"%s: authentication expired. Press 'c' to reconfigure.",
						st,
					),
				},
			})
			return
		}

		p.sendResult(SyncResultMsg{Source: st, Error: err})
		return
	}

	tasks := result.Items

	// Detect new tasks by checking which ones don't exist in the store yet.
	var newTaskIDs map[string]bool
	if len(tasks) > 0 {
		existingTasks, _ := p.store.GetTasks(ctx, store.TaskFilter{
			Limit: 1000,
		})
		existingIDs := make(map[string]bool, len(existingTasks))
		for _, t := range existingTasks {
			existingIDs[t.ID] = true
		}
		newTaskIDs = make(map[string]bool)
		for _, t := range tasks {
			if !existingIDs[t.ID] {
				newTaskIDs[t.ID] = true
			}
		}
	}

	if len(tasks) > 0 {
		if upsertErr := p.store.UpsertTasks(ctx, tasks); upsertErr != nil {
			p.setStatus(st, SyncError, upsertErr)
			p.sendResult(SyncResultMsg{Source: st, Error: upsertErr})
			return
		}
	}

	// Create notifications for new tasks only.
	newTaskCount := len(newTaskIDs)
	if newTaskCount > 0 {
		for _, t := range tasks {
			if !newTaskIDs[t.ID] {
				continue
			}
			notification := model.Notification{
				TaskID:     t.ID,
				SourceType: model.SourceType(st),
				Message:    fmt.Sprintf("New %s item: %s", st, t.Title),
				CreatedAt:  time.Now(),
			}
			_ = p.store.CreateNotification(ctx, notification)
		}
	}

	p.setStatus(st, SyncIdle, nil)
	p.sendResult(SyncResultMsg{
		Tasks:        tasks,
		Source:       st,
		NewTaskCount: newTaskCount,
	})
}

// setStatus updates the sync status for a source type.
func (p *Poller) setStatus(st model.SourceType, state SyncState, err error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	status, ok := p.statuses[st]
	if !ok {
		return
	}

	status.State = state
	status.Error = err
	if state == SyncIdle && err == nil {
		status.LastSync = time.Now()
	}
}

// sendResult sends a SyncResultMsg on the result channel without blocking.
func (p *Poller) sendResult(msg SyncResultMsg) {
	select {
	case p.resultCh <- msg:
	default:
		// Drop if channel is full to avoid blocking the poller
	}
}

// waitForResult returns a tea.Cmd that waits for the next result from
// the result channel. After receiving a result, it returns both the
// result message and a new waitForResult command to keep listening.
func (p *Poller) waitForResult() tea.Cmd {
	return func() tea.Msg {
		result, ok := <-p.resultCh
		if !ok {
			return nil
		}
		return result
	}
}

// WaitForNextResult returns a tea.Cmd that waits for the next sync result.
// This should be called after processing a SyncResultMsg to continue
// listening for future results.
func (p *Poller) WaitForNextResult() tea.Cmd {
	return p.waitForResult()
}
