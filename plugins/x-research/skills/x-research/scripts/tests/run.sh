#!/bin/sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

sh "$SCRIPT_DIR/test_config_loader.sh"

echo "x-research tests passed"
