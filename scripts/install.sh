#!/bin/bash

# MessageBridge Auto-Installer
# Supports: Ubuntu, Debian, Arch Linux

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
MINIMAL_INSTALL=false
SKIP_NGINX=false
FORCE_INSTALL=false

print_header() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║          MessageBridge Installer             ║"
    echo "║      Secure Payment Webhook Gateway          ║"
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
    echo "  --minimal         Install only the application without nginx"
    echo "  --skip-nginx      Skip nginx configuration"
    echo "  --force           Force installation even if already installed"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                # Full installation with nginx"
    echo "  $0 --minimal      # Install only messagebridge"
    echo "  $0 --skip-nginx   # Install but skip nginx setup"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --minimal)
                MINIMAL_INSTALL=true
                SKIP_NGINX=true
                shift
                ;;
            --skip-nginx)
                SKIP_NGINX=true
                shift
                ;;
            --force)
                FORCE_INSTALL=true
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

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "Cannot detect OS. Supported: Ubuntu, Debian, Arch Linux"
        exit 1
    fi

    case $OS in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            ;;
        arch)
            PACKAGE_MANAGER="pacman"
            ;;
        *)
            print_error "Unsupported OS: $OS. Supported: Ubuntu, Debian, Arch Linux"
            exit 1
            ;;
    esac

    print_info "Detected OS: $OS $OS_VERSION"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."

    local missing_deps=()

    # Check SQLite
    if ! command -v sqlite3 &> /dev/null; then
        missing_deps+=("sqlite3")
    fi

    # Check nginx (if not skipping)
    if [[ "$SKIP_NGINX" != true ]] && ! command -v nginx &> /dev/null; then
        missing_deps+=("nginx")
    fi

    # Check systemctl
    if ! command -v systemctl &> /dev/null; then
        print_error "systemd is required but not found"
        exit 1
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        install_dependencies "${missing_deps[@]}"
    else
        print_success "All dependencies are satisfied"
    fi
}

# Install dependencies
install_dependencies() {
    local deps=("$@")
    print_info "Installing missing dependencies..."

    case $PACKAGE_MANAGER in
        apt)
            apt update
            for dep in "${deps[@]}"; do
                print_info "Installing $dep..."
                apt install -y "$dep"
            done
            ;;
        pacman)
            for dep in "${deps[@]}"; do
                print_info "Installing $dep..."
                # Map package names for Arch
                case $dep in
                    sqlite3) pacman -S --noconfirm sqlite ;;
                    *) pacman -S --noconfirm "$dep" ;;
                esac
            done
            ;;
    esac

    print_success "Dependencies installed successfully"
}

# Check if application is already installed
check_existing_installation() {
    if [[ "$FORCE_INSTALL" == true ]]; then
        return 0
    fi

    if [ -f "$INSTALL_DIR/$APP_NAME" ]; then
        print_warning "MessageBridge is already installed"
        read -p "Do you want to continue and overwrite? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
}

# Create user and directories
setup_user_and_directories() {
    print_info "Setting up user and directories..."

    # Create system user
    if ! id "$APP_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$DATA_DIR" "$APP_USER"
        print_success "Created user: $APP_USER"
    else
        print_info "User $APP_USER already exists"
    fi

    # Create directories
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    chown "$APP_USER:$APP_USER" "$DATA_DIR" "$LOG_DIR"
    chmod 750 "$DATA_DIR" "$LOG_DIR"
    
    # Set proper permissions for config directory
    chown root:$APP_USER "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"

    print_success "Directories created and configured"
}

# Fix permissions for existing installation
fix_permissions() {
    print_info "Fixing permissions for existing installation..."
    
    # Fix directory permissions
    if [ -d "$CONFIG_DIR" ]; then
        chown root:$APP_USER "$CONFIG_DIR"
        chmod 750 "$CONFIG_DIR"
    fi
    
    if [ -d "$DATA_DIR" ]; then
        chown "$APP_USER:$APP_USER" "$DATA_DIR"
        chmod 750 "$DATA_DIR"
    fi
    
    if [ -d "$LOG_DIR" ]; then
        chown "$APP_USER:$APP_USER" "$LOG_DIR"
        chmod 750 "$LOG_DIR"
    fi
    
    # Fix config file permissions
    if [ -f "$CONFIG_DIR/config.yaml" ]; then
        chown root:$APP_USER "$CONFIG_DIR/config.yaml"
        chmod 640 "$CONFIG_DIR/config.yaml"
    fi
    
    # Fix binary permissions
    if [ -f "$INSTALL_DIR/$APP_NAME" ]; then
        chmod +x "$INSTALL_DIR/$APP_NAME"
    fi
    
    print_success "Permissions fixed"
}

