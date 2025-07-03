# Build stage
FROM golang:1.24-alpine AS builder

# Install necessary packages
RUN apk add --no-cache git gcc musl-dev sqlite-dev

# Set working directory
WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=1 GOOS=linux go build -a -installsuffix cgo -o messagebridge .

# Runtime stage
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates sqlite tzdata

# Create non-root user
RUN addgroup -g 1000 messagebridge && \
    adduser -D -s /bin/sh -u 1000 -G messagebridge messagebridge

# Create directories
RUN mkdir -p /var/lib/messagebridge /etc/messagebridge /var/log/messagebridge && \
    chown -R messagebridge:messagebridge /var/lib/messagebridge /var/log/messagebridge

# Copy binary from builder stage
COPY --from=builder /app/messagebridge /usr/local/bin/messagebridge

# Copy example configuration
COPY examples/simple-config.yaml /etc/messagebridge/config.yaml

# Set proper permissions
RUN chmod +x /usr/local/bin/messagebridge

# Switch to non-root user
USER messagebridge

# Set working directory
WORKDIR /home/messagebridge

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Expose port
EXPOSE 8080

# Volume for data persistence
VOLUME ["/var/lib/messagebridge"]

# Environment variables
ENV CONFIG_PATH="/etc/messagebridge/config.yaml"

# Start the application
CMD ["sh", "-c", "messagebridge -config ${CONFIG_PATH}"] 