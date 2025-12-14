.PHONY: build run test clean install deps help

# Variables
BINARY_NAME=spv-server
BUILD_DIR=./build
MAIN_PATH=./cmd/server/main.go

# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GORUN=$(GOCMD) run
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOMOD=$(GOCMD) mod
GOFMT=$(GOCMD) fmt

help: ## Display this help message
	@echo "SPV Backend - Available Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

deps: ## Download dependencies
	$(GOMOD) download
	$(GOMOD) tidy

build: deps ## Build the server binary
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	$(GOBUILD) -o $(BUILD_DIR)/$(BINARY_NAME) $(MAIN_PATH)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

run: ## Run the server (without building)
	@echo "Starting SPV server..."
	$(GORUN) $(MAIN_PATH)

run-build: build ## Build and run the server
	@echo "Running $(BINARY_NAME)..."
	$(BUILD_DIR)/$(BINARY_NAME)

test: ## Run tests
	$(GOTEST) -v ./...

fmt: ## Format code
	$(GOFMT) ./...

vet: ## Run go vet
	$(GOCMD) vet ./...

lint: fmt vet ## Run linters

install: build ## Install the binary to $GOPATH/bin
	@echo "Installing $(BINARY_NAME)..."
	@cp $(BUILD_DIR)/$(BINARY_NAME) $(GOPATH)/bin/
	@echo "Installed to $(GOPATH)/bin/$(BINARY_NAME)"

clean: ## Clean build artifacts
	@echo "Cleaning..."
	@rm -rf $(BUILD_DIR)
	@rm -f $(BINARY_NAME)
	@echo "Clean complete"

# Development targets
dev: ## Run in development mode with auto-reload (requires air)
	@which air > /dev/null || (echo "Installing air..." && go install github.com/cosmtrek/air@latest)
	air

# Docker targets
docker-build: ## Build Docker image
	docker build -t spv-backend:latest .

docker-run: ## Run Docker container
	docker run -p 3000:3000 --env-file .env spv-backend:latest

# Bitcoin Core helpers
bitcoin-regtest: ## Start Bitcoin Core in regtest mode
	@echo "Starting Bitcoin Core in regtest mode..."
	bitcoind -regtest -daemon

bitcoin-stop: ## Stop Bitcoin Core
	bitcoin-cli -regtest stop

bitcoin-generate: ## Generate 150 blocks in regtest
	@echo "Generating 150 blocks..."
	bitcoin-cli -regtest createwallet "test" || true
	bitcoin-cli -regtest -rpcwallet=test getnewaddress > /tmp/btc_addr.txt
	bitcoin-cli -regtest generatetoaddress 150 $$(cat /tmp/btc_addr.txt)
	@echo "Generated 150 blocks"

bitcoin-info: ## Show Bitcoin Core info
	bitcoin-cli -regtest getblockchaininfo

# Environment setup
setup-env: ## Copy .env.example to .env
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo ".env file created. Please edit it with your configuration."; \
	else \
		echo ".env file already exists."; \
	fi

# Full setup for first-time users
setup: setup-env deps ## Complete setup (env + dependencies)
	@echo "Setup complete! Edit .env and run 'make run' to start the server."
