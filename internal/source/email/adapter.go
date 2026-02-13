package email

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net"
	"net/smtp"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/emersion/go-imap/v2"

	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source"
)

// Adapter implements source.Source for Email (IMAP/SMTP).
type Adapter struct {
	imapClient *IMAPClient
	smtpConfig SMTPConfig
	sourceID   string
	username   string
}

// NewAdapter creates a new email source adapter.
func NewAdapter(
	imapHost, imapPort string,
	smtpHost, smtpPort string,
	username, password string,
	useTLS bool,
	sourceID string,
) *Adapter {
	return &Adapter{
		imapClient: NewIMAPClient(
			imapHost, imapPort, username, password, useTLS,
		),
		smtpConfig: SMTPConfig{
			Host:     smtpHost,
			Port:     smtpPort,
			Username: username,
			Password: password,
			TLS:      useTLS,
		},
		sourceID: sourceID,
		username: username,
	}
}

// Type returns the source type identifier for Email.
func (a *Adapter) Type() source.SourceType {
	return source.SourceTypeEmail
}

// ValidateConnection verifies IMAP credentials by connecting,
// authenticating, and selecting INBOX. Returns the username on success.
func (a *Adapter) ValidateConnection(
	ctx context.Context,
) (string, error) {
	client, err := a.imapClient.Connect(ctx)
	if err != nil {
		return "", fmt.Errorf("validating email connection: %w", err)
	}
	defer func() { _ = client.Logout().Wait() }()

	if _, err := client.Select("INBOX", nil).Wait(); err != nil {
		return "", fmt.Errorf("selecting INBOX: %w", err)
	}

	return a.username, nil
}

// FetchItems retrieves recent messages from the IMAP inbox and maps
// them to model.Task items.
func (a *Adapter) FetchItems(
	ctx context.Context,
	opts source.FetchOptions,
) (*source.FetchResult, error) {
	pageSize := opts.PageSize
	if pageSize < 1 {
		pageSize = 50
	}

	envelopes, err := a.imapClient.FetchEnvelopes(ctx, 100)
	if err != nil {
		return nil, fmt.Errorf("fetching email items: %w", err)
	}

	tasks := make([]model.Task, 0, len(envelopes))
	for _, env := range envelopes {
		tasks = append(tasks, a.envelopeToTask(env))
	}

	// Apply simple pagination
	page := opts.Page
	if page < 1 {
		page = 1
	}
	start := (page - 1) * pageSize
	if start >= len(tasks) {
		return &source.FetchResult{
			Items:   nil,
			Total:   len(tasks),
			HasMore: false,
		}, nil
	}

	end := start + pageSize
	hasMore := false
	if end < len(tasks) {
		hasMore = true
	} else {
		end = len(tasks)
	}

	return &source.FetchResult{
		Items:   tasks[start:end],
		Total:   len(tasks),
		HasMore: hasMore,
	}, nil
}

// GetItemDetail retrieves the full message body for a given UID and
// returns it as an ItemDetail.
func (a *Adapter) GetItemDetail(
	ctx context.Context,
	sourceItemID string,
) (*source.ItemDetail, error) {
	uid, err := parseUID(sourceItemID)
	if err != nil {
		return nil, err
	}

	parsed, err := a.imapClient.FetchMessage(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf(
			"fetching email detail %s: %w", sourceItemID, err,
		)
	}

	task := a.envelopeToTask(parsed.Envelope)

	// Prefer plain text body; fall back to stripped HTML
	renderedBody := parsed.TextBody
	if renderedBody == "" && parsed.HTMLBody != "" {
		renderedBody = stripHTML(parsed.HTMLBody)
	}

	metadata := make(map[string]string)
	if parsed.Envelope.MessageID != "" {
		metadata["Message-ID"] = parsed.Envelope.MessageID
	}
	if len(parsed.Envelope.To) > 0 {
		metadata["To"] = strings.Join(parsed.Envelope.To, ", ")
	}
	if len(parsed.Envelope.Flags) > 0 {
		metadata["Flags"] = strings.Join(parsed.Envelope.Flags, ", ")
	}

	// List attachments in metadata
	if len(parsed.Attachments) > 0 {
		var parts []string
		for _, att := range parsed.Attachments {
			parts = append(parts, fmt.Sprintf(
				"%s (%s, %s)",
				att.Filename, att.MIMEType, formatSize(att.Size),
			))
		}
		metadata["Attachments"] = strings.Join(parts, "; ")
	}

	return &source.ItemDetail{
		Task:         task,
		RenderedBody: renderedBody,
		Metadata:     metadata,
	}, nil
}

