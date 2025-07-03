package storage

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/expai/messagebridge/models"

	_ "github.com/mattn/go-sqlite3"
)

// SQLiteStorage represents SQLite storage for messages
type SQLiteStorage struct {
	db   *sql.DB
	path string
}

// NewSQLiteStorage creates a new SQLite storage instance
func NewSQLiteStorage(dbPath string) (*SQLiteStorage, error) {
	// Create directory if it doesn't exist
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create database directory: %w", err)
	}

	db, err := sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_synchronous=NORMAL&_cache_size=-64000")
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	storage := &SQLiteStorage{
		db:   db,
		path: dbPath,
	}

	if err := storage.createTables(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to create tables: %w", err)
	}

	return storage, nil
}

// createTables creates the necessary tables
func (s *SQLiteStorage) createTables() error {
	query := `
	CREATE TABLE IF NOT EXISTS messages (
		id TEXT PRIMARY KEY,
		path TEXT NOT NULL,
		queue TEXT NOT NULL,
		body BLOB NOT NULL,
		headers TEXT NOT NULL,
		timestamp DATETIME NOT NULL,
		retries INTEGER DEFAULT 0,
		status TEXT NOT NULL,
		error TEXT,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		next_retry_at DATETIME
	);

	CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(status);
	CREATE INDEX IF NOT EXISTS idx_messages_next_retry ON messages(next_retry_at);
	CREATE INDEX IF NOT EXISTS idx_messages_queue ON messages(queue);
	`

	_, err := s.db.Exec(query)
	return err
}

// SaveMessage saves a message to storage
func (s *SQLiteStorage) SaveMessage(msg *models.WebhookMessage) error {
	headersJSON, err := json.Marshal(msg.Headers)
	if err != nil {
		return fmt.Errorf("failed to marshal headers: %w", err)
	}

	query := `
	INSERT OR REPLACE INTO messages 
	(id, path, queue, body, headers, timestamp, retries, status, error, created_at, updated_at, next_retry_at)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`

	nextRetryAt := sql.NullTime{}
	if msg.Status == models.StatusRetrying {
		nextRetryAt = sql.NullTime{
			Time:  time.Now().Add(time.Duration(msg.Retries*2) * time.Minute),
			Valid: true,
		}
	}

	_, err = s.db.Exec(query,
		msg.ID, msg.Path, msg.Queue, msg.Body, string(headersJSON),
		msg.Timestamp, msg.Retries, msg.Status, msg.Error,
		msg.CreatedAt, msg.UpdatedAt, nextRetryAt,
	)

	return err
}

// GetPendingMessages retrieves messages that need retry
func (s *SQLiteStorage) GetPendingMessages(limit int) ([]*models.PendingMessage, error) {
	query := `
	SELECT id, path, queue, body, headers, timestamp, retries, status, error, 
	       created_at, updated_at, next_retry_at
	FROM messages 
	WHERE status IN (?, ?) AND (next_retry_at IS NULL OR next_retry_at <= ?)
	ORDER BY created_at ASC
	LIMIT ?
	`

	rows, err := s.db.Query(query, models.StatusPending, models.StatusRetrying, time.Now(), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []*models.PendingMessage
	for rows.Next() {
		msg := &models.PendingMessage{
			WebhookMessage: &models.WebhookMessage{},
		}

		var headersJSON string
		var nextRetryAt sql.NullTime

		err := rows.Scan(
			&msg.ID, &msg.Path, &msg.Queue, &msg.Body, &headersJSON,
			&msg.Timestamp, &msg.Retries, &msg.Status, &msg.Error,
			&msg.CreatedAt, &msg.UpdatedAt, &nextRetryAt,
		)
		if err != nil {
			return nil, err
		}

		if err := json.Unmarshal([]byte(headersJSON), &msg.Headers); err != nil {
			return nil, fmt.Errorf("failed to unmarshal headers: %w", err)
		}

		if nextRetryAt.Valid {
			msg.NextRetryAt = nextRetryAt.Time
		}

		messages = append(messages, msg)
	}

	return messages, rows.Err()
}

// UpdateMessageStatus updates message status
func (s *SQLiteStorage) UpdateMessageStatus(id string, status models.MessageStatus, error string) error {
	query := `
	UPDATE messages 
	SET status = ?, error = ?, updated_at = ?, retries = retries + 1,
	    next_retry_at = CASE 
			WHEN ? = 'retrying' THEN datetime('now', '+' || (retries + 1) * 2 || ' minutes')
			ELSE NULL 
		END
	WHERE id = ?
	`

	_, err := s.db.Exec(query, status, error, time.Now(), status, id)
	return err
}

// DeleteMessage removes a message from storage
func (s *SQLiteStorage) DeleteMessage(id string) error {
	query := `DELETE FROM messages WHERE id = ?`
	_, err := s.db.Exec(query, id)
	return err
}

// GetMessageStats returns statistics about stored messages
func (s *SQLiteStorage) GetMessageStats() (map[string]int, error) {
	query := `
	SELECT status, COUNT(*) as count 
	FROM messages 
	GROUP BY status
	`

	rows, err := s.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	stats := make(map[string]int)
	for rows.Next() {
		var status string
		var count int
		if err := rows.Scan(&status, &count); err != nil {
			return nil, err
		}
		stats[status] = count
	}

	return stats, rows.Err()
}

// Close closes the database connection
func (s *SQLiteStorage) Close() error {
	return s.db.Close()
}

// Cleanup removes old messages based on retention policy
func (s *SQLiteStorage) Cleanup(retentionDays int) error {
	query := `
	DELETE FROM messages 
	WHERE status = ? AND created_at < datetime('now', '-' || ? || ' days')
	`

	_, err := s.db.Exec(query, models.StatusSent, retentionDays)
	return err
}
