package handler

import (
	"errors"
	"testing"
	"time"

	"github.com/expai/messagebridge/config"
	"github.com/expai/messagebridge/internal/interfaces"
	"github.com/expai/messagebridge/models"
)

// Mock implementations for testing
type mockMessageProducer struct {
	sendErr     error
	healthErr   error
	sendCalled  bool
	retryCalled bool
}

func (m *mockMessageProducer) SendMessage(msg *models.WebhookMessage) error {
	m.sendCalled = true
	return m.sendErr
}

func (m *mockMessageProducer) SendMessageWithRetry(msg *models.WebhookMessage) error {
	m.retryCalled = true
	return m.sendErr
}

func (m *mockMessageProducer) HealthCheck() error {
	return m.healthErr
}

func (m *mockMessageProducer) Close() error {
	return nil
}

type mockHTTPSender struct {
	sendErr     error
	healthErr   error
	sendCalled  bool
	retryCalled bool
}

func (m *mockHTTPSender) SendMessage(msg *models.WebhookMessage) error {
	m.sendCalled = true
	return m.sendErr
}

func (m *mockHTTPSender) SendMessageWithRetry(msg *models.WebhookMessage) error {
	m.retryCalled = true
	return m.sendErr
}

func (m *mockHTTPSender) HealthCheck() error {
	return m.healthErr
}

type mockMessageStorage struct {
	saveErr error
	saved   []*models.WebhookMessage
	stats   map[string]int
}

func (m *mockMessageStorage) SaveMessage(msg *models.WebhookMessage) error {
	if m.saveErr != nil {
		return m.saveErr
	}
	m.saved = append(m.saved, msg)
	return nil
}

func (m *mockMessageStorage) GetPendingMessages(limit int) ([]*models.PendingMessage, error) {
	return nil, nil
}

func (m *mockMessageStorage) UpdateMessageStatus(id string, status models.MessageStatus, error string) error {
	return nil
}

func (m *mockMessageStorage) DeleteMessage(id string) error {
	return nil
}

func (m *mockMessageStorage) GetMessageStats() (map[string]int, error) {
	if m.stats == nil {
		m.stats = map[string]int{"pending": 5, "sent": 10}
	}
	return m.stats, nil
}

func (m *mockMessageStorage) Close() error {
	return nil
}

func (m *mockMessageStorage) Cleanup(retentionDays int) error {
	return nil
}

func TestProcessWebhook(t *testing.T) {
	tests := []struct {
		name        string
		storageErr  error
		wantErr     bool
		expectSaved bool
		hasStorage  bool
	}{
		{
			name:        "successful save",
			storageErr:  nil,
			wantErr:     false,
			expectSaved: true,
			hasStorage:  true,
		},
		{
			name:        "storage error",
			storageErr:  errors.New("storage error"),
			wantErr:     true,
			expectSaved: false,
			hasStorage:  true,
		},
		{
			name:        "no storage configured",
			storageErr:  nil,
			wantErr:     true,
			expectSaved: false,
			hasStorage:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := &config.Config{}
			mockProducer := &mockMessageProducer{}
			mockHTTP := &mockHTTPSender{}

			var mockStorage interfaces.MessageStorage
			if tt.hasStorage {
				mockStorage = &mockMessageStorage{saveErr: tt.storageErr}
			}

			handler := NewMessageHandler(cfg, mockProducer, mockHTTP, mockStorage)

			msg := &models.WebhookMessage{
				ID:        "test-id",
				Path:      "/webhook/test",
				Queue:     "test-queue",
				Body:      []byte(`{"test": true}`),
				Headers:   map[string]string{"Content-Type": "application/json"},
				Timestamp: time.Now(),
				Status:    models.StatusPending,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			}

			err := handler.ProcessWebhook(msg)

			if tt.wantErr && err == nil {
				t.Errorf("ProcessWebhook() expected error but got none")
			}
			if !tt.wantErr && err != nil {
				t.Errorf("ProcessWebhook() unexpected error: %v", err)
			}

			if tt.expectSaved && mockStorage != nil {
				if ms, ok := mockStorage.(*mockMessageStorage); ok && len(ms.saved) == 0 {
					t.Errorf("ProcessWebhook() expected message to be saved but wasn't")
				}
			}
		})
	}
}

func TestHealthCheck(t *testing.T) {
	cfg := &config.Config{}
	mockProducer := &mockMessageProducer{healthErr: errors.New("kafka down")}
	mockHTTP := &mockHTTPSender{healthErr: nil}
	mockStorage := &mockMessageStorage{}

	handler := NewMessageHandler(cfg, mockProducer, mockHTTP, mockStorage)

	health := handler.HealthCheck()

	// Check that all components are included in health check
	if _, exists := health["kafka"]; !exists {
		t.Error("HealthCheck() missing kafka status")
	}
	if _, exists := health["storage"]; !exists {
		t.Error("HealthCheck() missing storage status")
	}

	// Check kafka error is reflected
	if kafkaHealth, ok := health["kafka"].(map[string]interface{}); ok {
		if kafkaHealth["status"] != "unhealthy" {
			t.Error("HealthCheck() kafka should be unhealthy")
		}
	}
}
