package httpclient

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/expai/messagebridge/config"
	"github.com/expai/messagebridge/models"
)

// Client represents HTTP client for sending webhooks
type Client struct {
	client *http.Client
	config *config.RemoteURLConfig
}

// NewClient creates a new HTTP client
func NewClient(cfg *config.RemoteURLConfig) *Client {
	return &Client{
		client: &http.Client{
			Timeout: cfg.Timeout,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		config: cfg,
	}
}

// SendMessage sends a webhook message to remote URL
func (c *Client) SendMessage(msg *models.WebhookMessage) error {
	req, err := http.NewRequest("POST", c.config.URL, bytes.NewReader(msg.Body))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %w", err)
	}

	// Set headers from original webhook
	for key, value := range msg.Headers {
		req.Header.Set(key, value)
	}

	// Add metadata headers
	req.Header.Set("X-Webhook-ID", msg.ID)
	req.Header.Set("X-Webhook-Path", msg.Path)
	req.Header.Set("X-Webhook-Queue", msg.Queue)
	req.Header.Set("X-Webhook-Timestamp", msg.Timestamp.Format(time.RFC3339))

	// Set content type if not present
	if req.Header.Get("Content-Type") == "" {
		req.Header.Set("Content-Type", "application/json")
	}

	ctx, cancel := context.WithTimeout(context.Background(), c.config.Timeout)
	defer cancel()

	req = req.WithContext(ctx)

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send HTTP request: %w", err)
	}
	defer resp.Body.Close()

	// Read response body for logging
	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("HTTP request failed with status %d: %s", resp.StatusCode, string(body))
	}

	log.Printf("Message %s sent to remote URL successfully - Status: %d", msg.ID, resp.StatusCode)
	return nil
}

// SendMessageWithRetry sends a message with built-in retry logic
func (c *Client) SendMessageWithRetry(msg *models.WebhookMessage) error {
	var lastErr error

	for attempt := 0; attempt <= c.config.Retries; attempt++ {
		if attempt > 0 {
			backoff := time.Duration(attempt*attempt) * time.Second
			log.Printf("Retrying HTTP send for message %s, attempt %d/%d after %v",
				msg.ID, attempt, c.config.Retries, backoff)
			time.Sleep(backoff)
		}

		err := c.SendMessage(msg)
		if err == nil {
			return nil
		}

		lastErr = err
		log.Printf("Failed to send message %s to remote URL (attempt %d/%d): %v",
			msg.ID, attempt+1, c.config.Retries+1, err)
	}

	return fmt.Errorf("failed to send message after %d attempts: %w",
		c.config.Retries+1, lastErr)
}

// HealthCheck checks if remote URL is available
func (c *Client) HealthCheck() error {
	req, err := http.NewRequest("HEAD", c.config.URL, nil)
	if err != nil {
		return fmt.Errorf("failed to create health check request: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()

	req = req.WithContext(ctx)

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("health check failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 500 {
		return fmt.Errorf("remote URL returned server error: %d", resp.StatusCode)
	}

	return nil
}