# Install application binary
install_binary() {
    print_info "Installing application binary..."

    if [ ! -f "./$APP_NAME" ]; then
        print_error "Binary file ./$APP_NAME not found in current directory"
        print_info "Please run this script from the extracted release directory"
        exit 1
    fi

    cp "./$APP_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$APP_NAME"

    print_success "Binary installed to $INSTALL_DIR/$APP_NAME"
}

# Install configuration
install_config() {
    print_info "Installing configuration..."

    if [ -f "./examples/production-config.yaml" ]; then
        cp "./examples/production-config.yaml" "$CONFIG_DIR/config.yaml"
        # Make config readable by messagebridge user
        chown root:$APP_USER "$CONFIG_DIR/config.yaml"
        chmod 640 "$CONFIG_DIR/config.yaml"
        print_success "Configuration installed to $CONFIG_DIR/config.yaml"
    else
        print_error "Configuration file not found: ./examples/production-config.yaml"
        exit 1
    fi
}

# Install systemd service
install_systemd_service() {
    print_info "Installing systemd service..."

    if [ -f "./deployments/systemd/messagebridge.service" ]; then
        cp "./deployments/systemd/messagebridge.service" "$SYSTEMD_DIR/"
        systemctl daemon-reload
        print_success "Systemd service installed"
    else
        print_error "Systemd service file not found: ./deployments/systemd/messagebridge.service"
        exit 1
    fi
}