// GetActions returns the available actions for an email message.
func (a *Adapter) GetActions(
	_ context.Context,
	_ string,
) ([]source.Action, error) {
	return []source.Action{
		{
			ID:            "reply",
			Name:          "Reply",
			RequiresInput: true,
			InputPrompt:   "Enter reply text:",
		},
		{
			ID:   "archive",
			Name: "Archive",
		},
		{
			ID:   "flag",
			Name: "Flag",
		},
		{
			ID:   "unflag",
			Name: "Unflag",
		},
		{
			ID:   "mark_read",
			Name: "Mark Read",
		},
		{
			ID:   "mark_unread",
			Name: "Mark Unread",
		},
	}, nil
}

// ExecuteAction performs an action on an email message.
func (a *Adapter) ExecuteAction(
	ctx context.Context,
	sourceItemID string,
	action source.Action,
	input string,
) error {
	uid, err := parseUID(sourceItemID)
	if err != nil {
		return err
	}

	switch action.ID {
	case "reply":
		return a.handleReply(ctx, uid, input)
	case "archive":
		return a.imapClient.MoveToArchive(ctx, uid)
	case "flag":
		return a.imapClient.SetFlags(
			ctx, uid, []imap.Flag{imap.FlagFlagged}, true,
		)
	case "unflag":
		return a.imapClient.SetFlags(
			ctx, uid, []imap.Flag{imap.FlagFlagged}, false,
		)
	case "mark_read":
		return a.imapClient.SetFlags(
			ctx, uid, []imap.Flag{imap.FlagSeen}, true,
		)
	case "mark_unread":
		return a.imapClient.SetFlags(
			ctx, uid, []imap.Flag{imap.FlagSeen}, false,
		)
	default:
		return fmt.Errorf(
			"unknown action %q for email %s", action.ID, sourceItemID,
		)
	}
}

// Search uses IMAP SEARCH with text matching to find messages.
func (a *Adapter) Search(
	ctx context.Context,
	query string,
	opts source.FetchOptions,
) (*source.FetchResult, error) {
	if strings.TrimSpace(query) == "" {
		return &source.FetchResult{}, nil
	}

	client, err := a.imapClient.Connect(ctx)
	if err != nil {
		return nil, fmt.Errorf("searching emails: %w", err)
	}
	defer func() { _ = client.Logout().Wait() }()

	if _, err := client.Select("INBOX", nil).Wait(); err != nil {
		return nil, fmt.Errorf("selecting INBOX for search: %w", err)
	}

	criteria := &imap.SearchCriteria{
		Text: []string{query},
	}

	searchData, err := client.UIDSearch(criteria, nil).Wait()
	if err != nil {
		return &source.FetchResult{}, nil
	}

	uids := searchData.AllUIDs()
	if len(uids) == 0 {
		return &source.FetchResult{}, nil
	}

	// Limit results
	pageSize := opts.PageSize
	if pageSize < 1 {
		pageSize = 50
	}
	if len(uids) > pageSize {
		uids = uids[len(uids)-pageSize:]
	}

	uidSet := imap.UIDSetNum(uids...)
	fetchOpts := &imap.FetchOptions{
		Envelope: true,
		Flags:    true,
		UID:      true,
	}

	fetchCmd := client.Fetch(uidSet, fetchOpts)
	defer fetchCmd.Close()

	var tasks []model.Task
	for {
		msg := fetchCmd.Next()
		if msg == nil {
			break
		}
		buf, err := msg.Collect()
		if err != nil {
			continue
		}
		env := envelopeFromBuffer(buf)
		tasks = append(tasks, a.envelopeToTask(env))
	}

	if err := fetchCmd.Close(); err != nil {
		return nil, fmt.Errorf("closing search fetch: %w", err)
	}

	return &source.FetchResult{
		Items:   tasks,
		Total:   len(tasks),
		HasMore: false,
	}, nil
}

