#!/bin/bash
# Security Guardian Go - Installation Script
# Downloads the appropriate binary for your platform from GitHub Releases

set -e

REPO="artwist-polyakov/polyakov-claude-skills"
BINARY_NAME="guardian"

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Normalize architecture
case "$ARCH" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Normalize OS
case "$OS" in
    darwin|linux)
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

BINARY="${BINARY_NAME}-${OS}-${ARCH}"

echo "Detected platform: ${OS}-${ARCH}"
echo "Downloading ${BINARY}..."

# Get latest release URL
RELEASE_URL="https://github.com/${REPO}/releases/latest/download/${BINARY}"

# Download binary
if command -v curl &> /dev/null; then
    curl -fsSL -o "${BINARY_NAME}" "${RELEASE_URL}"
elif command -v wget &> /dev/null; then
    wget -q -O "${BINARY_NAME}" "${RELEASE_URL}"
else
    echo "Error: curl or wget required"
    exit 1
fi

# Make executable
chmod +x "${BINARY_NAME}"

echo ""
echo "Successfully downloaded: ./${BINARY_NAME}"
echo ""
echo "To install system-wide (requires sudo):"
echo "  sudo mv ${BINARY_NAME} /usr/local/bin/"
echo ""
echo "Or copy to your project's .claude/hooks/security-guardian-go/bin/ directory:"
echo "  mkdir -p .claude/hooks/security-guardian-go/bin"
echo "  mv ${BINARY_NAME} .claude/hooks/security-guardian-go/bin/"
echo ""
echo "Then update your .claude/settings.json to use the hook."
