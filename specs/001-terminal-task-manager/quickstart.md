# Quickstart: Terminal Task Manager

## Prerequisites

- **Go 1.22+**: [Install Go](https://go.dev/dl/)
- **Git**: For cloning the repository
- A Jira Server/DC instance with a Personal Access Token (PAT)
- (Optional) Bitbucket Server/DC instance with a PAT
- (Optional) IMAP-compatible email account
- (Optional) Anthropic API key for AI assistant

## Setup

```bash
# Clone the repository
git clone <repo-url>
cd task-management

# Install dependencies
go mod download

# Build the binary
go build -o taskmanager ./cmd/taskmanager

# Run
./taskmanager
```

## First Run

On first launch with no configured sources, the app guides you through setup:

1. Select source type (Jira, Bitbucket, or Email)
2. Enter connection details (base URL, credentials)
3. The app validates the connection
4. Repeat for additional sources, or press `Esc` to start

## Configuration

Configuration is stored at `~/.config/taskmanager/config.yaml`:

```yaml
sources:
  - type: jira
    name: "Work Jira"
    base_url: "https://jira.example.com"
    poll_interval_sec: 120
    config:
      default_jql: "assignee=currentUser() ORDER BY updated DESC"

  - type: bitbucket
    name: "Work Bitbucket"
    base_url: "https://bitbucket.example.com"
    poll_interval_sec: 120

  - type: email
    name: "Work Email"
    base_url: "imap.gmail.com"
    config:
      imap_port: 993
      smtp_host: "smtp.gmail.com"
      smtp_port: 587
      username: "you@gmail.com"
      tls: true

ai:
  model: "claude-sonnet-4-5-20250929"
  max_tokens: 1024

display:
  theme: "default"
  poll_interval_sec: 120
```

Credentials are stored in the system keychain (macOS Keychain / Linux Secret Service).

## Key Bindings

| Key | Action |
|-----|--------|
| `j` / `k` | Move down / up |
| `Enter` | Open detail view |
| `Esc` / `q` | Back / quit |
| `/` | Search / filter |
| `:` | Command palette |
| `?` | Help overlay |
| `r` | Manual refresh |
| `1-3` | Filter by source (1=Jira, 2=Bitbucket, 3=Email) |
| `a` | AI assistant prompt |
| `c` | Add comment (in detail view) |
| `t` | Transition status (Jira detail view) |
| `p` | Approve PR (Bitbucket detail view) |
| `Tab` | Cycle sort order |

## Development

```bash
# Run tests
go test ./...

# Run with live reload (install air first: go install github.com/air-verse/air@latest)
air

# Build for multiple platforms
GOOS=darwin GOARCH=arm64 go build -o taskmanager-darwin-arm64 ./cmd/taskmanager
GOOS=linux GOARCH=amd64 go build -o taskmanager-linux-amd64 ./cmd/taskmanager
```

## Project Structure

See [plan.md](./plan.md) for the full project structure and technology decisions.