// handleReply fetches the original message and sends a reply via SMTP.
func (a *Adapter) handleReply(
	ctx context.Context, uid uint32, replyBody string,
) error {
	parsed, err := a.imapClient.FetchMessage(ctx, uid)
	if err != nil {
		return fmt.Errorf("fetching message for reply: %w", err)
	}

	if err := sendReply(a.smtpConfig, parsed, replyBody); err != nil {
		return fmt.Errorf("sending reply: %w", err)
	}

	// Mark as answered
	return a.imapClient.SetFlags(
		ctx, uid, []imap.Flag{imap.FlagAnswered}, true,
	)
}

// envelopeToTask converts an Envelope to a model.Task.
func (a *Adapter) envelopeToTask(env Envelope) model.Task {
	rawData, _ := json.Marshal(env)

	status := model.StatusOpen
	priority := model.PriorityMedium

	hasSeen := false
	hasFlagged := false
	for _, flag := range env.Flags {
		switch flag {
		case `\Seen`:
			hasSeen = true
		case `\Flagged`:
			hasFlagged = true
		}
	}

	if hasSeen {
		status = model.StatusInProgress
		priority = model.PriorityLowest
	}

	if hasFlagged && !hasSeen {
		priority = model.PriorityHigh
	} else if !hasSeen {
		priority = model.PriorityMedium
	}

	// Sanitize MessageID for use in task ID
	taskID := "email-" + sanitizeID(env.MessageID)
	if env.MessageID == "" {
		taskID = fmt.Sprintf("email-uid-%d", env.UID)
	}

	sourceItemID := strconv.FormatUint(uint64(env.UID), 10)

	return model.Task{
		ID:           taskID,
		SourceType:   model.SourceTypeEmail,
		SourceItemID: sourceItemID,
		SourceID:     a.sourceID,
		Title:        env.Subject,
		Author:       env.From,
		Status:       status,
		Priority:     priority,
		SourceURL:    "",
		CreatedAt:    env.Date,
		UpdatedAt:    env.Date,
		FetchedAt:    time.Now(),
		RawData:      string(rawData),
	}
}

// sendReply composes and sends a reply via SMTP.
func sendReply(
	cfg SMTPConfig, originalMsg *ParsedMessage, replyBody string,
) error {
	from := cfg.Username
	to := originalMsg.Envelope.From

	subject := originalMsg.Envelope.Subject
	if !strings.HasPrefix(strings.ToLower(subject), "re:") {
		subject = "Re: " + subject
	}

	// Compose the message
	var msg strings.Builder
	msg.WriteString(fmt.Sprintf("From: %s\r\n", from))
	msg.WriteString(fmt.Sprintf("To: %s\r\n", to))
	msg.WriteString(fmt.Sprintf("Subject: %s\r\n", subject))
	if originalMsg.Envelope.MessageID != "" {
		msg.WriteString(fmt.Sprintf(
			"In-Reply-To: <%s>\r\n",
			originalMsg.Envelope.MessageID,
		))
		msg.WriteString(fmt.Sprintf(
			"References: <%s>\r\n",
			originalMsg.Envelope.MessageID,
		))
	}
	msg.WriteString(
		"Content-Type: text/plain; charset=UTF-8\r\n",
	)
	msg.WriteString("\r\n")
	msg.WriteString(replyBody)

	addr := cfg.Host + ":" + cfg.Port

	if cfg.TLS {
		return sendSMTPWithTLS(addr, cfg, from, to, msg.String())
	}

	return sendSMTPWithStartTLS(addr, cfg, from, to, msg.String())
}

// sendSMTPWithTLS sends an email over an implicit TLS connection.
func sendSMTPWithTLS(
	addr string, cfg SMTPConfig,
	from, to, body string,
) error {
	tlsConfig := &tls.Config{ServerName: cfg.Host}

	conn, err := tls.Dial("tcp", addr, tlsConfig)
	if err != nil {
		return fmt.Errorf("TLS dial to %s: %w", addr, err)
	}

	client, err := smtp.NewClient(conn, cfg.Host)
	if err != nil {
		conn.Close()
		return fmt.Errorf("creating SMTP client: %w", err)
	}
	defer client.Close()

	auth := smtp.PlainAuth("", cfg.Username, cfg.Password, cfg.Host)
	if err := client.Auth(auth); err != nil {
		return fmt.Errorf("SMTP auth: %w", err)
	}

	return sendMailViaSMTPClient(client, from, to, body)
}