# Generate nginx configuration
generate_nginx_config() {
    if [[ "$SKIP_NGINX" == true ]]; then
        return 0
    fi

    print_info "Generating nginx configuration..."

    # Read domain from config
    local domain
    local server_host
    local server_port

    if [ -f "$CONFIG_DIR/config.yaml" ]; then
        domain=$(grep -E "^\s*domain:" "$CONFIG_DIR/config.yaml" | sed 's/.*domain:\s*[\"]*\([^\"]*\)[\"]*$/\1/' | tr -d '"')
        server_host=$(grep -E "^\s*host:" "$CONFIG_DIR/config.yaml" | sed 's/.*host:\s*[\"]*\([^\"]*\)[\"]*$/\1/' | tr -d '"')
        server_port=$(grep -E "^\s*port:" "$CONFIG_DIR/config.yaml" | sed 's/.*port:\s*\([0-9]*\).*/\1/')
    fi

    # Set defaults if not found
    domain=${domain:-"webhook.yourdomain.com"}
    server_host=${server_host:-"127.0.0.1"}
    server_port=${server_port:-"8080"}

    # Create clean nginx config (HTTP only - SSL must be configured manually)
    cat > "/etc/nginx/sites-available/$APP_NAME" << EOF
# MessageBridge nginx configuration
# Note: This is HTTP-only configuration. SSL MUST be configured manually!

server {
    listen 80;
    server_name $domain;

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logging
    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;

    # Proxy to MessageBridge
    location / {
        proxy_pass http://$server_host:$server_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # Health check endpoint
    location /health {
        proxy_pass http://$server_host:$server_port/health;
        access_log off;
    }
}

# SSL Configuration Template (for manual setup)
# Copy and uncomment the following block after obtaining SSL certificates:
#
# server {
#     listen 443 ssl http2;
#     server_name $domain;
#     
#     ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
#     ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
#     
#     ssl_protocols TLSv1.2 TLSv1.3;
#     ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
#     ssl_prefer_server_ciphers off;
#     ssl_session_cache shared:SSL:10m;
#     ssl_session_timeout 10m;
#     
#     add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
#     add_header X-Content-Type-Options "nosniff" always;
#     add_header X-Frame-Options "DENY" always;
#     add_header X-XSS-Protection "1; mode=block" always;
#     
#     access_log /var/log/nginx/${APP_NAME}_ssl_access.log;
#     error_log /var/log/nginx/${APP_NAME}_ssl_error.log;
#     
#     location / {
#         proxy_pass http://$server_host:$server_port;
#         proxy_set_header Host \$host;
#         proxy_set_header X-Real-IP \$remote_addr;
#         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
#         proxy_set_header X-Forwarded-Proto \$scheme;
#         
#         proxy_connect_timeout 60s;
#         proxy_send_timeout 60s;
#         proxy_read_timeout 60s;
#         
#         proxy_buffering off;
#         proxy_request_buffering off;
#     }
#     
#     location /health {
#         proxy_pass http://$server_host:$server_port/health;
#         access_log off;
#     }
# }
#
# server {
#     listen 80;
#     server_name $domain;
#     return 301 https://\$server_name\$request_uri;
# }
EOF

    # Enable site
    if [ ! -L "/etc/nginx/sites-enabled/$APP_NAME" ]; then
        ln -s "/etc/nginx/sites-available/$APP_NAME" "/etc/nginx/sites-enabled/"
    fi

    # Test nginx configuration
    if nginx -t 2>/dev/null; then
        print_success "Nginx configuration generated and tested successfully"
    else
        print_warning "Nginx configuration has issues - please check manually"
    fi
}

# Enable and start services
enable_services() {
    print_info "Enabling and starting services..."

    # Enable and start messagebridge
    systemctl enable "$APP_NAME"
    systemctl start "$APP_NAME"

    if systemctl is-active --quiet "$APP_NAME"; then
        print_success "MessageBridge service started successfully"
    else
        print_error "Failed to start MessageBridge service"
        print_info "Check logs with: journalctl -u $APP_NAME"
        exit 1
    fi

    # Restart nginx if not skipping
    if [[ "$SKIP_NGINX" != true ]]; then
        systemctl enable nginx
        systemctl restart nginx
        
        if systemctl is-active --quiet nginx; then
            print_success "Nginx service restarted successfully"
        else
            print_warning "Nginx service failed to restart - check configuration"
        fi
    fi
}

# Show final instructions
show_final_instructions() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            Installation Complete!            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    print_info "Configuration file: $CONFIG_DIR/config.yaml"
    print_info "Log files: $LOG_DIR/"
    print_info "Data directory: $DATA_DIR/"

    echo ""
    print_error "⚠️  CRITICAL: SSL SETUP IS MANDATORY FOR PRODUCTION!"
    print_error "⚠️  Current setup is HTTP-only and NOT SECURE for webhooks!"
    echo ""
    
    if [[ "$SKIP_NGINX" != true ]]; then
        local domain
        if [ -f "$CONFIG_DIR/config.yaml" ]; then
            domain=$(grep -E "^\s*domain:" "$CONFIG_DIR/config.yaml" | sed 's/.*domain:\s*[\"]*\([^\"]*\)[\"]*$/\1/' | tr -d '"')
        fi
        domain=${domain:-"webhook.yourdomain.com"}

        print_warning "🔐 YOU MUST CONFIGURE SSL BEFORE RECEIVING REAL WEBHOOKS:"
        echo ""
        
        print_info "STEP 1: Update DNS settings"
        echo "   Point $domain to this server's IP address"
        echo ""
        
        print_info "STEP 2: Install certbot"
        case $PACKAGE_MANAGER in
            apt)
                echo "   sudo apt install certbot python3-certbot-nginx"
                ;;
            pacman)
                echo "   sudo pacman -S certbot certbot-nginx"
                ;;
        esac
        echo ""

        print_info "STEP 3: Obtain SSL certificate"
        echo "   sudo certbot --nginx -d $domain"
        echo "   This will automatically configure SSL in nginx!"
        echo ""
        
        print_info "STEP 4: Update configuration"
        echo "   Edit: $CONFIG_DIR/config.yaml"
        echo "   Update:"
        echo "     - nginx.domain: \"$domain\""
        echo "     - remote_url.url: \"https://your-api.com/webhooks\""
        echo ""
        
        print_info "STEP 5: Restart services"
        echo "   sudo systemctl restart messagebridge nginx"
        echo ""
        
        print_warning "📋 SSL Configuration file template available at:"
        echo "   /etc/nginx/sites-available/$APP_NAME"
        echo "   (Contains commented SSL section for reference)"
    fi

    echo ""
    print_info "STEP 6: Test the installation (HTTP only for now)"
    echo "   curl -X POST http://localhost:8080/health"
    echo "   curl -X POST http://$domain/health  # After DNS setup"

    echo ""
    print_info "STEP 7: Monitor the service"
    echo "   sudo systemctl status $APP_NAME"
    echo "   sudo journalctl -u $APP_NAME -f"

    echo ""
    print_warning "🚨 REMEMBER: HTTPS MUST BE CONFIGURED BEFORE PRODUCTION USE!"
    print_success "MessageBridge is running on HTTP. Configure SSL now!"
}

# Main installation function
main() {
    print_header
    
    parse_args "$@"
    detect_os
    check_root
    check_existing_installation
    check_dependencies
    setup_user_and_directories
    
    # Fix permissions for existing installations (force install or re-install)
    if [[ "$FORCE_INSTALL" == true ]] || [ -f "$INSTALL_DIR/$APP_NAME" ]; then
        fix_permissions
    fi
    
    install_binary
    install_config
    install_systemd_service
    generate_nginx_config
    enable_services
    show_final_instructions
}

# Run main function with all arguments
main "$@" 