package handler

import (
	"fmt"
	"log"

	"github.com/expai/messagebridge/config"
	"github.com/expai/messagebridge/httpclient"
	"github.com/expai/messagebridge/kafka"
	"github.com/expai/messagebridge/models"
	"github.com/expai/messagebridge/storage"
)

// MessageHandler processes webhook messages
type MessageHandler struct {
	config        *config.Config
	kafkaProducer *kafka.Producer
	httpClient    *httpclient.Client
	storage       *storage.SQLiteStorage
}

// NewMessageHandler creates a new message handler
func NewMessageHandler(cfg *config.Config, kafkaProducer *kafka.Producer, httpClient *httpclient.Client, storage *storage.SQLiteStorage) *MessageHandler {
	return &MessageHandler{
		config:        cfg,
		kafkaProducer: kafkaProducer,
		httpClient:    httpClient,
		storage:       storage,
	}
}

// ProcessWebhook processes incoming webhook messages
func (h *MessageHandler) ProcessWebhookOld(msg *models.WebhookMessage) error {
	log.Printf("Processing webhook message %s for queue %s", msg.ID, msg.Queue)

	// Determine delivery strategy
	target := h.getDeliveryTarget()

	var err error
	switch target.Type {
	case models.TargetKafka:
		err = h.sendToKafka(msg)
	case models.TargetRemoteURL:
		err = h.sendToRemoteURL(msg)
	default:
		err = h.sendToKafka(msg) // Default to Kafka
	}

	// If sending failed and SQLite is configured, save for retry
	if err != nil && h.storage != nil {
		log.Printf("Failed to send message %s immediately, saving to storage: %v", msg.ID, err)
		msg.Status = models.StatusPending
		msg.Error = err.Error()

		if saveErr := h.storage.SaveMessage(msg); saveErr != nil {
			log.Printf("Failed to save message %s to storage: %v", msg.ID, saveErr)
			return fmt.Errorf("failed to send message and save to storage: send error: %w, save error: %v", err, saveErr)
		}

		log.Printf("Message %s saved to storage for retry", msg.ID)
		return nil // Return success since we saved it for retry
	}

	if err != nil {
		return fmt.Errorf("failed to send message %s: %w", msg.ID, err)
	}

	msg.Status = models.StatusSent
	log.Printf("Message %s sent successfully", msg.ID)
	return nil
}

// ProcessWebhook processes incoming webhook messages and stores them in database
func (h *MessageHandler) ProcessWebhook(msg *models.WebhookMessage) error {
	log.Printf("Processing webhook message %s for queue %s", msg.ID, msg.Queue)

	if h.storage == nil {
		return fmt.Errorf("storage is not configured")
	}

	msg.Status = models.StatusPending

	if err := h.storage.SaveMessage(msg); err != nil {
		log.Printf("Failed to save message %s to storage: %v", msg.ID, err)
		return fmt.Errorf("failed to save message to storage: %w", err)
	}

	log.Printf("Message %s saved to storage for processing by worker", msg.ID)
	return nil
}

// sendToKafka sends message to Kafka
func (h *MessageHandler) sendToKafka(msg *models.WebhookMessage) error {
	if h.kafkaProducer == nil {
		return fmt.Errorf("Kafka producer not configured")
	}

	return h.kafkaProducer.SendMessageWithRetry(msg)
}

// sendToRemoteURL sends message to remote URL
func (h *MessageHandler) sendToRemoteURL(msg *models.WebhookMessage) error {
	if h.httpClient == nil {
		return fmt.Errorf("HTTP client not configured")
	}

	return h.httpClient.SendMessageWithRetry(msg)
}

// getDeliveryTarget determines where to send the message
func (h *MessageHandler) getDeliveryTarget() *models.DeliveryTarget {
	// If remote URL is configured, prefer it
	if h.config.RemoteURL != nil && h.config.RemoteURL.URL != "" {
		return &models.DeliveryTarget{
			Type: models.TargetRemoteURL,
			URL:  h.config.RemoteURL.URL,
		}
	}

	// Default to Kafka
	return &models.DeliveryTarget{
		Type: models.TargetKafka,
	}
}

// HealthCheck checks the health of all components
func (h *MessageHandler) HealthCheck() map[string]interface{} {
	health := make(map[string]interface{})

	// Check Kafka
	if h.kafkaProducer != nil {
		if err := h.kafkaProducer.HealthCheck(); err != nil {
			health["kafka"] = map[string]interface{}{
				"status": "unhealthy",
				"error":  err.Error(),
			}
		} else {
			health["kafka"] = map[string]interface{}{
				"status": "healthy",
			}
		}
	} else {
		health["kafka"] = map[string]interface{}{
			"status": "not_configured",
		}
	}

	// Check Remote URL
	if h.httpClient != nil {
		if err := h.httpClient.HealthCheck(); err != nil {
			health["remote_url"] = map[string]interface{}{
				"status": "unhealthy",
				"error":  err.Error(),
			}
		} else {
			health["remote_url"] = map[string]interface{}{
				"status": "healthy",
			}
		}
	} else {
		health["remote_url"] = map[string]interface{}{
			"status": "not_configured",
		}
	}

	// Check Storage
	if h.storage != nil {
		stats, err := h.storage.GetMessageStats()
		if err != nil {
			health["storage"] = map[string]interface{}{
				"status": "unhealthy",
				"error":  err.Error(),
			}
		} else {
			health["storage"] = map[string]interface{}{
				"status": "healthy",
				"stats":  stats,
			}
		}
	} else {
		health["storage"] = map[string]interface{}{
			"status": "not_configured",
		}
	}

	return health
}
