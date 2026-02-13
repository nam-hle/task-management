package email

import "time"

// Envelope holds the parsed envelope data from an IMAP message.
type Envelope struct {
	MessageID string
	Subject   string
	From      string
	To        []string
	Date      time.Time
	Flags     []string // \Seen, \Flagged, \Answered, \Deleted
	UID       uint32
}

// ParsedMessage holds the full parsed content of an email message.
type ParsedMessage struct {
	Envelope    Envelope
	TextBody    string
	HTMLBody    string
	Attachments []Attachment
}

// Attachment holds metadata about a message attachment.
type Attachment struct {
	Filename string
	Size     int64
	MIMEType string
}

// SMTPConfig holds the SMTP server settings for sending replies.
type SMTPConfig struct {
	Host     string
	Port     string
	Username string
	Password string
	TLS      bool
}
