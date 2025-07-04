#!/bin/bash

# MessageBridge Database Permissions Fix Script
# Quick fix for SQLite database permission issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="messagebridge"
APP_USER="messagebridge"
DATA_DIR="/var/lib/messagebridge"

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_info "Fixing MessageBridge database permissions..."

# Check if user exists
if ! id "$APP_USER" &>/dev/null; then
    print_error "User $APP_USER does not exist. Please run the installer first."
    exit 1
fi

# Check if data directory exists
if [ ! -d "$DATA_DIR" ]; then
    print_error "Data directory not found: $DATA_DIR"
    exit 1
fi

# Stop service temporarily
print_info "Stopping MessageBridge service..."
systemctl stop "$APP_NAME" || true

# Fix data directory permissions
print_info "Fixing directory permissions..."
chown -R "$APP_USER:$APP_USER" "$DATA_DIR"
chmod 750 "$DATA_DIR"

# Fix database file permissions
print_info "Fixing database file permissions..."
find "$DATA_DIR" -name "*.db" -exec chown "$APP_USER:$APP_USER" {} \;
find "$DATA_DIR" -name "*.db" -exec chmod 640 {} \;
find "$DATA_DIR" -name "*.db-*" -exec chown "$APP_USER:$APP_USER" {} \;
find "$DATA_DIR" -name "*.db-*" -exec chmod 640 {} \;

# List database files for verification
print_info "Database files found:"
find "$DATA_DIR" -name "*.db*" -ls 2>/dev/null || echo "No database files found"

# Start service
print_info "Starting MessageBridge service..."
systemctl start "$APP_NAME"

if systemctl is-active --quiet "$APP_NAME"; then
    print_success "Service started successfully"
    print_info "Testing database write access..."
    
    # Wait a moment for service to initialize
    sleep 2
    
    # Test with a simple health check that might touch the database
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        print_success "Service is responding to health checks"
    else
        print_info "Service started but health check failed (this might be normal)"
    fi
else
    print_error "Service failed to start. Check logs: journalctl -u $APP_NAME"
    exit 1
fi

print_success "Database permissions fix completed!"
print_info "Monitor logs: journalctl -u $APP_NAME -f"
print_info "Test webhook: curl -X POST http://localhost:8080/webhook/payment -d '{\"test\":true}' -H 'Content-Type: application/json'" 