// sendSMTPWithStartTLS sends an email using STARTTLS.
func sendSMTPWithStartTLS(
	addr string, cfg SMTPConfig,
	from, to, body string,
) error {
	conn, err := net.DialTimeout("tcp", addr, 30*time.Second)
	if err != nil {
		return fmt.Errorf("dial to %s: %w", addr, err)
	}

	client, err := smtp.NewClient(conn, cfg.Host)
	if err != nil {
		conn.Close()
		return fmt.Errorf("creating SMTP client: %w", err)
	}
	defer client.Close()

	tlsConfig := &tls.Config{ServerName: cfg.Host}
	if err := client.StartTLS(tlsConfig); err != nil {
		return fmt.Errorf("SMTP STARTTLS: %w", err)
	}

	auth := smtp.PlainAuth("", cfg.Username, cfg.Password, cfg.Host)
	if err := client.Auth(auth); err != nil {
		return fmt.Errorf("SMTP auth: %w", err)
	}

	return sendMailViaSMTPClient(client, from, to, body)
}

// sendMailViaSMTPClient sends a message using an already-authenticated
// SMTP client.
func sendMailViaSMTPClient(
	client *smtp.Client, from, to, body string,
) error {
	if err := client.Mail(from); err != nil {
		return fmt.Errorf("SMTP MAIL FROM: %w", err)
	}

	if err := client.Rcpt(to); err != nil {
		return fmt.Errorf("SMTP RCPT TO: %w", err)
	}

	writer, err := client.Data()
	if err != nil {
		return fmt.Errorf("SMTP DATA: %w", err)
	}

	if _, err := writer.Write([]byte(body)); err != nil {
		return fmt.Errorf("writing email body: %w", err)
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("closing email body: %w", err)
	}

	return client.Quit()
}

// parseUID converts a string source item ID to a uint32 UID.
func parseUID(sourceItemID string) (uint32, error) {
	uid, err := strconv.ParseUint(sourceItemID, 10, 32)
	if err != nil {
		return 0, fmt.Errorf(
			"invalid email UID %q: %w", sourceItemID, err,
		)
	}
	return uint32(uid), nil
}

// sanitizeID removes or replaces characters that are not safe for use
// in a task ID.
var idUnsafeChars = regexp.MustCompile(`[^a-zA-Z0-9._-]`)

func sanitizeID(s string) string {
	return idUnsafeChars.ReplaceAllString(s, "_")
}

// htmlTagPattern matches HTML tags for stripping.
var htmlTagPattern = regexp.MustCompile(`<[^>]*>`)

// stripHTML removes HTML tags from a string and decodes common
// entities, providing a basic plain-text rendering.
func stripHTML(html string) string {
	if html == "" {
		return ""
	}

	result := html
	for _, tag := range []string{
		"<br>", "<br/>", "<br />", "</p>", "</div>", "</li>",
	} {
		result = strings.ReplaceAll(result, tag, "\n")
	}

	result = htmlTagPattern.ReplaceAllString(result, "")

	replacer := strings.NewReplacer(
		"&amp;", "&",
		"&lt;", "<",
		"&gt;", ">",
		"&quot;", `"`,
		"&#39;", "'",
		"&nbsp;", " ",
	)
	result = replacer.Replace(result)

	for strings.Contains(result, "\n\n\n") {
		result = strings.ReplaceAll(result, "\n\n\n", "\n\n")
	}

	return strings.TrimSpace(result)
}

// formatSize formats a byte size into a human-readable string.
func formatSize(bytes int64) string {
	switch {
	case bytes >= 1024*1024:
		return fmt.Sprintf("%.1f MB", float64(bytes)/(1024*1024))
	case bytes >= 1024:
		return fmt.Sprintf("%.1f KB", float64(bytes)/1024)
	default:
		return fmt.Sprintf("%d B", bytes)
	}
}
