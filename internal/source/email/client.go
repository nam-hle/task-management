package email

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
	"github.com/emersion/go-message/mail"

	"github.com/nhle/task-management/internal/source"
)

// IMAPClient wraps go-imap v2 for connecting to and querying IMAP servers.
type IMAPClient struct {
	host     string
	port     string
	username string
	password string
	tls      bool
}

// NewIMAPClient creates a new IMAP client configuration.
func NewIMAPClient(
	host, port, username, password string, tls bool,
) *IMAPClient {
	return &IMAPClient{
		host:     host,
		port:     port,
		username: username,
		password: password,
		tls:      tls,
	}
}

// Connect establishes a connection to the IMAP server, authenticates,
// and returns the connected client. The caller is responsible for
// calling Logout/Close on the returned client.
func (c *IMAPClient) Connect(
	_ context.Context,
) (*imapclient.Client, error) {
	addr := c.host + ":" + c.port

	var client *imapclient.Client
	var err error

	if c.tls {
		client, err = imapclient.DialTLS(addr, nil)
	} else {
		client, err = imapclient.DialStartTLS(addr, nil)
	}
	if err != nil {
		return nil, fmt.Errorf("connecting to IMAP %s: %w", addr, err)
	}

	if err := client.Login(c.username, c.password).Wait(); err != nil {
		_ = client.Logout().Wait()
		return nil, &source.AuthError{
			SourceType: source.SourceTypeEmail,
			Message: fmt.Sprintf(
				"authentication failed for %s: %v",
				c.username, err,
			),
		}
	}

	return client, nil
}

// FetchEnvelopes connects to IMAP, selects INBOX, searches for recent
// messages (last 7 days), and returns their envelope data.
func (c *IMAPClient) FetchEnvelopes(
	ctx context.Context, limit int,
) ([]Envelope, error) {
	client, err := c.Connect(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = client.Logout().Wait() }()

	// SELECT INBOX
	if _, err := client.Select("INBOX", nil).Wait(); err != nil {
		return nil, fmt.Errorf("selecting INBOX: %w", err)
	}

	// Search for messages from the last 7 days
	since := time.Now().AddDate(0, 0, -7)
	criteria := &imap.SearchCriteria{
		Since: since,
	}

	searchData, err := client.UIDSearch(criteria, nil).Wait()
	if err != nil {
		return nil, fmt.Errorf("searching messages: %w", err)
	}

	uids := searchData.AllUIDs()
	if len(uids) == 0 {
		return nil, nil
	}

	// Limit the number of UIDs to fetch (take most recent)
	if limit > 0 && len(uids) > limit {
		uids = uids[len(uids)-limit:]
	}

	uidSet := imap.UIDSetNum(uids...)

	fetchOpts := &imap.FetchOptions{
		Envelope: true,
		Flags:    true,
		UID:      true,
	}

	fetchCmd := client.Fetch(uidSet, fetchOpts)
	defer fetchCmd.Close()

	var envelopes []Envelope
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
		envelopes = append(envelopes, env)
	}

	if err := fetchCmd.Close(); err != nil {
		return envelopes, fmt.Errorf("fetching envelopes: %w", err)
	}

	return envelopes, nil
}

// FetchMessage connects to IMAP, selects INBOX, and fetches the full
// message body for the given UID, parsing it into a ParsedMessage.
func (c *IMAPClient) FetchMessage(
	ctx context.Context, uid uint32,
) (*ParsedMessage, error) {
	client, err := c.Connect(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = client.Logout().Wait() }()

	if _, err := client.Select("INBOX", nil).Wait(); err != nil {
		return nil, fmt.Errorf("selecting INBOX: %w", err)
	}

	uidSet := imap.UIDSetNum(imap.UID(uid))

	bodySection := &imap.FetchItemBodySection{
		Peek: true,
	}

	fetchOpts := &imap.FetchOptions{
		Envelope:    true,
		Flags:       true,
		UID:         true,
		BodySection: []*imap.FetchItemBodySection{bodySection},
	}

	fetchCmd := client.Fetch(uidSet, fetchOpts)
	defer fetchCmd.Close()

	msg := fetchCmd.Next()
	if msg == nil {
		return nil, fmt.Errorf("message UID %d not found", uid)
	}

	buf, err := msg.Collect()
	if err != nil {
		return nil, fmt.Errorf("collecting message data: %w", err)
	}

	env := envelopeFromBuffer(buf)

	parsed := &ParsedMessage{
		Envelope: env,
	}

	// Parse the MIME body
	rawBody := buf.FindBodySection(bodySection)
	if rawBody != nil {
		textBody, htmlBody, attachments := parseMIMEBody(rawBody)
		parsed.TextBody = textBody
		parsed.HTMLBody = htmlBody
		parsed.Attachments = attachments
	}

	if err := fetchCmd.Close(); err != nil {
		return parsed, fmt.Errorf("closing fetch: %w", err)
	}

	return parsed, nil
}

