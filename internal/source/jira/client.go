package jira

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Client is a thin HTTP client for the Jira Server/DC REST API v2.
// It handles Bearer token authentication, JSON marshaling, and
// automatic retry with exponential backoff on HTTP 429.
type Client struct {
	baseURL    string
	token      string
	httpClient *http.Client
	maxRetries int
}

// NewClient creates a new Jira HTTP client. The baseURL should be the
// root URL of the Jira instance (e.g., https://jira.corp.example.com).
// The token is a Personal Access Token used for Bearer authentication.
func NewClient(baseURL, token string) *Client {
	return &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   token,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		maxRetries: 3,
	}
}

// Get performs an HTTP GET request and unmarshals the JSON response.
func (c *Client) Get(
	ctx context.Context,
	path string,
	result interface{},
) error {
	return c.do(ctx, http.MethodGet, path, nil, result)
}

// Post performs an HTTP POST request with a JSON body and unmarshals
// the JSON response.
func (c *Client) Post(
	ctx context.Context,
	path string,
	body interface{},
	result interface{},
) error {
	return c.do(ctx, http.MethodPost, path, body, result)
}

// do is the core HTTP method that builds the request, handles auth,
// rate limiting with exponential backoff, and JSON (de)serialization.
func (c *Client) do(
	ctx context.Context,
	method string,
	path string,
	body interface{},
	result interface{},
) error {
	url := c.baseURL + path

	var bodyReader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshaling request body: %w", err)
		}
		bodyReader = bytes.NewReader(data)
	}

	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		// Rebuild the body reader on retries since it was consumed.
		if attempt > 0 && body != nil {
			data, _ := json.Marshal(body)
			bodyReader = bytes.NewReader(data)
		}

		req, err := http.NewRequestWithContext(
			ctx, method, url, bodyReader,
		)
		if err != nil {
			return fmt.Errorf("creating request: %w", err)
		}

		req.Header.Set("Authorization", "Bearer "+c.token)
		req.Header.Set("Accept", "application/json")
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("executing request %s %s: %w", method, path, err)
		}

		respBody, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			return fmt.Errorf("reading response body: %w", readErr)
		}

		if resp.StatusCode == http.StatusTooManyRequests {
			waitDuration := retryAfterDuration(resp, attempt)
			lastErr = fmt.Errorf(
				"rate limited (429) on %s %s", method, path,
			)

			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(waitDuration):
				continue
			}
		}

		if resp.StatusCode == http.StatusUnauthorized {
			return fmt.Errorf(
				"authentication failed (401): check your "+
					"Personal Access Token for %s", c.baseURL,
			)
		}

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			var jiraErr ErrorResponse
			if json.Unmarshal(respBody, &jiraErr) == nil &&
				(len(jiraErr.ErrorMessages) > 0 ||
					len(jiraErr.Errors) > 0) {
				return fmt.Errorf(
					"jira API error (%d) on %s %s: %s %v",
					resp.StatusCode, method, path,
					strings.Join(jiraErr.ErrorMessages, "; "),
					jiraErr.Errors,
				)
			}
			return fmt.Errorf(
				"unexpected status %d on %s %s: %s",
				resp.StatusCode, method, path, string(respBody),
			)
		}

		// No content to parse (e.g. 204).
		if result == nil || resp.StatusCode == http.StatusNoContent {
			return nil
		}

		if err := json.Unmarshal(respBody, result); err != nil {
			return fmt.Errorf(
				"unmarshaling response from %s %s: %w",
				method, path, err,
			)
		}

		return nil
	}

	return fmt.Errorf(
		"max retries (%d) exceeded: %w", c.maxRetries, lastErr,
	)
}

// retryAfterDuration reads the Retry-After header and computes a wait
// duration. Falls back to exponential backoff if the header is missing.
func retryAfterDuration(resp *http.Response, attempt int) time.Duration {
	if header := resp.Header.Get("Retry-After"); header != "" {
		if seconds, err := strconv.Atoi(header); err == nil {
			return time.Duration(seconds) * time.Second
		}
	}

	// Exponential backoff: 1s, 2s, 4s, ...
	backoff := time.Duration(1<<uint(attempt)) * time.Second
	if backoff > 30*time.Second {
		backoff = 30 * time.Second
	}
	return backoff
}
