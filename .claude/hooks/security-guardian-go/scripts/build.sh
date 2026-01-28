#!/bin/bash
# Security Guardian Go - Build Script
# Builds binaries for all supported platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/bin"

cd "$PROJECT_DIR"

echo "Building Security Guardian Go..."
echo "Project directory: $PROJECT_DIR"
echo "Build directory: $BUILD_DIR"

# Create build directory
mkdir -p "$BUILD_DIR"

# Build flags for smaller binary
LDFLAGS="-s -w"

# Build for macOS ARM64 (M1/M2/M3)
echo "Building for darwin/arm64..."
GOOS=darwin GOARCH=arm64 go build -ldflags="$LDFLAGS" -o "${BUILD_DIR}/guardian-darwin-arm64" ./cmd/guardian

# Build for macOS AMD64 (Intel)
echo "Building for darwin/amd64..."
GOOS=darwin GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "${BUILD_DIR}/guardian-darwin-amd64" ./cmd/guardian

# Build for Linux AMD64
echo "Building for linux/amd64..."
GOOS=linux GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "${BUILD_DIR}/guardian-linux-amd64" ./cmd/guardian

echo ""
echo "Build complete! Binaries:"
ls -lh "$BUILD_DIR"/guardian-*

echo ""
echo "To use locally, create a symlink:"
echo "  ln -sf ${BUILD_DIR}/guardian-\$(uname -s | tr '[:upper:]' '[:lower:]')-\$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') ${BUILD_DIR}/guardian"