// SetFlags connects to IMAP and modifies flags on a message.
// If add is true, the flags are added; otherwise they are removed.
func (c *IMAPClient) SetFlags(
	ctx context.Context,
	uid uint32,
	flags []imap.Flag,
	add bool,
) error {
	client, err := c.Connect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = client.Logout().Wait() }()

	if _, err := client.Select("INBOX", nil).Wait(); err != nil {
		return fmt.Errorf("selecting INBOX: %w", err)
	}

	uidSet := imap.UIDSetNum(imap.UID(uid))

	op := imap.StoreFlagsAdd
	if !add {
		op = imap.StoreFlagsDel
	}

	storeCmd := client.Store(uidSet, &imap.StoreFlags{
		Op:     op,
		Silent: true,
		Flags:  flags,
	}, nil)

	return storeCmd.Close()
}

// MoveToArchive connects to IMAP and moves the message to an archive
// mailbox. It tries common archive folder names, falling back to
// marking the message as deleted.
func (c *IMAPClient) MoveToArchive(
	ctx context.Context, uid uint32,
) error {
	client, err := c.Connect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = client.Logout().Wait() }()

	if _, err := client.Select("INBOX", nil).Wait(); err != nil {
		return fmt.Errorf("selecting INBOX: %w", err)
	}

	uidSet := imap.UIDSetNum(imap.UID(uid))

	// Try common archive folder names
	archiveFolders := []string{
		"Archive", "[Gmail]/All Mail", "Archives", "INBOX.Archive",
	}

	for _, folder := range archiveFolders {
		moveCmd := client.Move(uidSet, folder)
		if _, err := moveCmd.Wait(); err == nil {
			return nil
		}
	}

	// Fallback: mark as deleted
	storeCmd := client.Store(uidSet, &imap.StoreFlags{
		Op:     imap.StoreFlagsAdd,
		Silent: true,
		Flags:  []imap.Flag{imap.FlagDeleted},
	}, nil)

	return storeCmd.Close()
}

// envelopeFromBuffer extracts an Envelope from a FetchMessageBuffer.
func envelopeFromBuffer(buf *imapclient.FetchMessageBuffer) Envelope {
	env := Envelope{
		UID: uint32(buf.UID),
	}

	if buf.Envelope != nil {
		env.MessageID = buf.Envelope.MessageID
		env.Subject = buf.Envelope.Subject
		env.Date = buf.Envelope.Date

		if len(buf.Envelope.From) > 0 {
			from := buf.Envelope.From[0]
			if from.Name != "" {
				env.From = from.Name
			} else {
				env.From = from.Addr()
			}
		}

		for _, to := range buf.Envelope.To {
			env.To = append(env.To, to.Addr())
		}
	}

	for _, flag := range buf.Flags {
		env.Flags = append(env.Flags, string(flag))
	}

	return env
}

// parseMIMEBody parses a raw RFC 2822 message body using go-message
// and extracts the text/plain body, text/html body, and attachment
// metadata.
func parseMIMEBody(raw []byte) (
	textBody string, htmlBody string, attachments []Attachment,
) {
	reader := bytes.NewReader(raw)

	mr, err := mail.CreateReader(reader)
	if err != nil {
		// If parsing fails, try treating the whole thing as plain text
		return string(raw), "", nil
	}
	defer mr.Close()

	for {
		part, err := mr.NextPart()
		if err == io.EOF {
			break
		}
		if err != nil {
			break
		}

		switch h := part.Header.(type) {
		case *mail.InlineHeader:
			contentType, _, _ := h.ContentType()
			body, readErr := io.ReadAll(part.Body)
			if readErr != nil {
				continue
			}

			switch {
			case strings.HasPrefix(contentType, "text/plain"):
				textBody = string(body)
			case strings.HasPrefix(contentType, "text/html"):
				htmlBody = string(body)
			}

		case *mail.AttachmentHeader:
			filename, _ := h.Filename()
			contentType, _, _ := h.ContentType()

			// Read to get size without storing content
			body, readErr := io.ReadAll(part.Body)
			if readErr != nil {
				continue
			}

			attachments = append(attachments, Attachment{
				Filename: filename,
				Size:     int64(len(body)),
				MIMEType: contentType,
			})
		}
	}

	return textBody, htmlBody, attachments
}
