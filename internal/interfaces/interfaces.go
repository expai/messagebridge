package interfaces

import (
	"github.com/expai/messagebridge/models"
)

// MessageProducer interface for Kafka producers
type MessageProducer interface {
	SendMessage(msg *models.WebhookMessage) error
	SendMessageWithRetry(msg *models.WebhookMessage) error
	HealthCheck() error
	Close() error
}

// HTTPSender interface for HTTP clients
type HTTPSender interface {
	SendMessage(msg *models.WebhookMessage) error
	SendMessageWithRetry(msg *models.WebhookMessage) error
	HealthCheck() error
}

// MessageStorage interface for message storage
type MessageStorage interface {
	SaveMessage(msg *models.WebhookMessage) error
	GetPendingMessages(limit int) ([]*models.PendingMessage, error)
	UpdateMessageStatus(id string, status models.MessageStatus, error string) error
	DeleteMessage(id string) error
	GetMessageStats() (map[string]int, error)
	Close() error
	Cleanup(retentionDays int) error
}

// WebhookHandler interface for processing webhooks
type WebhookHandler interface {
	ProcessWebhook(msg *models.WebhookMessage) error
	HealthCheck() map[string]interface{}
}
