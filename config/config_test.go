package config

import (
	"os"
	"testing"
	"time"
)

func TestValidate(t *testing.T) {
	tests := []struct {
		name    string
		config  Config
		wantErr bool
		errMsg  string
	}{
		{
			name: "valid config",
			config: Config{
				Server: ServerConfig{
					Host: "localhost",
					Port: 8080,
				},
				Routes: []RouteConfig{
					{Path: "/webhook/test", Queue: "test-queue"},
				},
			},
			wantErr: false,
		},
		{
			name: "missing server host",
			config: Config{
				Server: ServerConfig{
					Port: 8080,
				},
				Routes: []RouteConfig{
					{Path: "/webhook/test", Queue: "test-queue"},
				},
			},
			wantErr: true,
			errMsg:  "server.host is required",
		},
		{
			name: "missing server port",
			config: Config{
				Server: ServerConfig{
					Host: "localhost",
				},
				Routes: []RouteConfig{
					{Path: "/webhook/test", Queue: "test-queue"},
				},
			},
			wantErr: true,
			errMsg:  "server.port is required",
		},
		{
			name: "no routes",
			config: Config{
				Server: ServerConfig{
					Host: "localhost",
					Port: 8080,
				},
				Routes: []RouteConfig{},
			},
			wantErr: true,
			errMsg:  "at least one route must be configured",
		},
		{
			name: "route missing path",
			config: Config{
				Server: ServerConfig{
					Host: "localhost",
					Port: 8080,
				},
				Routes: []RouteConfig{
					{Queue: "test-queue"},
				},
			},
			wantErr: true,
			errMsg:  "route[0].path is required",
		},
		{
			name: "route missing queue",
			config: Config{
				Server: ServerConfig{
					Host: "localhost",
					Port: 8080,
				},
				Routes: []RouteConfig{
					{Path: "/webhook/test"},
				},
			},
			wantErr: true,
			errMsg:  "route[0].queue is required",
		},
		{
			name: "remote URL without SQLite",
			config: Config{
				Server: ServerConfig{
					Host: "localhost",
					Port: 8080,
				},
				Routes: []RouteConfig{
					{Path: "/webhook/test", Queue: "test-queue"},
				},
				RemoteURL: &RemoteURLConfig{
					URL: "http://example.com",
				},
			},
			wantErr: true,
			errMsg:  "sqlite configuration is required when remote_url is specified",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.Validate()

			if tt.wantErr && err == nil {
				t.Errorf("Validate() expected error but got none")
			}
			if !tt.wantErr && err != nil {
				t.Errorf("Validate() unexpected error: %v", err)
			}
			if tt.wantErr && err != nil && err.Error() != tt.errMsg {
				t.Errorf("Validate() error = %v, want %v", err.Error(), tt.errMsg)
			}
		})
	}
}

func TestSetDefaults(t *testing.T) {
	config := &Config{
		Kafka:     &KafkaConfig{},
		RemoteURL: &RemoteURLConfig{},
		Worker:    WorkerConfig{},
	}

	config.setDefaults()

	// Test Kafka defaults
	if config.Kafka.RetryMax != 3 {
		t.Errorf("setDefaults() Kafka.RetryMax = %d, want 3", config.Kafka.RetryMax)
	}
	if config.Kafka.RetryBackoff != time.Second*2 {
		t.Errorf("setDefaults() Kafka.RetryBackoff = %v, want %v", config.Kafka.RetryBackoff, time.Second*2)
	}
	if config.Kafka.BatchSize != 100 {
		t.Errorf("setDefaults() Kafka.BatchSize = %d, want 100", config.Kafka.BatchSize)
	}
	if config.Kafka.Timeout != time.Second*30 {
		t.Errorf("setDefaults() Kafka.Timeout = %v, want %v", config.Kafka.Timeout, time.Second*30)
	}

	// Test RemoteURL defaults
	if config.RemoteURL.Timeout != time.Second*30 {
		t.Errorf("setDefaults() RemoteURL.Timeout = %v, want %v", config.RemoteURL.Timeout, time.Second*30)
	}
	if config.RemoteURL.Retries != 3 {
		t.Errorf("setDefaults() RemoteURL.Retries = %d, want 3", config.RemoteURL.Retries)
	}

	// Test Worker defaults
	if config.Worker.RetryInterval != time.Minute*5 {
		t.Errorf("setDefaults() Worker.RetryInterval = %v, want %v", config.Worker.RetryInterval, time.Minute*5)
	}
	if config.Worker.BatchSize != 50 {
		t.Errorf("setDefaults() Worker.BatchSize = %d, want 50", config.Worker.BatchSize)
	}
}

func TestLoadConfig(t *testing.T) {
	// Create a temporary config file
	configContent := `
server:
  host: localhost
  port: 8080

routes:
  - path: /webhook/test
    queue: test-queue

kafka:
  brokers:
    - localhost:9092

worker:
  retry_interval: 5m
  batch_size: 50
`

	tmpfile, err := os.CreateTemp("", "config_test_*.yaml")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(tmpfile.Name())

	if _, err := tmpfile.Write([]byte(configContent)); err != nil {
		t.Fatal(err)
	}
	if err := tmpfile.Close(); err != nil {
		t.Fatal(err)
	}

	// Test loading the config
	config, err := LoadConfig(tmpfile.Name())
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}

	// Verify config values
	if config.Server.Host != "localhost" {
		t.Errorf("LoadConfig() Server.Host = %s, want localhost", config.Server.Host)
	}
	if config.Server.Port != 8080 {
		t.Errorf("LoadConfig() Server.Port = %d, want 8080", config.Server.Port)
	}
	if len(config.Routes) != 1 {
		t.Errorf("LoadConfig() Routes length = %d, want 1", len(config.Routes))
	}
	if config.Routes[0].Path != "/webhook/test" {
		t.Errorf("LoadConfig() Routes[0].Path = %s, want /webhook/test", config.Routes[0].Path)
	}
	if config.Routes[0].Queue != "test-queue" {
		t.Errorf("LoadConfig() Routes[0].Queue = %s, want test-queue", config.Routes[0].Queue)
	}
}

func TestLoadConfigFileNotFound(t *testing.T) {
	_, err := LoadConfig("nonexistent.yaml")
	if err == nil {
		t.Error("LoadConfig() expected error for nonexistent file but got none")
	}
}
