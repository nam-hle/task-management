package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/store"
)

const (
	defaultModel     = "claude-sonnet-4-5-20250929"
	defaultMaxTokens = 1024
	apiURL           = "https://api.anthropic.com/v1/messages"
	apiVersion       = "2023-06-01"
)

// StreamChunk represents a piece of the AI response being streamed back.
type StreamChunk struct {
	Text string
	Done bool
}

// Assistant is the AI assistant service that communicates with the Claude API,
// manages conversation context, and handles tool use for task queries.
type Assistant struct {
	apiKey    string
	store     store.Store
	context   *ConversationContext
	model     string
	maxTokens int
	client    *http.Client
}

// New creates a new AI assistant with the given configuration.
func New(
	apiKey string,
	s store.Store,
	modelName string,
	maxTokens int,
) *Assistant {
	if modelName == "" {
		modelName = defaultModel
	}
	if maxTokens <= 0 {
		maxTokens = defaultMaxTokens
	}

	return &Assistant{
		apiKey:    apiKey,
		store:     s,
		context:   NewConversationContext(),
		model:     modelName,
		maxTokens: maxTokens,
		client:    &http.Client{},
	}
}

// Reset clears the conversation history.
func (a *Assistant) Reset() {
	a.context.Reset()
}

// SendMessage sends a user message to the Claude API and returns a channel
// that receives response chunks. The channel is closed when the response
// is complete.
func (a *Assistant) SendMessage(
	ctx context.Context,
	userMsg string,
) (<-chan StreamChunk, error) {
	a.context.AddMessage(RoleUser, userMsg, nil)

	ch := make(chan StreamChunk, 16)

	go func() {
		defer close(ch)
		a.processMessage(ctx, ch)
	}()

	return ch, nil
}

// processMessage handles the API call loop, including tool use iterations.
func (a *Assistant) processMessage(ctx context.Context, ch chan<- StreamChunk) {
	maxToolIterations := 5

	for i := 0; i < maxToolIterations; i++ {
		resp, err := a.callAPI(ctx)
		if err != nil {
			ch <- StreamChunk{
				Text: fmt.Sprintf("Error: %v", err),
				Done: true,
			}
			return
		}

		// Process content blocks from the response
		var textParts []string
		var toolUseBlocks []apiToolUse
		hasToolUse := false

		for _, block := range resp.Content {
			switch block.Type {
			case "text":
				textParts = append(textParts, block.Text)
			case "tool_use":
				hasToolUse = true
				toolUseBlocks = append(toolUseBlocks, apiToolUse{
					ID:    block.ID,
					Name:  block.Name,
					Input: block.Input,
				})
			}
		}

		// Send any text content to the UI
		if len(textParts) > 0 {
			combined := strings.Join(textParts, "")
			ch <- StreamChunk{Text: combined, Done: !hasToolUse}

			if !hasToolUse {
				a.context.AddMessage(RoleAssistant, combined, nil)
				return
			}
		}

		if !hasToolUse {
			if len(textParts) == 0 {
				ch <- StreamChunk{Text: "", Done: true}
			}
			return
		}

		// Record the assistant's response (with tool use) in context
		assistantContent, err := json.Marshal(resp.Content)
		if err != nil {
			ch <- StreamChunk{
				Text: fmt.Sprintf("Error encoding response: %v", err),
				Done: true,
			}
			return
		}
		a.context.AddMessage(RoleAssistant, string(assistantContent), nil)

		// Process each tool use and build tool results
		var toolResults []apiContentBlock
		for _, tu := range toolUseBlocks {
			result := a.executeToolUse(ctx, tu)
			toolResults = append(toolResults, apiContentBlock{
				Type:      "tool_result",
				ToolUseID: tu.ID,
				Content:   result,
			})
		}

		// Add tool results as a user message
		toolResultsJSON, err := json.Marshal(toolResults)
		if err != nil {
			ch <- StreamChunk{
				Text: fmt.Sprintf("Error encoding tool results: %v", err),
				Done: true,
			}
			return
		}
		a.context.AddMessage(RoleUser, string(toolResultsJSON), nil)
	}

	ch <- StreamChunk{
		Text: "\n\n(Reached maximum tool use iterations)",
		Done: true,
	}
}

