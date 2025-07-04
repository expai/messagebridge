# Makefile for messagebridge

# Variables
APP_NAME = messagebridge
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.1")
BUILD_TIME = $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
GO_VERSION = $(shell go version | awk '{print $$3}')
LDFLAGS = -X main.version=$(VERSION) -X main.buildTime=$(BUILD_TIME)

# Build targets
.PHONY: all build clean test deps docker install uninstall help

all: build

help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

deps: ## Download dependencies
	go mod download
	go mod tidy

build: ## Build the application
	CGO_ENABLED=1 go build -ldflags "$(LDFLAGS)" -o $(APP_NAME) .

build-linux: ## Build for Linux
	CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -ldflags "$(LDFLAGS)" -o $(APP_NAME)-linux .

test: ## Run tests
	go test -v ./...

test-race: ## Run tests with race detection
	go test -race -v ./...

clean: ## Clean build artifacts
	rm -f $(APP_NAME) $(APP_NAME)-linux
	go clean

fmt: ## Format code
	go fmt ./...

lint: ## Run linter
	golangci-lint run

##@ Docker

docker-build: ## Build Docker image
	docker build -t $(APP_NAME):$(VERSION) .
	docker tag $(APP_NAME):$(VERSION) $(APP_NAME):latest

docker-run: ## Run Docker container
	docker run --rm -p 8080:8080 $(APP_NAME):latest

docker-push: ## Push Docker image
	docker push $(APP_NAME):$(VERSION)
	docker push $(APP_NAME):latest

##@ Installation

install: build ## Install binary to system (basic installation)
	sudo cp $(APP_NAME) /usr/local/bin/
	sudo chmod +x /usr/local/bin/$(APP_NAME)
	sudo mkdir -p /etc/$(APP_NAME) /var/lib/$(APP_NAME) /var/log/$(APP_NAME)
	sudo useradd -r -s /bin/false $(APP_NAME) || true
	sudo chown $(APP_NAME):$(APP_NAME) /var/lib/$(APP_NAME) /var/log/$(APP_NAME)
	sudo cp examples/simple-config.yaml /etc/$(APP_NAME)/config.yaml
	sudo cp deployments/systemd/$(APP_NAME).service /etc/systemd/system/
	sudo systemctl daemon-reload
	@echo "Basic installation complete. To start the service:"
	@echo "  sudo systemctl enable $(APP_NAME)"
	@echo "  sudo systemctl start $(APP_NAME)"

install-full: build-linux ## Full production installation with nginx setup
	@echo "Starting full production installation..."
	chmod +x scripts/install.sh
	sudo ./scripts/install.sh

install-minimal: build-linux ## Minimal installation without nginx
	@echo "Starting minimal installation..."
	chmod +x scripts/install.sh
	sudo ./scripts/install.sh --minimal

install-check: ## Check system requirements for installation
	@echo "Checking system requirements..."
	@command -v sqlite3 >/dev/null 2>&1 || echo "⚠️  sqlite3 not found"
	@command -v nginx >/dev/null 2>&1 || echo "⚠️  nginx not found"
	@command -v systemctl >/dev/null 2>&1 || echo "❌ systemd not found (required)"
	@id messagebridge >/dev/null 2>&1 && echo "✓ messagebridge user exists" || echo "ℹ️  messagebridge user will be created"
	@[ -f /usr/local/bin/messagebridge ] && echo "⚠️  messagebridge already installed" || echo "✓ messagebridge not installed"

uninstall: ## Uninstall from system (basic removal)
	sudo systemctl stop $(APP_NAME) || true
	sudo systemctl disable $(APP_NAME) || true
	sudo rm -f /etc/systemd/system/$(APP_NAME).service
	sudo rm -f /usr/local/bin/$(APP_NAME)
	sudo systemctl daemon-reload
	@echo "Basic uninstallation complete. To remove data and config:"
	@echo "  sudo rm -rf /etc/$(APP_NAME) /var/lib/$(APP_NAME) /var/log/$(APP_NAME)"
	@echo "  sudo userdel $(APP_NAME)"

uninstall-full: ## Complete removal including data and nginx
	@echo "Starting full removal..."
	chmod +x scripts/uninstall.sh
	sudo ./scripts/uninstall.sh --remove-data --remove-nginx

uninstall-safe: ## Safe removal preserving data and config
	@echo "Starting safe removal..."
	chmod +x scripts/uninstall.sh
	sudo ./scripts/uninstall.sh

fix-permissions: ## Fix permissions for existing installation
	@echo "Fixing permissions for MessageBridge..."
	chmod +x scripts/fix-permissions.sh
	sudo ./scripts/fix-permissions.sh

fix-database: ## Fix database permissions only
	@echo "Fixing database permissions for MessageBridge..."
	chmod +x scripts/fix-database-permissions.sh
	sudo ./scripts/fix-database-permissions.sh

##@ Service Management

start: ## Start the service
	sudo systemctl start $(APP_NAME)

stop: ## Stop the service
	sudo systemctl stop $(APP_NAME)

restart: ## Restart the service
	sudo systemctl restart $(APP_NAME)

status: ## Check service status
	sudo systemctl status $(APP_NAME)

logs: ## Show service logs
	sudo journalctl -u $(APP_NAME) -fq

##@ Development Tools

run: ## Run locally with example config
	./$(APP_NAME) -config examples/simple-config.yaml

run-dev: build run ## Build and run locally

test-webhook: ## Send test webhook
	@echo "Sending test webhook to http://localhost:8080/webhook/payment"
	curl -X POST http://localhost:8080/webhook/payment \
		-H "Content-Type: application/json" \
		-d '{"test": "payment", "amount": 100, "currency": "USD"}'

health: ## Check application health
	curl -s http://localhost:8080/health | jq .

##@ Release

release: test build-linux ## Prepare release build
	mkdir -p dist
	cp $(APP_NAME)-linux dist/$(APP_NAME)
	cp -r examples dist/
	cp -r deployments dist/
	cp -r scripts dist/
	chmod +x dist/scripts/*.sh
	cp README.md QUICKSTART.md LICENSE CHANGELOG.md TROUBLESHOOTING.md dist/ 2>/dev/null || true
	tar -czf dist/$(APP_NAME)-$(VERSION)-linux-amd64.tar.gz -C dist $(APP_NAME) examples deployments scripts README.md QUICKSTART.md LICENSE CHANGELOG.md TROUBLESHOOTING.md
	@echo "Release package created: dist/$(APP_NAME)-$(VERSION)-linux-amd64.tar.gz"
	@echo "Package contents:"
	@echo "  - $(APP_NAME) binary"
	@echo "  - Production configuration files"
	@echo "  - Installation scripts"
	@echo "  - Systemd service file"
	@echo "  - Documentation"

##@ Information

version: ## Show version information
	@echo "App Name: $(APP_NAME)"
	@echo "Version: $(VERSION)"
	@echo "Build Time: $(BUILD_TIME)"
	@echo "Go Version: $(GO_VERSION)" 