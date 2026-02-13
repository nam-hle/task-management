package ai

import "sync"

// Role identifies the sender of a conversation message.
type Role string

const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

// Message represents a single message in the conversation history.
type Message struct {
	Role     Role
	Content  string
	TaskRefs []string // task IDs referenced in this message
}

// ConversationContext maintains an ordered history of conversation messages,
// automatically trimming the oldest entries when the limit is reached.
type ConversationContext struct {
	mu          sync.Mutex
	messages    []Message
	maxMessages int
}

// NewConversationContext creates a new conversation context with a default
// maximum of 20 messages.
func NewConversationContext() *ConversationContext {
	return &ConversationContext{
		messages:    make([]Message, 0, 20),
		maxMessages: 20,
	}
}

// AddMessage appends a message to the conversation history. If the number
// of messages exceeds maxMessages, the oldest messages are trimmed while
// keeping the first message (which serves as initial context).
func (c *ConversationContext) AddMessage(
	role Role,
	content string,
	taskRefs []string,
) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.messages = append(c.messages, Message{
		Role:     role,
		Content:  content,
		TaskRefs: taskRefs,
	})

	if len(c.messages) > c.maxMessages {
		// Keep the first message (initial context) and trim from the middle.
		trimmed := make([]Message, 0, c.maxMessages)
		trimmed = append(trimmed, c.messages[0])
		excess := len(c.messages) - c.maxMessages
		trimmed = append(trimmed, c.messages[1+excess:]...)
		c.messages = trimmed
	}
}

// GetMessages returns a copy of the current conversation messages.
func (c *ConversationContext) GetMessages() []Message {
	c.mu.Lock()
	defer c.mu.Unlock()

	result := make([]Message, len(c.messages))
	copy(result, c.messages)
	return result
}

// Reset clears all messages from the conversation context.
func (c *ConversationContext) Reset() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.messages = c.messages[:0]
}

// Len returns the number of messages in the conversation context.
func (c *ConversationContext) Len() int {
	c.mu.Lock()
	defer c.mu.Unlock()

	return len(c.messages)
}