// callAPI makes a single request to the Claude Messages API.
func (a *Assistant) callAPI(ctx context.Context) (*apiResponse, error) {
	systemPrompt := a.buildSystemPrompt(ctx)
	messages := a.buildAPIMessages()

	reqBody := apiRequest{
		Model:     a.model,
		MaxTokens: a.maxTokens,
		System:    systemPrompt,
		Messages:  messages,
		Tools:     toolDefinitions(),
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshaling request: %w", err)
	}

	req, err := http.NewRequestWithContext(
		ctx, http.MethodPost, apiURL, bytes.NewReader(bodyBytes),
	)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", a.apiKey)
	req.Header.Set("anthropic-version", apiVersion)

	resp, err := a.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("calling Claude API: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		var apiErr apiErrorResponse
		if json.Unmarshal(respBody, &apiErr) == nil && apiErr.Error.Message != "" {
			return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, apiErr.Error.Message)
		}
		return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, string(respBody))
	}

	var result apiResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("decoding response: %w", err)
	}

	return &result, nil
}

// buildSystemPrompt constructs the system prompt with task context.
func (a *Assistant) buildSystemPrompt(ctx context.Context) string {
	var sb strings.Builder

	sb.WriteString("You are a task management assistant. ")
	sb.WriteString("You can search and summarize tasks from Jira, ")
	sb.WriteString("Bitbucket, and Email sources.\n\n")

	// Query task summary from store
	summary := a.buildTaskSummary(ctx)
	if summary != "" {
		sb.WriteString("Current task data:\n")
		sb.WriteString(summary)
		sb.WriteString("\n\n")
	}

	sb.WriteString("You have access to these tools:\n")
	sb.WriteString("- search_tasks: Search tasks by query text, source type, ")
	sb.WriteString("status, or priority\n")
	sb.WriteString("- get_task_detail: Get full details for a specific task ")
	sb.WriteString("by its ID\n\n")

	sb.WriteString("IMPORTANT: You CANNOT perform write operations ")
	sb.WriteString("(status transitions, comments, approvals, or modifications). ")
	sb.WriteString("If asked to perform a write action, politely explain that ")
	sb.WriteString("you can only search and summarize, and suggest the keyboard ")
	sb.WriteString("shortcut the user can use instead:\n")
	sb.WriteString("- Press 't' in the detail view to transition status\n")
	sb.WriteString("- Press 'c' in the detail view to add a comment\n")
	sb.WriteString("- Press 'p' in the detail view to approve\n\n")

	sb.WriteString("When referencing tasks, include their source item ID ")
	sb.WriteString("and title. Keep responses concise and focused.")

	return sb.String()
}

