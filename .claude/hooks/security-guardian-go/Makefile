# Security Guardian Go - Makefile

BINARY_NAME=guardian
VERSION?=1.0.0
BUILD_DIR=bin
GO=go

# Build flags for smaller binary
LDFLAGS=-s -w -X main.Version=$(VERSION)

.PHONY: all build clean test install build-all

all: build

# Build for current platform
build:
	$(GO) build -ldflags="$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/guardian

# Build for all platforms
build-all: build-darwin-arm64 build-darwin-amd64 build-linux-amd64

build-darwin-arm64:
	GOOS=darwin GOARCH=arm64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 ./cmd/guardian

build-darwin-amd64:
	GOOS=darwin GOARCH=amd64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 ./cmd/guardian

build-linux-amd64:
	GOOS=linux GOARCH=amd64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 ./cmd/guardian

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	$(GO) clean

# Run tests
test:
	$(GO) test -v ./...

# Run tests with coverage
test-coverage:
	$(GO) test -v -cover -coverprofile=coverage.out ./...
	$(GO) tool cover -html=coverage.out -o coverage.html

# Install to system
install: build
	cp $(BUILD_DIR)/$(BINARY_NAME) /usr/local/bin/

# Format code
fmt:
	$(GO) fmt ./...

# Lint code
lint:
	golangci-lint run

# Download dependencies
deps:
	$(GO) mod download
	$(GO) mod tidy

# Verify dependencies
verify:
	$(GO) mod verify

# Benchmark
benchmark:
	@echo "Running cold start benchmark..."
	@for i in 1 2 3 4 5; do \
		echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | \
		/usr/bin/time -p ./$(BUILD_DIR)/$(BINARY_NAME) 2>&1 | grep real; \
	done

# Help
help:
	@echo "Security Guardian Go - Build targets:"
	@echo "  build          - Build for current platform"
	@echo "  build-all      - Build for all platforms (macOS ARM, macOS Intel, Linux amd64)"
	@echo "  clean          - Clean build artifacts"
	@echo "  test           - Run tests"
	@echo "  test-coverage  - Run tests with coverage report"
	@echo "  install        - Install to /usr/local/bin"
	@echo "  fmt            - Format code"
	@echo "  lint           - Run linter"
	@echo "  deps           - Download and tidy dependencies"
	@echo "  benchmark      - Run cold start benchmark"
