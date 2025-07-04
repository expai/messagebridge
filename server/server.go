package server

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/expai/messagebridge/config"
	"github.com/expai/messagebridge/models"

	"github.com/gorilla/mux"
)

// WebhookHandler interface for processing webhooks
type WebhookHandler interface {
	ProcessWebhook(msg *models.WebhookMessage) error
}

// Server represents HTTP server for webhook reception
type Server struct {
	server   *http.Server
	router   *mux.Router
	config   *config.Config
	handler  WebhookHandler
	routeMap map[string]string // path -> queue mapping
}

// NewServer creates a new HTTP server
func NewServer(cfg *config.Config, handler WebhookHandler) *Server {
	router := mux.NewRouter()

	// Build route mapping
	routeMap := make(map[string]string)
	for _, route := range cfg.Routes {
		routeMap[route.Path] = route.Queue
	}

	server := &Server{
		router:   router,
		config:   cfg,
		handler:  handler,
		routeMap: routeMap,
	}

	server.setupRoutes()

	httpServer := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port),
		Handler:      router,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	server.server = httpServer
	return server
}

// setupRoutes configures HTTP routes
func (s *Server) setupRoutes() {
	// Health check endpoint
	s.router.HandleFunc("/health", s.healthHandler).Methods("GET")

	// Status endpoint
	s.router.HandleFunc("/status", s.statusHandler).Methods("GET")

	// Webhook endpoints
	for _, route := range s.config.Routes {
		s.router.HandleFunc(route.Path, s.webhookHandler).Methods("POST")
		log.Printf("Registered webhook route: %s -> queue: %s", route.Path, route.Queue)
	}

	// Middleware
	s.router.Use(s.loggingMiddleware)
	s.router.Use(s.recoveryMiddleware)
}

// webhookHandler handles incoming webhook requests
func (s *Server) webhookHandler(w http.ResponseWriter, r *http.Request) {
	// Generate unique message ID
	msgID, err := generateID()
	if err != nil {
		http.Error(w, "Failed to generate message ID", http.StatusInternalServerError)
		return
	}

	// Read request body
	body, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("Failed to read request body for %s: %v", msgID, err)
		http.Error(w, "Failed to read request body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	// Extract headers
	headers := make(map[string]string)
	for key, values := range r.Header {
		if len(values) > 0 {
			headers[key] = values[0]
		}
	}

	// Get queue for this path
	queue, exists := s.routeMap[r.URL.Path]
	if !exists {
		log.Printf("No queue configured for path %s", r.URL.Path)
		http.Error(w, "Path not configured", http.StatusNotFound)
		return
	}

	// Create webhook message
	msg := &models.WebhookMessage{
		ID:        msgID,
		Path:      r.URL.Path,
		Queue:     queue,
		Body:      body,
		Headers:   headers,
		Timestamp: time.Now(),
		Status:    models.StatusPending,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	// Process webhook
	if err := s.handler.ProcessWebhook(msg); err != nil {
		log.Printf("Failed to process webhook %s: %v", msgID, err)
		http.Error(w, "Failed to process webhook", http.StatusInternalServerError)
		return
	}

	// Return success response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	response := map[string]interface{}{
		"message_id": msgID,
		"status":     "accepted",
		"timestamp":  time.Now().Format(time.RFC3339),
	}

	json.NewEncoder(w).Encode(response)
	log.Printf("Webhook %s processed successfully", msgID)
}

// healthHandler handles health check requests
func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	response := map[string]interface{}{
		"status":    "healthy",
		"timestamp": time.Now().Format(time.RFC3339),
		"version":   "1.0.0",
	}

	json.NewEncoder(w).Encode(response)
}

// statusHandler handles status requests
func (s *Server) statusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	response := map[string]interface{}{
		"status":    "running",
		"timestamp": time.Now().Format(time.RFC3339),
		"routes":    s.config.Routes,
		"server": map[string]interface{}{
			"host": s.config.Server.Host,
			"port": s.config.Server.Port,
		},
	}

	json.NewEncoder(w).Encode(response)
}

// loggingMiddleware logs HTTP requests
func (s *Server) loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Create a response writer wrapper to capture status
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(rw, r)

		duration := time.Since(start)
		log.Printf("%s %s %d %v %s", r.Method, r.URL.Path, rw.statusCode, duration, r.RemoteAddr)
	})
}

// recoveryMiddleware recovers from panics
func (s *Server) recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				log.Printf("Panic recovered: %v", err)
				http.Error(w, "Internal server error", http.StatusInternalServerError)
			}
		}()

		next.ServeHTTP(w, r)
	})
}

// Start starts the HTTP server
func (s *Server) Start() error {
	log.Printf("Starting HTTP server on %s:%d", s.config.Server.Host, s.config.Server.Port)
	return s.server.ListenAndServe()
}

// Shutdown gracefully shuts down the server
func (s *Server) Shutdown(ctx context.Context) error {
	log.Println("Shutting down HTTP server...")
	return s.server.Shutdown(ctx)
}

// responseWriter wraps http.ResponseWriter to capture status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// generateID generates a unique message ID
func generateID() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}
 