#!/bin/bash
# Setup script for riscv-formal integration
# This copies integration files from verif/formal_configs/ to the riscv-formal submodule

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
RISCV_FORMAL="$PROJECT_ROOT/verif/riscv-formal"
INTEGRATION_DIR="$SCRIPT_DIR/riscv-formal-integration"
CORES_DIR="$RISCV_FORMAL/cores/kcore"

# Check if riscv-formal submodule exists
if [ ! -d "$RISCV_FORMAL" ]; then
    echo "Error: riscv-formal submodule not found at $RISCV_FORMAL"
    echo "Please run: git submodule update --init --recursive"
    exit 1
fi

# Check if integration directory exists
if [ ! -d "$INTEGRATION_DIR" ]; then
    echo "Error: Integration directory not found at $INTEGRATION_DIR"
    exit 1
fi

# Remove existing directory if it exists
if [ -e "$CORES_DIR" ]; then
    echo "Removing existing $CORES_DIR"
    rm -rf "$CORES_DIR"
fi

# Copy integration files to riscv-formal/cores/kcore
echo "Copying integration files: $INTEGRATION_DIR -> $CORES_DIR"
cp -r "$INTEGRATION_DIR" "$CORES_DIR"

echo "✅ riscv-formal integration setup complete!"
echo ""
echo "You can now run checks with:"
echo "  cd riscv-formal/cores/kcore"
echo "  python3 ../../checks/genchecks.py"
echo "  cd checks && sby -f <check>.sby"
