#!/bin/bash

# MessageBridge Permissions Fix Script
# Quick fix for permission issues on existing installations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="messagebridge"
APP_USER="messagebridge"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/messagebridge"
DATA_DIR="/var/lib/messagebridge"
LOG_DIR="/var/log/messagebridge"

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

print_info "Fixing MessageBridge permissions..."

# Check if user exists
if ! id "$APP_USER" &>/dev/null; then
    print_error "User $APP_USER does not exist. Please run the installer first."
    exit 1
fi

# Fix directory permissions
if [ -d "$CONFIG_DIR" ]; then
    chown root:$APP_USER "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"
    print_success "Fixed config directory permissions: $CONFIG_DIR"
else
    print_error "Config directory not found: $CONFIG_DIR"
fi

if [ -d "$DATA_DIR" ]; then
    chown "$APP_USER:$APP_USER" "$DATA_DIR"
    chmod 750 "$DATA_DIR"
    print_success "Fixed data directory permissions: $DATA_DIR"
fi

if [ -d "$LOG_DIR" ]; then
    chown "$APP_USER:$APP_USER" "$LOG_DIR"
    chmod 750 "$LOG_DIR"
    print_success "Fixed log directory permissions: $LOG_DIR"
fi

# Fix config file permissions
if [ -f "$CONFIG_DIR/config.yaml" ]; then
    chown root:$APP_USER "$CONFIG_DIR/config.yaml"
    chmod 640 "$CONFIG_DIR/config.yaml"
    print_success "Fixed config file permissions: $CONFIG_DIR/config.yaml"
else
    print_error "Config file not found: $CONFIG_DIR/config.yaml"
fi

# Fix binary permissions
if [ -f "$INSTALL_DIR/$APP_NAME" ]; then
    chmod +x "$INSTALL_DIR/$APP_NAME"
    print_success "Fixed binary permissions: $INSTALL_DIR/$APP_NAME"
else
    print_error "Binary not found: $INSTALL_DIR/$APP_NAME"
fi

# Stop and restart service if running
if systemctl is-active --quiet "$APP_NAME"; then
    print_info "Restarting $APP_NAME service..."
    systemctl restart "$APP_NAME"
    
    if systemctl is-active --quiet "$APP_NAME"; then
        print_success "Service restarted successfully"
    else
        print_error "Service failed to restart. Check logs: journalctl -u $APP_NAME"
    fi
else
    print_info "Starting $APP_NAME service..."
    systemctl start "$APP_NAME"
    
    if systemctl is-active --quiet "$APP_NAME"; then
        print_success "Service started successfully"
    else
        print_error "Service failed to start. Check logs: journalctl -u $APP_NAME"
    fi
fi

print_success "Permissions fix completed!"
print_info "Service status: systemctl status $APP_NAME"
print_info "Check logs: journalctl -u $APP_NAME -f" 