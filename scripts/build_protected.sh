#!/bin/bash
# build.sh - Build obfuscated binary with garble

set -e

echo "Building Neo B2-Plus with protection..."

# Install garble if not present
if ! command -v garble &> /dev/null; then
    echo "Installing garble..."
    go install mvdan.cc/garble@latest
fi

# Build with garble
echo "Compiling with obfuscation..."
garble -seed=random -tiny build -o bin/neob2plus ./cmd/server

echo "Build complete: bin/neob2plus"
echo "Checksum: $(sha256sum bin/neob2plus | cut -d' ' -f1)"