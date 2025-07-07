package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/expai/messagebridge/config"
	"github.com/expai/messagebridge/handler"
	"github.com/expai/messagebridge/httpclient"
	"github.com/expai/messagebridge/internal/interfaces"
	"github.com/expai/messagebridge/kafka"
	"github.com/expai/messagebridge/server"
	"github.com/expai/messagebridge/storage"
	"github.com/expai/messagebridge/worker"
)

const (
	ExitSuccess = 0
	ExitFailure = 1
	ExitRestart = 2 // Signal for restart
)

var (
	configPath = flag.String("config", "", "Path to configuration file (required)")
	version    = "1.0.0"
	buildTime  = "unknown"
)

func main() {
	flag.Parse()

	if *configPath == "" {
		fmt.Println("Error: -config flag is required")
		fmt.Println("Usage: messagebridge -config /path/to/config.yaml")
		os.Exit(ExitFailure)
	}

	// Set up panic recovery
	defer func() {
		if r := recover(); r != nil {
			log.Printf("PANIC: %v", r)
			log.Println("Application will restart...")
			os.Exit(ExitRestart)
		}
	}()

	exitCode := run(*configPath)
	os.Exit(exitCode)
}

func run(configPath string) int {
	log.Printf("Starting messagebridge v%s (built at %s)", version, buildTime)
	log.Printf("Loading configuration from: %s", configPath)

	// Load configuration
	cfg, err := config.LoadConfig(configPath)
	if err != nil {
		log.Printf("Failed to load configuration: %v", err)
		return ExitFailure
	}

	log.Println("Configuration loaded successfully")

	// Initialize components
	app, err := initializeApplication(cfg)
	if err != nil {
		log.Printf("Failed to initialize application: %v", err)
		return ExitRestart // Try to restart on initialization failure
	}

	// Start application
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Set up signal handling for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)

	// Start components
	if err := app.Start(ctx); err != nil {
		log.Printf("Failed to start application: %v", err)
		return ExitRestart
	}

	log.Println("Application started successfully")

	// Wait for shutdown signal
	sig := <-sigChan
	log.Printf("Received signal: %v", sig)

	// Handle different signals
	switch sig {
	case syscall.SIGHUP:
		log.Println("Received SIGHUP, restarting...")
		app.Shutdown()
		return ExitRestart
	default:
		log.Println("Shutting down gracefully...")
		app.Shutdown()
		return ExitSuccess
	}
}

// Application represents the main application
type Application struct {
	config        *config.Config
	server        *server.Server
	worker        *worker.Worker
	handler       interfaces.WebhookHandler
	kafkaProducer interfaces.MessageProducer
	httpClient    interfaces.HTTPSender
	storage       interfaces.MessageStorage
	wg            sync.WaitGroup
}

// initializeApplication initializes all application components
func initializeApplication(cfg *config.Config) (*Application, error) {
	app := &Application{
		config: cfg,
	}

	// Initialize SQLite storage if configured
	if cfg.SQLite != nil {
		storage, err := storage.NewSQLiteStorage(cfg.SQLite.DatabasePath)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize SQLite storage: %w", err)
		}
		app.storage = storage
		log.Println("SQLite storage initialized")
	}

	// Initialize Kafka producer
	if cfg.Kafka != nil {
		producer, err := kafka.NewProducer(cfg.Kafka)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize Kafka producer: %w", err)
		}
		app.kafkaProducer = producer
		log.Println("Kafka producer initialized")
	}

	// Initialize HTTP client for remote URL if configured
	if cfg.RemoteURL != nil {
		client := httpclient.NewClient(cfg.RemoteURL)
		app.httpClient = client
		log.Println("HTTP client initialized")
	}

	// Initialize message handler
	app.handler = handler.NewMessageHandler(cfg, app.kafkaProducer, app.httpClient, app.storage)
	log.Println("Message handler initialized")

	// Initialize HTTP server
	app.server = server.NewServer(cfg, app.handler)
	log.Println("HTTP server initialized")

	// Initialize worker if storage is available
	if app.storage != nil {
		app.worker = worker.NewWorker(cfg, app.storage, app.kafkaProducer, app.httpClient)
		log.Println("Worker initialized")
	}

	return app, nil
}

// Start starts all application components
func (app *Application) Start(ctx context.Context) error {
	// Start worker if available
	if app.worker != nil {
		app.wg.Add(1)
		go func() {
			defer app.wg.Done()
			app.worker.Start(ctx)
		}()
	}

	// Start HTTP server
	app.wg.Add(1)
	go func() {
		defer app.wg.Done()
		if err := app.server.Start(); err != nil {
			log.Printf("HTTP server error: %v", err)
		}
	}()

	// Health monitoring
	app.wg.Add(1)
	go func() {
		defer app.wg.Done()
		app.healthMonitor(ctx)
	}()

	// Cleanup routine
	if app.storage != nil {
		app.wg.Add(1)
		go func() {
			defer app.wg.Done()
			app.cleanupRoutine(ctx)
		}()
	}

	return nil
}

// Shutdown gracefully shuts down the application
func (app *Application) Shutdown() {
	log.Println("Initiating graceful shutdown...")

	// Create shutdown context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Stop HTTP server
	if app.server != nil {
		if err := app.server.Shutdown(ctx); err != nil {
			log.Printf("Error shutting down server: %v", err)
		}
	}

	// Stop worker
	if app.worker != nil {
		app.worker.Stop()
	}

	// Wait for all goroutines to finish
	done := make(chan struct{})
	go func() {
		app.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		log.Println("All components stopped")
	case <-ctx.Done():
		log.Println("Shutdown timeout reached")
	}

	// Close resources
	app.closeResources()

	log.Println("Shutdown completed")
}

// closeResources closes all open resources
func (app *Application) closeResources() {
	if app.kafkaProducer != nil {
		if err := app.kafkaProducer.Close(); err != nil {
			log.Printf("Error closing Kafka producer: %v", err)
		}
	}

	if app.storage != nil {
		if err := app.storage.Close(); err != nil {
			log.Printf("Error closing storage: %v", err)
		}
	}
}

// healthMonitor monitors the health of the application
func (app *Application) healthMonitor(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			app.performHealthCheck()
		}
	}
}

// performHealthCheck performs a health check
func (app *Application) performHealthCheck() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Health check panic: %v", r)
		}
	}()

	health := app.handler.HealthCheck()

	// Check for critical failures
	criticalFailure := false
	for component, status := range health {
		if statusMap, ok := status.(map[string]interface{}); ok {
			if statusMap["status"] == "unhealthy" && component == "kafka" {
				log.Printf("Critical component %s is unhealthy: %v", component, statusMap["error"])
				criticalFailure = true
			}
		}
	}

	if criticalFailure {
		log.Println("Critical failure detected, application should restart")
		// Don't panic here, let the monitoring system handle restart
	}

	log.Printf("Health check completed: %d components checked", len(health))
}

// cleanupRoutine performs periodic cleanup
func (app *Application) cleanupRoutine(ctx context.Context) {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if app.worker != nil {
				if err := app.worker.Cleanup(); err != nil {
					log.Printf("Cleanup error: %v", err)
				}
			}
		}
	}
}
