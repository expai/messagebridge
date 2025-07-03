package worker

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/expai/messagebridge/config"
	"github.com/expai/messagebridge/httpclient"
	"github.com/expai/messagebridge/kafka"
	"github.com/expai/messagebridge/models"
	"github.com/expai/messagebridge/storage"
)

// Worker handles retry logic for failed messages
type Worker struct {
	storage       *storage.SQLiteStorage
	kafkaProducer *kafka.Producer
	httpClient    *httpclient.Client
	config        *config.Config
	running       bool
	stopCh        chan struct{}
	wg            sync.WaitGroup
}

// NewWorker creates a new worker instance
func NewWorker(cfg *config.Config, storage *storage.SQLiteStorage, kafkaProducer *kafka.Producer, httpClient *httpclient.Client) *Worker {
	return &Worker{
		storage:       storage,
		kafkaProducer: kafkaProducer,
		httpClient:    httpClient,
		config:        cfg,
		stopCh:        make(chan struct{}),
	}
}

// Start starts the worker
func (w *Worker) Start(ctx context.Context) {
	if w.running {
		return
	}

	w.running = true
	w.wg.Add(1)

	go func() {
		defer w.wg.Done()
		w.run(ctx)
	}()

	log.Println("Worker started")
}

// Stop stops the worker
func (w *Worker) Stop() {
	if !w.running {
		return
	}

	w.running = false
	close(w.stopCh)
	w.wg.Wait()
	log.Println("Worker stopped")
}

// run is the main worker loop
func (w *Worker) run(ctx context.Context) {
	ticker := time.NewTicker(w.config.Worker.RetryInterval)
	defer ticker.Stop()

	// Initial run
	w.processRetries()

	for {
		select {
		case <-ctx.Done():
			return
		case <-w.stopCh:
			return
		case <-ticker.C:
			w.processRetries()
		}
	}
}

// processRetries processes pending messages for retry
func (w *Worker) processRetries() {
	messages, err := w.storage.GetPendingMessages(w.config.Worker.BatchSize)
	if err != nil {
		log.Printf("Failed to get pending messages: %v", err)
		return
	}

	if len(messages) == 0 {
		return
	}

	log.Printf("Processing %d pending messages", len(messages))

	for _, msg := range messages {
		if err := w.processMessage(msg); err != nil {
			log.Printf("Failed to process message %s: %v", msg.ID, err)
		}
	}
}

// processMessage processes a single message
func (w *Worker) processMessage(msg *models.PendingMessage) error {
	// Check if we've exceeded max retries (0 means unlimited retries)
	if w.config.Worker.MaxRetries > 0 && msg.Retries >= w.config.Worker.MaxRetries {
		log.Printf("Message %s exceeded max retries (%d), marking as failed", msg.ID, w.config.Worker.MaxRetries)
		return w.storage.UpdateMessageStatus(msg.ID, models.StatusFailed, "Exceeded max retries")
	}

	// Log retry attempt
	if w.config.Worker.MaxRetries == 0 {
		log.Printf("Retrying message %s (attempt %d, unlimited retries enabled)", msg.ID, msg.Retries+1)
	} else {
		log.Printf("Retrying message %s (attempt %d/%d)", msg.ID, msg.Retries+1, w.config.Worker.MaxRetries)
	}

	// Determine delivery target
	target := w.getDeliveryTarget()

	var err error
	switch target.Type {
	case models.TargetKafka:
		err = w.sendToKafka(msg.WebhookMessage)
	case models.TargetRemoteURL:
		err = w.sendToRemoteURL(msg.WebhookMessage)
	default:
		err = w.sendToKafka(msg.WebhookMessage) // Default to Kafka
	}

	if err != nil {
		log.Printf("Failed to send message %s: %v", msg.ID, err)
		return w.storage.UpdateMessageStatus(msg.ID, models.StatusRetrying, err.Error())
	}

	// Success - remove from storage or mark as sent
	log.Printf("Message %s sent successfully, removing from storage", msg.ID)
	return w.storage.DeleteMessage(msg.ID)
}

// sendToKafka sends message to Kafka
func (w *Worker) sendToKafka(msg *models.WebhookMessage) error {
	if w.kafkaProducer == nil {
		return fmt.Errorf("Kafka producer not available")
	}

	return w.kafkaProducer.SendMessage(msg)
}

// sendToRemoteURL sends message to remote URL
func (w *Worker) sendToRemoteURL(msg *models.WebhookMessage) error {
	if w.httpClient == nil {
		return fmt.Errorf("HTTP client not available")
	}

	return w.httpClient.SendMessage(msg)
}

// getDeliveryTarget determines where to send the message
func (w *Worker) getDeliveryTarget() *models.DeliveryTarget {
	// If remote URL is configured, prefer it
	if w.config.RemoteURL != nil && w.config.RemoteURL.URL != "" {
		return &models.DeliveryTarget{
			Type: models.TargetRemoteURL,
			URL:  w.config.RemoteURL.URL,
		}
	}

	// Default to Kafka
	return &models.DeliveryTarget{
		Type: models.TargetKafka,
	}
}

// GetStats returns worker statistics
func (w *Worker) GetStats() (map[string]interface{}, error) {
	messageStats, err := w.storage.GetMessageStats()
	if err != nil {
		return nil, err
	}

	var maxRetriesDisplay interface{}
	if w.config.Worker.MaxRetries == 0 {
		maxRetriesDisplay = "unlimited"
	} else {
		maxRetriesDisplay = w.config.Worker.MaxRetries
	}

	stats := map[string]interface{}{
		"running":        w.running,
		"retry_interval": w.config.Worker.RetryInterval.String(),
		"batch_size":     w.config.Worker.BatchSize,
		"max_retries":    maxRetriesDisplay,
		"message_stats":  messageStats,
	}

	return stats, nil
}

// Cleanup performs maintenance tasks
func (w *Worker) Cleanup() error {
	// Clean up old sent messages (keep for 7 days)
	if err := w.storage.Cleanup(7); err != nil {
		log.Printf("Failed to cleanup old messages: %v", err)
		return err
	}

	log.Println("Cleanup completed successfully")
	return nil
}
