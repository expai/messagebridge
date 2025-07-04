package kafka

import (
	"crypto/tls"
	"fmt"
	"log"
	"time"

	"github.com/expai/messagebridge/config"
	"github.com/expai/messagebridge/models"

	"github.com/IBM/sarama"
)

// Producer represents a Kafka producer
type Producer struct {
	producer     sarama.SyncProducer
	config       *config.KafkaConfig
	saramaConfig *sarama.Config
}

// NewProducer creates a new Kafka producer
func NewProducer(cfg *config.KafkaConfig) (*Producer, error) {
	saramaConfig := sarama.NewConfig()

	// Producer settings for reliability
	saramaConfig.Producer.RequiredAcks = sarama.WaitForAll
	saramaConfig.Producer.Retry.Max = cfg.RetryMax
	saramaConfig.Producer.Retry.Backoff = cfg.RetryBackoff
	saramaConfig.Producer.Return.Successes = true
	saramaConfig.Producer.Return.Errors = true
	saramaConfig.Producer.Compression = sarama.CompressionSnappy
	saramaConfig.Producer.Flush.Frequency = time.Second * 1
	saramaConfig.Producer.Flush.Messages = cfg.BatchSize
	saramaConfig.Net.DialTimeout = cfg.Timeout
	saramaConfig.Net.ReadTimeout = cfg.Timeout
	saramaConfig.Net.WriteTimeout = cfg.Timeout

	// Security settings
	if cfg.SecurityProtocol != "" {
		switch cfg.SecurityProtocol {
		case "SASL_SSL":
			saramaConfig.Net.SASL.Enable = true
			saramaConfig.Net.TLS.Enable = true
			saramaConfig.Net.TLS.Config = &tls.Config{InsecureSkipVerify: false}
		case "SASL_PLAINTEXT":
			saramaConfig.Net.SASL.Enable = true
		case "SSL":
			saramaConfig.Net.TLS.Enable = true
			saramaConfig.Net.TLS.Config = &tls.Config{InsecureSkipVerify: false}
		}
	}

	if cfg.TLSEnabled {
		saramaConfig.Net.TLS.Enable = true
		saramaConfig.Net.TLS.Config = &tls.Config{InsecureSkipVerify: false}
	}

	// SASL settings
	if cfg.SASLMechanism != "" {
		saramaConfig.Net.SASL.Enable = true
		saramaConfig.Net.SASL.User = cfg.SASLUsername
		saramaConfig.Net.SASL.Password = cfg.SASLPassword

		switch cfg.SASLMechanism {
		case "PLAIN":
			saramaConfig.Net.SASL.Mechanism = sarama.SASLTypePlaintext
		case "SCRAM-SHA-256":
			saramaConfig.Net.SASL.Mechanism = sarama.SASLTypeSCRAMSHA256
		case "SCRAM-SHA-512":
			saramaConfig.Net.SASL.Mechanism = sarama.SASLTypeSCRAMSHA512
		default:
			return nil, fmt.Errorf("unsupported SASL mechanism: %s", cfg.SASLMechanism)
		}
	}

	producer, err := sarama.NewSyncProducer(cfg.Brokers, saramaConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create Kafka producer: %w", err)
	}

	return &Producer{
		producer:     producer,
		config:       cfg,
		saramaConfig: saramaConfig,
	}, nil
}

// SendMessage sends a message to Kafka
func (p *Producer) SendMessage(msg *models.WebhookMessage) error {
	kafkaMessage := &sarama.ProducerMessage{
		Topic:     msg.Queue,
		Key:       sarama.StringEncoder(msg.ID),
		Value:     sarama.ByteEncoder(msg.Body),
		Headers:   make([]sarama.RecordHeader, 0, len(msg.Headers)+2),
		Timestamp: msg.Timestamp,
	}

	// Add original headers
	for key, value := range msg.Headers {
		kafkaMessage.Headers = append(kafkaMessage.Headers, sarama.RecordHeader{
			Key:   []byte(key),
			Value: []byte(value),
		})
	}

	// Add metadata headers
	kafkaMessage.Headers = append(kafkaMessage.Headers,
		sarama.RecordHeader{
			Key:   []byte("X-Webhook-ID"),
			Value: []byte(msg.ID),
		},
		sarama.RecordHeader{
			Key:   []byte("X-Webhook-Path"),
			Value: []byte(msg.Path),
		},
	)

	partition, offset, err := p.producer.SendMessage(kafkaMessage)
	if err != nil {
		return fmt.Errorf("failed to send message to Kafka: %w", err)
	}

	log.Printf("Message sent to Kafka successfully - Topic: %s, Partition: %d, Offset: %d",
		msg.Queue, partition, offset)

	return nil
}

// SendMessageWithRetry sends a message with built-in retry logic
func (p *Producer) SendMessageWithRetry(msg *models.WebhookMessage) error {
	var lastErr error

	for attempt := 0; attempt <= p.config.RetryMax; attempt++ {
		if attempt > 0 {
			backoff := time.Duration(attempt) * p.config.RetryBackoff
			log.Printf("Retrying Kafka send for message %s, attempt %d/%d after %v",
				msg.ID, attempt, p.config.RetryMax, backoff)
			time.Sleep(backoff)
		}

		err := p.SendMessage(msg)
		if err == nil {
			return nil
		}

		lastErr = err
		log.Printf("Failed to send message %s to Kafka (attempt %d/%d): %v",
			msg.ID, attempt+1, p.config.RetryMax+1, err)
	}

	return fmt.Errorf("failed to send message after %d attempts: %w",
		p.config.RetryMax+1, lastErr)
}

// HealthCheck checks if Kafka is available
func (p *Producer) HealthCheck() error {
	// Try to get metadata for brokers
	client, err := sarama.NewClient(p.config.Brokers, p.saramaConfig)
	if err != nil {
		return fmt.Errorf("Kafka health check failed: %w", err)
	}
	defer client.Close()

	brokers := client.Brokers()
	if len(brokers) == 0 {
		return fmt.Errorf("no Kafka brokers available")
	}

	return nil
}

// Close closes the producer
func (p *Producer) Close() error {
	if p.producer != nil {
		return p.producer.Close()
	}
	return nil
}

// GetTopics returns list of available topics
func (p *Producer) GetTopics() ([]string, error) {
	client, err := sarama.NewClient(p.config.Brokers, p.saramaConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create Kafka client: %w", err)
	}
	defer client.Close()

	topics, err := client.Topics()
	if err != nil {
		return nil, fmt.Errorf("failed to get topics: %w", err)
	}

	return topics, nil
}
 