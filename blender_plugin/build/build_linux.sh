#!/bin/bash
set -euo pipefail

# Build instantmeshes-cli for Linux x86_64
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build_linux"

echo "=== Building instantmeshes-cli for Linux x86_64 ==="

rm -rf "$BUILD_DIR"

cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build "$BUILD_DIR" --target instantmeshes-cli -j$(nproc)

mkdir -p "$PROJECT_ROOT/release"
cp "$BUILD_DIR/instantmeshes-cli" "$PROJECT_ROOT/release/instantmeshes-cli-linux-x86_64"
strip "$PROJECT_ROOT/release/instantmeshes-cli-linux-x86_64"

echo "Done: $PROJECT_ROOT/release/instantmeshes-cli-linux-x86_64"
file "$PROJECT_ROOT/release/instantmeshes-cli-linux-x86_64"
