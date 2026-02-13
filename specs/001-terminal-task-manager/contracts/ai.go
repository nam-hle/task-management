// Package contracts/ai defines the AI assistant interface.
// The AI assistant is read-only: it can search and summarize but cannot
// execute write operations on any source.
//
// Provider: Anthropic Claude (via anthropic-sdk-go or go-anthropic)
// Model: Claude Sonnet 4.5 (or configurable)
package contracts

// AIAssistant defines the interface for the AI-powered search assistant.

// Key operations:
//
// Query:
//   Send a natural language query to the AI with context about available tasks.
//   The AI receives:
//   - System prompt defining its role (read-only task search assistant)
//   - Current task data summary (source types, counts, sample data)
//   - User's query
//   - Conversation history (for follow-up context)
//   Returns: AI response text + referenced task IDs
//
// StreamQuery:
//   Same as Query but returns a channel of token chunks for real-time display.
//   Each chunk contains partial text that should be appended to the response.
//   The Bubble Tea model receives these as messages via tea.Cmd.
//
// System prompt template:
//   "You are a read-only task search assistant for a terminal task manager.
//    You can search and summarize items from the user's connected sources
//    (Jira issues, Bitbucket pull requests, emails).
//    You CANNOT perform any write operations (status transitions, comments,
//    approvals, or modifications).
//    If asked to perform a write action, politely explain that you can only
//    search and summarize, and suggest the keyboard shortcut or action the
//    user can take manually.
//    Available data: {task_summary}
//    Respond concisely. Reference specific items by their source ID."
//
// Tool use pattern (for structured search):
//   The AI can use tool calling to search tasks:
//   - search_tasks(query, source_type?, status?, priority?)
//   - get_task_detail(task_id)
//   These tools query the local SQLite cache, not the external APIs directly.
//
// Conversation context:
//   Maintained in-memory as a list of {role, content} messages.
//   Reset when the user closes the AI panel.
//   Max context: last 20 messages (to stay within token limits).
//
// Error handling:
//   - API key missing/invalid: Show configuration prompt
//   - Network error: Show error, app continues to function
//   - Rate limit: Show "please wait" with retry timer
//   - Token limit exceeded: Truncate oldest messages from context
//
// Configuration:
//   - api_key: stored in system keychain (cred:claude-api-key)
//   - model: configurable (default: claude-sonnet-4-5-20250929)
//   - max_tokens: configurable (default: 1024)
