package models

import (
	"time"
)

// WebhookMessage represents a webhook message
type WebhookMessage struct {
	ID        string            `json:"id" db:"id"`
	Path      string            `json:"path" db:"path"`
	Queue     string            `json:"queue" db:"queue"`
	Body      []byte            `json:"body" db:"body"`
	Headers   map[string]string `json:"headers" db:"headers"`
	Timestamp time.Time         `json:"timestamp" db:"timestamp"`
	Retries   int               `json:"retries" db:"retries"`
	Status    MessageStatus     `json:"status" db:"status"`
	Error     string            `json:"error,omitempty" db:"error"`
	CreatedAt time.Time         `json:"created_at" db:"created_at"`
	UpdatedAt time.Time         `json:"updated_at" db:"updated_at"`
}

// MessageStatus represents the status of a message
type MessageStatus string

const (
	StatusPending  MessageStatus = "pending"
	StatusSent     MessageStatus = "sent"
	StatusFailed   MessageStatus = "failed"
	StatusRetrying MessageStatus = "retrying"
)

// PendingMessage represents a message pending for retry
type PendingMessage struct {
	*WebhookMessage
	NextRetryAt time.Time `json:"next_retry_at" db:"next_retry_at"`
}

// DeliveryTarget represents where to deliver the message
type DeliveryTarget struct {
	Type  TargetType `json:"type"`
	Topic string     `json:"topic,omitempty"`
	URL   string     `json:"url,omitempty"`
}

// TargetType represents the type of delivery target
type TargetType string

const (
	TargetKafka     TargetType = "kafka"
	TargetRemoteURL TargetType = "remote_url"
)
