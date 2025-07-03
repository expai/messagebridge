#!/bin/bash

# MessageBridge Uninstaller
# Removes all components installed by install.sh

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
SYSTEMD_DIR="/etc/systemd/system"

# Flags
REMOVE_DATA=false
REMOVE_NGINX=false
FORCE_REMOVE=false

print_header() {
    echo -e "${RED}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║         MessageBridge Uninstaller            ║"
    echo "║           ⚠️  WARNING: DESTRUCTIVE  ⚠️         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --remove-data     Remove all data and logs (DESTRUCTIVE!)"
    echo "  --remove-nginx    Remove nginx configuration"
    echo "  --force          Force removal without confirmation"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Remove application only"
    echo "  $0 --remove-data        # Remove everything including data"
    echo "  $0 --remove-nginx       # Remove app and nginx config"
    echo "  $0 --force --remove-data # Force complete removal"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remove-data)
                REMOVE_DATA=true
                shift
                ;;
            --remove-nginx)
                REMOVE_NGINX=true
                shift
                ;;
            --force)
                FORCE_REMOVE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Confirmation prompt
confirm_removal() {
    if [[ "$FORCE_REMOVE" == true ]]; then
        return 0
    fi

    echo ""
    print_warning "This will remove MessageBridge from your system!"
    
    if [[ "$REMOVE_DATA" == true ]]; then
        print_error "⚠️  ALL DATA AND LOGS WILL BE PERMANENTLY DELETED!"
    fi
    
    if [[ "$REMOVE_NGINX" == true ]]; then
        print_warning "Nginx configuration will be removed"
    fi

    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY == "yes" ]]; then
        print_info "Uninstallation cancelled"
        exit 0
    fi
}

# Stop services
stop_services() {
    print_info "Stopping services..."

    # Stop messagebridge service
    if systemctl is-active --quiet "$APP_NAME" 2>/dev/null; then
        systemctl stop "$APP_NAME"
        print_success "Stopped $APP_NAME service"
    fi

    # Disable service
    if systemctl is-enabled --quiet "$APP_NAME" 2>/dev/null; then
        systemctl disable "$APP_NAME"
        print_success "Disabled $APP_NAME service"
    fi
}

# Remove systemd service
remove_systemd_service() {
    print_info "Removing systemd service..."

    if [ -f "$SYSTEMD_DIR/$APP_NAME.service" ]; then
        rm -f "$SYSTEMD_DIR/$APP_NAME.service"
        systemctl daemon-reload
        print_success "Removed systemd service"
    fi
}

# Remove binary
remove_binary() {
    print_info "Removing application binary..."

    if [ -f "$INSTALL_DIR/$APP_NAME" ]; then
        rm -f "$INSTALL_DIR/$APP_NAME"
        print_success "Removed binary from $INSTALL_DIR"
    fi
}

# Remove configuration
remove_config() {
    if [[ "$REMOVE_DATA" == true ]]; then
        print_info "Removing configuration directory..."
        if [ -d "$CONFIG_DIR" ]; then
            rm -rf "$CONFIG_DIR"
            print_success "Removed configuration directory"
        fi
    else
        print_info "Configuration directory preserved: $CONFIG_DIR"
        print_info "Remove manually if desired: sudo rm -rf $CONFIG_DIR"
    fi
}

# Remove data and logs
remove_data_and_logs() {
    if [[ "$REMOVE_DATA" == true ]]; then
        print_info "Removing data and log directories..."
        
        if [ -d "$DATA_DIR" ]; then
            rm -rf "$DATA_DIR"
            print_success "Removed data directory: $DATA_DIR"
        fi
        
        if [ -d "$LOG_DIR" ]; then
            rm -rf "$LOG_DIR"
            print_success "Removed log directory: $LOG_DIR"
        fi
    else
        print_info "Data and logs preserved:"
        print_info "  Data: $DATA_DIR"
        print_info "  Logs: $LOG_DIR"
        print_info "Remove manually if desired:"
        print_info "  sudo rm -rf $DATA_DIR $LOG_DIR"
    fi
}

# Remove user
remove_user() {
    if [[ "$REMOVE_DATA" == true ]]; then
        print_info "Removing system user..."
        
        if id "$APP_USER" &>/dev/null; then
            userdel "$APP_USER" 2>/dev/null || true
            print_success "Removed user: $APP_USER"
        fi
    else
        print_info "System user preserved: $APP_USER"
        print_info "Remove manually if desired: sudo userdel $APP_USER"
    fi
}

# Remove nginx configuration
remove_nginx_config() {
    if [[ "$REMOVE_NGINX" == true ]]; then
        print_info "Removing nginx configuration..."

        # Remove enabled site
        if [ -L "/etc/nginx/sites-enabled/$APP_NAME" ]; then
            rm -f "/etc/nginx/sites-enabled/$APP_NAME"
            print_success "Removed nginx enabled site"
        fi

        # Remove available site
        if [ -f "/etc/nginx/sites-available/$APP_NAME" ]; then
            rm -f "/etc/nginx/sites-available/$APP_NAME"
            print_success "Removed nginx site configuration"
        fi

        # Remove log files
        if [ -f "/var/log/nginx/${APP_NAME}_access.log" ]; then
            rm -f "/var/log/nginx/${APP_NAME}_access.log"
        fi
        if [ -f "/var/log/nginx/${APP_NAME}_error.log" ]; then
            rm -f "/var/log/nginx/${APP_NAME}_error.log"
        fi

        # Test and reload nginx
        if command -v nginx &> /dev/null; then
            if nginx -t 2>/dev/null; then
                systemctl reload nginx 2>/dev/null || true
                print_success "Reloaded nginx configuration"
            else
                print_warning "Nginx configuration test failed - please check manually"
            fi
        fi
    else
        print_info "Nginx configuration preserved"
        print_info "Remove manually if desired:"
        print_info "  sudo rm -f /etc/nginx/sites-enabled/$APP_NAME"
        print_info "  sudo rm -f /etc/nginx/sites-available/$APP_NAME"
    fi
}

# Show final message
show_final_message() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Uninstallation Complete!           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    print_success "MessageBridge has been removed from your system"

    if [[ "$REMOVE_DATA" != true ]]; then
        echo ""
        print_info "Preserved files (remove manually if desired):"
        [ -d "$CONFIG_DIR" ] && print_info "  Configuration: $CONFIG_DIR"
        [ -d "$DATA_DIR" ] && print_info "  Data: $DATA_DIR"
        [ -d "$LOG_DIR" ] && print_info "  Logs: $LOG_DIR"
        id "$APP_USER" &>/dev/null && print_info "  User: $APP_USER"
    fi

    if [[ "$REMOVE_NGINX" != true ]]; then
        if [ -f "/etc/nginx/sites-available/$APP_NAME" ]; then
            echo ""
            print_info "Nginx configuration preserved:"
            print_info "  /etc/nginx/sites-available/$APP_NAME"
        fi
    fi

    echo ""
    print_info "Thank you for using MessageBridge!"
}

# Main uninstallation function
main() {
    print_header
    
    parse_args "$@"
    check_root
    confirm_removal
    stop_services
    remove_systemd_service
    remove_binary
    remove_nginx_config
    remove_config
    remove_data_and_logs
    remove_user
    show_final_message
}

# Run main function with all arguments
main "$@" 