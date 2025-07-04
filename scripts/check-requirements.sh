#!/bin/bash

# MessageBridge System Requirements Checker
# Проверяет системные требования перед установкой

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║     MessageBridge Requirements Checker       ║"
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

# Check OS
check_os() {
    print_info "Проверка операционной системы..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        
        case $OS in
            ubuntu)
                print_success "Ubuntu $OS_VERSION (поддерживается)"
                ;;
            debian)
                print_success "Debian $OS_VERSION (поддерживается)"
                ;;
            arch)
                print_success "Arch Linux (поддерживается)"
                ;;
            *)
                print_warning "ОС $OS не тестировалась, но может работать"
                ;;
        esac
    else
        print_error "Не удалось определить ОС"
        return 1
    fi
}

# Check systemd
check_systemd() {
    print_info "Проверка systemd..."
    
    if command -v systemctl &> /dev/null; then
        print_success "systemd найден"
        
        # Check if systemd is running
        if systemctl is-system-running &> /dev/null; then
            print_success "systemd активен"
        else
            print_warning "systemd не активен или работает в degraded режиме"
        fi
    else
        print_error "systemd не найден (обязательно)"
        return 1
    fi
}

# Check dependencies
check_dependencies() {
    print_info "Проверка зависимостей..."
    
    local missing_deps=()
    local optional_missing=()
    
    # Required dependencies
    if ! command -v sqlite3 &> /dev/null; then
        missing_deps+=("sqlite3")
    else
        print_success "SQLite3 найден"
    fi
    
    # Optional dependencies
    if ! command -v nginx &> /dev/null; then
        optional_missing+=("nginx")
    else
        print_success "nginx найден"
    fi
    
    if ! command -v curl &> /dev/null; then
        optional_missing+=("curl")
    else
        print_success "curl найден"
    fi
    
    # Report missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Отсутствуют обязательные зависимости: ${missing_deps[*]}"
        print_info "Установите их командой:"
        case $OS in
            ubuntu|debian)
                echo "  sudo apt update && sudo apt install ${missing_deps[*]}"
                ;;
            arch)
                echo "  sudo pacman -S sqlite"
                ;;
        esac
        return 1
    fi
    
    if [ ${#optional_missing[@]} -gt 0 ]; then
        print_warning "Отсутствуют опциональные зависимости: ${optional_missing[*]}"
        print_info "Для полной установки установите их:"
        case $OS in
            ubuntu|debian)
                echo "  sudo apt install ${optional_missing[*]}"
                ;;
            arch)
                echo "  sudo pacman -S ${optional_missing[*]}"
                ;;
        esac
    fi
}

# Check ports
check_ports() {
    print_info "Проверка портов..."
    
    # Check if ports are available
    local ports=(8080 80 443)
    local used_ports=()
    
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            used_ports+=("$port")
        fi
    done
    
    if [ ${#used_ports[@]} -gt 0 ]; then
        print_warning "Порты уже используются: ${used_ports[*]}"
        print_info "MessageBridge использует порт 8080, nginx - 80 и 443"
    else
        print_success "Необходимые порты свободны"
    fi
}

# Check disk space
check_disk_space() {
    print_info "Проверка дискового пространства..."
    
    local available_mb=$(df /usr/local 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
    local var_available_mb=$(df /var 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
    
    if [ "$available_mb" -gt 100 ] && [ "$var_available_mb" -gt 500 ]; then
        print_success "Достаточно места на диске"
    elif [ "$available_mb" -lt 50 ]; then
        print_error "Недостаточно места в /usr/local (нужно минимум 50MB)"
    elif [ "$var_available_mb" -lt 100 ]; then
        print_error "Недостаточно места в /var (нужно минимум 100MB для данных)"
    else
        print_warning "Ограниченное место на диске, рекомендуется освободить место"
    fi
}

# Check permissions
check_permissions() {
    print_info "Проверка прав доступа..."
    
    if [ "$EUID" -eq 0 ]; then
        print_success "Запущен от root (достаточно прав для установки)"
    else
        print_warning "Не запущен от root - понадобится sudo для установки"
        
        # Check if user has sudo access
        if sudo -n true 2>/dev/null; then
            print_success "Пользователь имеет sudo доступ"
        else
            print_warning "Нужен доступ к sudo для установки"
        fi
    fi
}

# Check existing installation
check_existing() {
    print_info "Проверка существующей установки..."
    
    local existing_found=false
    
    if [ -f "/usr/local/bin/messagebridge" ]; then
        print_warning "Найден установленный messagebridge в /usr/local/bin/"
        existing_found=true
    fi
    
    if systemctl list-unit-files | grep -q "^messagebridge.service"; then
        print_warning "Найден systemd service messagebridge"
        existing_found=true
    fi
    
    if id "messagebridge" &>/dev/null; then
        print_warning "Найден пользователь messagebridge"
        existing_found=true
    fi
    
    if [ "$existing_found" = true ]; then
        print_info "Используйте --force для переустановки"
    else
        print_success "Предыдущие установки не найдены"
    fi
}

# Main check function
main() {
    print_header
    
    local checks_passed=0
    local total_checks=7
    
    # Run all checks
    if check_os; then ((checks_passed++)); fi
    if check_systemd; then ((checks_passed++)); fi
    if check_dependencies; then ((checks_passed++)); fi
    if check_ports; then ((checks_passed++)); fi
    if check_disk_space; then ((checks_passed++)); fi
    if check_permissions; then ((checks_passed++)); fi
    if check_existing; then ((checks_passed++)); fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    
    if [ $checks_passed -eq $total_checks ]; then
        print_success "Все проверки пройдены! Система готова для установки MessageBridge"
        echo ""
        print_info "Для установки выполните:"
        echo "  sudo ./scripts/install.sh"
        exit 0
    else
        print_warning "Пройдено проверок: $checks_passed из $total_checks"
        print_info "Исправьте выявленные проблемы и повторите проверку"
        exit 1
    fi
}

# Parse arguments
case "${1:-}" in
    --help|-h)
        echo "Использование: $0"
        echo "Проверяет системные требования для установки MessageBridge"
        exit 0
        ;;
    *)
        main
        ;;
esac 