package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// Config represents the main configuration structure
type Config struct {
	Server    ServerConfig     `yaml:"server"`
	Routes    []RouteConfig    `yaml:"routes"`
	Kafka     *KafkaConfig     `yaml:"kafka,omitempty"`
	Redis     *RedisConfig     `yaml:"redis,omitempty"`
	SQLite    *SQLiteConfig    `yaml:"sqlite,omitempty"`
	RemoteURL *RemoteURLConfig `yaml:"remote_url,omitempty"`
	Worker    WorkerConfig     `yaml:"worker"`
	Nginx     *NginxConfig     `yaml:"nginx,omitempty"`
}

// ServerConfig contains server settings
type ServerConfig struct {
	Host string `yaml:"host"`
	Port int    `yaml:"port"`
}

// RouteConfig defines webhook routes and their target queues
type RouteConfig struct {
	Path  string `yaml:"path"`
	Queue string `yaml:"queue"`
}

// KafkaConfig contains Kafka connection settings
type KafkaConfig struct {
	Brokers          []string      `yaml:"brokers"`
	SecurityProtocol string        `yaml:"security_protocol,omitempty"`
	SASLMechanism    string        `yaml:"sasl_mechanism,omitempty"`
	SASLUsername     string        `yaml:"sasl_username,omitempty"`
	SASLPassword     string        `yaml:"sasl_password,omitempty"`
	TLSEnabled       bool          `yaml:"tls_enabled"`
	RetryMax         int           `yaml:"retry_max"`
	RetryBackoff     time.Duration `yaml:"retry_backoff"`
	BatchSize        int           `yaml:"batch_size"`
	Timeout          time.Duration `yaml:"timeout"`
}

// RedisConfig contains Redis connection settings
type RedisConfig struct {
	Address  string `yaml:"address"`
	Password string `yaml:"password,omitempty"`
	Database int    `yaml:"database"`
}

// SQLiteConfig contains SQLite settings
type SQLiteConfig struct {
	DatabasePath string `yaml:"database_path"`
}

// RemoteURLConfig contains remote URL forwarding settings
type RemoteURLConfig struct {
	URL     string        `yaml:"url"`
	Timeout time.Duration `yaml:"timeout"`
	Retries int           `yaml:"retries"`
}

// WorkerConfig contains background worker settings
type WorkerConfig struct {
	RetryInterval time.Duration `yaml:"retry_interval"`
	BatchSize     int           `yaml:"batch_size"`
	MaxRetries    int           `yaml:"max_retries"`
}

// NginxConfig contains nginx configuration settings for auto-setup
type NginxConfig struct {
	Domain            string `yaml:"domain"`
	SSLCertificate    string `yaml:"ssl_certificate,omitempty"`
	SSLCertificateKey string `yaml:"ssl_certificate_key,omitempty"`
}

// LoadConfig loads configuration from file
func LoadConfig(configPath string) (*Config, error) {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	if err := config.Validate(); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	// Set defaults
	config.setDefaults()

	return &config, nil
}

// Validate validates the configuration
func (c *Config) Validate() error {
	// Validate required server settings
	if c.Server.Host == "" {
		return fmt.Errorf("server.host is required")
	}
	if c.Server.Port == 0 {
		return fmt.Errorf("server.port is required")
	}

	// Validate routes
	if len(c.Routes) == 0 {
		return fmt.Errorf("at least one route must be configured")
	}

	for i, route := range c.Routes {
		if route.Path == "" {
			return fmt.Errorf("route[%d].path is required", i)
		}
		if route.Queue == "" {
			return fmt.Errorf("route[%d].queue is required", i)
		}
	}

	// Validate that at least Kafka is configured
	// if c.Kafka == nil {
	// 	return fmt.Errorf("kafka configuration is required")
	// }

	// Validate Kafka settings
	// if len(c.Kafka.Brokers) == 0 {
	// 	return fmt.Errorf("kafka.brokers is required")
	// }

	// Validate remote URL settings
	if c.RemoteURL != nil && c.SQLite == nil {
		return fmt.Errorf("sqlite configuration is required when remote_url is specified")
	}

	return nil
}

// setDefaults sets default values for optional settings
func (c *Config) setDefaults() {
	// Kafka defaults
	if c.Kafka != nil {
		if c.Kafka.RetryMax == 0 {
			c.Kafka.RetryMax = 3
		}
		if c.Kafka.RetryBackoff == 0 {
			c.Kafka.RetryBackoff = time.Second * 2
		}
		if c.Kafka.BatchSize == 0 {
			c.Kafka.BatchSize = 100
		}
		if c.Kafka.Timeout == 0 {
			c.Kafka.Timeout = time.Second * 30
		}
	}

	// Remote URL defaults
	if c.RemoteURL != nil {
		if c.RemoteURL.Timeout == 0 {
			c.RemoteURL.Timeout = time.Second * 30
		}
		if c.RemoteURL.Retries == 0 {
			c.RemoteURL.Retries = 3
		}
	}

	// Worker defaults
	if c.Worker.RetryInterval == 0 {
		c.Worker.RetryInterval = time.Minute * 5
	}
	if c.Worker.BatchSize == 0 {
		c.Worker.BatchSize = 50
	}
	// if c.Worker.MaxRetries == 0 {
	// 	c.Worker.MaxRetries = 5
	// }
}