// buildTaskSummary queries the store for task counts by source and status.
func (a *Assistant) buildTaskSummary(ctx context.Context) string {
	tasks, err := a.store.GetTasks(ctx, store.TaskFilter{
		SortBy:   "updated_at",
		SortDesc: true,
		Limit:    500,
	})
	if err != nil || len(tasks) == 0 {
		return "No tasks available."
	}

	sourceCounts := make(map[model.SourceType]int)
	statusCounts := make(map[string]int)

	for _, t := range tasks {
		sourceCounts[t.SourceType]++
		statusCounts[t.Status]++
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Total tasks: %d\n", len(tasks)))

	sb.WriteString("By source: ")
	first := true
	for src, count := range sourceCounts {
		if !first {
			sb.WriteString(", ")
		}
		sb.WriteString(fmt.Sprintf("%s=%d", src, count))
		first = false
	}
	sb.WriteString("\n")

	sb.WriteString("By status: ")
	first = true
	for status, count := range statusCounts {
		if !first {
			sb.WriteString(", ")
		}
		sb.WriteString(fmt.Sprintf("%s=%d", status, count))
		first = false
	}

	return sb.String()
}

// buildAPIMessages converts the conversation context into the Claude API
// message format. Messages with JSON content blocks (from tool use) are
// sent as structured content; plain text messages are sent as-is.
func (a *Assistant) buildAPIMessages() []apiMessage {
	contextMsgs := a.context.GetMessages()
	var messages []apiMessage

	for _, msg := range contextMsgs {
		// Check if this is a structured content message (tool use/results)
		if isJSONArray(msg.Content) {
			var blocks []apiContentBlock
			if err := json.Unmarshal(
				[]byte(msg.Content), &blocks,
			); err == nil {
				messages = append(messages, apiMessage{
					Role:    string(msg.Role),
					Content: blocks,
				})
				continue
			}
		}

		messages = append(messages, apiMessage{
			Role: string(msg.Role),
			Content: []apiContentBlock{
				{Type: "text", Text: msg.Content},
			},
		})
	}

	return messages
}

// executeToolUse runs a tool requested by the AI and returns the result.
func (a *Assistant) executeToolUse(
	ctx context.Context,
	tu apiToolUse,
) string {
	// Read-only guard: reject any write-like tool names
	writeTools := map[string]bool{
		"transition_task": true,
		"add_comment":     true,
		"approve_task":    true,
		"update_task":     true,
		"delete_task":     true,
	}
	if writeTools[tu.Name] {
		return `{"error": "Write operations are not permitted. ` +
			`Please use the keyboard shortcuts instead: ` +
			`'t' for transitions, 'c' for comments, 'p' for approvals."}`
	}

	switch tu.Name {
	case "search_tasks":
		return a.handleSearchTasks(ctx, tu.Input)
	case "get_task_detail":
		return a.handleGetTaskDetail(ctx, tu.Input)
	default:
		return fmt.Sprintf(
			`{"error": "Unknown tool: %s"}`, tu.Name,
		)
	}
}

// handleSearchTasks queries the store with the provided search parameters.
func (a *Assistant) handleSearchTasks(
	ctx context.Context,
	input json.RawMessage,
) string {
	var params struct {
		Query      string `json:"query"`
		SourceType string `json:"source_type"`
		Status     string `json:"status"`
		Priority   *int   `json:"priority"`
	}

	if err := json.Unmarshal(input, &params); err != nil {
		return fmt.Sprintf(`{"error": "Invalid parameters: %v"}`, err)
	}

	filter := store.TaskFilter{
		SortBy:   "updated_at",
		SortDesc: true,
		Limit:    20,
	}

	if params.Query != "" {
		filter.Query = &params.Query
	}
	if params.SourceType != "" {
		filter.SourceType = &params.SourceType
	}
	if params.Status != "" {
		filter.Status = &params.Status
	}
	if params.Priority != nil {
		filter.Priority = params.Priority
	}

	tasks, err := a.store.GetTasks(ctx, filter)
	if err != nil {
		return fmt.Sprintf(`{"error": "Search failed: %v"}`, err)
	}

	type taskSummary struct {
		ID           string `json:"id"`
		SourceType   string `json:"source_type"`
		SourceItemID string `json:"source_item_id"`
		Title        string `json:"title"`
		Status       string `json:"status"`
		Priority     int    `json:"priority"`
		Assignee     string `json:"assignee"`
		UpdatedAt    string `json:"updated_at"`
	}

	summaries := make([]taskSummary, 0, len(tasks))
	for _, t := range tasks {
		summaries = append(summaries, taskSummary{
			ID:           t.ID,
			SourceType:   string(t.SourceType),
			SourceItemID: t.SourceItemID,
			Title:        t.Title,
			Status:       t.Status,
			Priority:     t.Priority,
			Assignee:     t.Assignee,
			UpdatedAt:    t.UpdatedAt.Format("2006-01-02 15:04"),
		})
	}

	result, err := json.Marshal(map[string]interface{}{
		"count": len(summaries),
		"tasks": summaries,
	})
	if err != nil {
		return fmt.Sprintf(`{"error": "Failed to encode results: %v"}`, err)
	}

	return string(result)
}

// handleGetTaskDetail retrieves full details for a specific task.
func (a *Assistant) handleGetTaskDetail(
	ctx context.Context,
	input json.RawMessage,
) string {
	var params struct {
		TaskID string `json:"task_id"`
	}

	if err := json.Unmarshal(input, &params); err != nil {
		return fmt.Sprintf(`{"error": "Invalid parameters: %v"}`, err)
	}

	if params.TaskID == "" {
		return `{"error": "task_id is required"}`
	}

	task, err := a.store.GetTaskByID(ctx, params.TaskID)
	if err != nil {
		return fmt.Sprintf(`{"error": "Task not found: %v"}`, err)
	}
	if task == nil {
		return `{"error": "Task not found"}`
	}

	type taskDetail struct {
		ID           string   `json:"id"`
		SourceType   string   `json:"source_type"`
		SourceItemID string   `json:"source_item_id"`
		Title        string   `json:"title"`
		Description  string   `json:"description"`
		Status       string   `json:"status"`
		Priority     int      `json:"priority"`
		Assignee     string   `json:"assignee"`
		Author       string   `json:"author"`
		SourceURL    string   `json:"source_url"`
		CreatedAt    string   `json:"created_at"`
		UpdatedAt    string   `json:"updated_at"`
		CrossRefs    []string `json:"cross_refs,omitempty"`
	}

	detail := taskDetail{
		ID:           task.ID,
		SourceType:   string(task.SourceType),
		SourceItemID: task.SourceItemID,
		Title:        task.Title,
		Description:  task.Description,
		Status:       task.Status,
		Priority:     task.Priority,
		Assignee:     task.Assignee,
		Author:       task.Author,
		SourceURL:    task.SourceURL,
		CreatedAt:    task.CreatedAt.Format("2006-01-02 15:04"),
		UpdatedAt:    task.UpdatedAt.Format("2006-01-02 15:04"),
		CrossRefs:    task.CrossRefs,
	}

	result, err := json.Marshal(detail)
	if err != nil {
		return fmt.Sprintf(`{"error": "Failed to encode task: %v"}`, err)
	}

	return string(result)
}

// isJSONArray returns true if the string starts with '['.
func isJSONArray(s string) bool {
	trimmed := strings.TrimSpace(s)
	return len(trimmed) > 0 && trimmed[0] == '['
}

// --- Claude API types ---

type apiRequest struct {
	Model     string       `json:"model"`
	MaxTokens int          `json:"max_tokens"`
	System    string       `json:"system"`
	Messages  []apiMessage `json:"messages"`
	Tools     []apiTool    `json:"tools,omitempty"`
}

type apiMessage struct {
	Role    string            `json:"role"`
	Content []apiContentBlock `json:"content"`
}

type apiContentBlock struct {
	// Common fields
	Type string `json:"type"`

	// For text blocks
	Text string `json:"text,omitempty"`

	// For tool_use blocks
	ID    string          `json:"id,omitempty"`
	Name  string          `json:"name,omitempty"`
	Input json.RawMessage `json:"input,omitempty"`

	// For tool_result blocks
	ToolUseID string `json:"tool_use_id,omitempty"`
	Content   string `json:"content,omitempty"`
}

type apiToolUse struct {
	ID    string
	Name  string
	Input json.RawMessage
}

type apiResponse struct {
	ID      string            `json:"id"`
	Type    string            `json:"type"`
	Role    string            `json:"role"`
	Content []apiContentBlock `json:"content"`
	Model   string            `json:"model"`
	StopReason string         `json:"stop_reason"`
}

type apiErrorResponse struct {
	Error struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}

type apiTool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	InputSchema json.RawMessage `json:"input_schema"`
}

