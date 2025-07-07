package errors

import (
	"fmt"
)

// Error types for different categories of errors
type ErrorType string

const (
	ErrorTypeConfig     ErrorType = "CONFIG"
	ErrorTypeStorage    ErrorType = "STORAGE"
	ErrorTypeKafka      ErrorType = "KAFKA"
	ErrorTypeHTTP       ErrorType = "HTTP"
	ErrorTypeValidation ErrorType = "VALIDATION"
	ErrorTypeInternal   ErrorType = "INTERNAL"
)

// ApplicationError represents a structured application error
type ApplicationError struct {
	Type    ErrorType `json:"type"`
	Message string    `json:"message"`
	Details string    `json:"details,omitempty"`
	Cause   error     `json:"-"`
}

func (e *ApplicationError) Error() string {
	if e.Details != "" {
		return fmt.Sprintf("[%s] %s: %s", e.Type, e.Message, e.Details)
	}
	return fmt.Sprintf("[%s] %s", e.Type, e.Message)
}

func (e *ApplicationError) Unwrap() error {
	return e.Cause
}

// NewConfigError creates a new configuration error
func NewConfigError(message string, cause error) *ApplicationError {
	return &ApplicationError{
		Type:    ErrorTypeConfig,
		Message: message,
		Cause:   cause,
	}
}

// NewStorageError creates a new storage error
func NewStorageError(message string, cause error) *ApplicationError {
	return &ApplicationError{
		Type:    ErrorTypeStorage,
		Message: message,
		Cause:   cause,
	}
}

// NewKafkaError creates a new Kafka error
func NewKafkaError(message string, cause error) *ApplicationError {
	return &ApplicationError{
		Type:    ErrorTypeKafka,
		Message: message,
		Cause:   cause,
	}
}

// NewHTTPError creates a new HTTP error
func NewHTTPError(message string, cause error) *ApplicationError {
	return &ApplicationError{
		Type:    ErrorTypeHTTP,
		Message: message,
		Cause:   cause,
	}
}

// NewValidationError creates a new validation error
func NewValidationError(message string, details string) *ApplicationError {
	return &ApplicationError{
		Type:    ErrorTypeValidation,
		Message: message,
		Details: details,
	}
}

// NewInternalError creates a new internal error
func NewInternalError(message string, cause error) *ApplicationError {
	return &ApplicationError{
		Type:    ErrorTypeInternal,
		Message: message,
		Cause:   cause,
	}
}

// IsType checks if an error is of a specific type
func IsType(err error, errorType ErrorType) bool {
	var appErr *ApplicationError
	if As(err, &appErr) {
		return appErr.Type == errorType
	}
	return false
}

// As is a wrapper around errors.As for convenience
func As(err error, target interface{}) bool {
	if err == nil {
		return false
	}

	switch t := target.(type) {
	case **ApplicationError:
		if appErr, ok := err.(*ApplicationError); ok {
			*t = appErr
			return true
		}
	}
	return false
}
