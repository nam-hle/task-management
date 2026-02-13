// Package contracts/email defines the Email (IMAP/SMTP) adapter interface.
// Uses IMAP4rev1/rev2 for reading and SMTP for sending replies.
//
// Library: emersion/go-imap v2 + emersion/go-message
// Auth: Username + password (stored in system keychain)
package contracts

// EmailAdapter extends the common Source interface with email-specific operations.

// Key operations mapped to Source interface methods:
//
// ValidateConnection:
//   Connect to IMAP server with TLS/STARTTLS.
//   Authenticate with username + password.
//   SELECT INBOX to verify access.
//   Return: authenticated email address as display name.
//
// FetchItems (inbox messages):
//   SELECT INBOX
//   SEARCH for recent messages (e.g., last 7 days or last 100 messages)
//   FETCH envelope data: From, Subject, Date, Flags
//   Maps to: Task {
//     Title = Subject,
//     Author = From display name,
//     Status = Unread -> "Open", Read -> "In Progress", Archived -> "Done",
//     Priority = Flagged -> 2, Unread -> 3, Read -> 5
//   }
//
// GetItemDetail:
//   FETCH full message body (BODY[])
//   Parse with go-message for MIME structure
//   Extract text/plain or text/html (convert HTML to text)
//   Return: ItemDetail with rendered body
//
// GetActions:
//   Available actions based on message state:
//   - Reply (requires input: reply text)
//   - Archive (move to Archive folder or set \Deleted flag)
//   - Flag / Unflag (toggle \Flagged)
//   - Mark Read / Unread (toggle \Seen flag)
//
// ExecuteAction:
//   Reply:   Compose reply via SMTP (Re: subject, In-Reply-To header)
//   Archive: MOVE message to Archive/All Mail folder, or STORE +FLAGS (\Deleted)
//   Flag:    STORE +FLAGS (\Flagged)
//   Unflag:  STORE -FLAGS (\Flagged)
//   Mark Read:   STORE +FLAGS (\Seen)
//   Mark Unread: STORE -FLAGS (\Seen)
//
// Search:
//   IMAP SEARCH command with text criteria.
//   Example: SEARCH TEXT "query string"
//
// Polling strategy:
//   Use IMAP IDLE for push notifications when supported (go-imap v2 supports this).
//   Fall back to periodic SEARCH if IDLE is not available.
//
// Email-specific considerations:
//   - HTML emails: Convert to text using html2text, then optionally render
//     markdown portions with glamour.
//   - Attachments: List attachment filenames and sizes in detail view.
//     Do not download or render attachments (out of scope).
//   - Gmail: Requires App Passwords or XOAUTH2 (go-imap supports both).
//   - Outlook: Requires App Passwords for IMAP access.
//
// SMTP for replies:
//   Connect to configured SMTP server with TLS/STARTTLS.
//   Authenticate with same credentials.
//   Compose: From, To (original sender), Subject (Re: original),
//            In-Reply-To and References headers, plain text body.