// toolDefinitions returns the tool specifications for the Claude API.
func toolDefinitions() []apiTool {
	return []apiTool{
		{
			Name: "search_tasks",
			Description: "Search tasks from Jira, Bitbucket, and Email " +
				"sources. Returns matching tasks with their key details.",
			InputSchema: json.RawMessage(`{
				"type": "object",
				"properties": {
					"query": {
						"type": "string",
						"description": "Search query to match against task titles and descriptions"
					},
					"source_type": {
						"type": "string",
						"enum": ["jira", "bitbucket", "email"],
						"description": "Filter by source type"
					},
					"status": {
						"type": "string",
						"enum": ["open", "in_progress", "review", "done"],
						"description": "Filter by task status"
					},
					"priority": {
						"type": "integer",
						"minimum": 1,
						"maximum": 5,
						"description": "Filter by priority (1=Critical, 2=High, 3=Medium, 4=Low, 5=Lowest)"
					}
				}
			}`),
		},
		{
			Name:        "get_task_detail",
			Description: "Get full details for a specific task by its ID.",
			InputSchema: json.RawMessage(`{
				"type": "object",
				"properties": {
					"task_id": {
						"type": "string",
						"description": "The unique task ID"
					}
				},
				"required": ["task_id"]
			}`),
		},
	}
}
