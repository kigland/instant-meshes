#!/bin/bash
set -euo pipefail

# Build instantmeshes-cli for macOS (arm64 + x86_64 universal binary)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build_macos"

echo "=== Building instantmeshes-cli for macOS ==="

# Clean
rm -rf "$BUILD_DIR"

# ARM64 build (native)
echo "--- Building arm64 ---"
cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR/arm64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$BUILD_DIR/arm64" --target instantmeshes-cli -j$(sysctl -n hw.logicalcpu)

# x86_64 build (cross-compile if on arm64, or native if on Intel)
echo "--- Building x86_64 ---"
cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR/x86_64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$BUILD_DIR/x86_64" --target instantmeshes-cli -j$(sysctl -n hw.logicalcpu)

# Create universal binary
echo "--- Creating universal binary ---"
mkdir -p "$PROJECT_ROOT/release"
lipo -create \
  "$BUILD_DIR/arm64/instantmeshes-cli" \
  "$BUILD_DIR/x86_64/instantmeshes-cli" \
  -output "$PROJECT_ROOT/release/instantmeshes-cli"

echo "--- Stripping ---"
strip "$PROJECT_ROOT/release/instantmeshes-cli"

echo "Done: $PROJECT_ROOT/release/instantmeshes-cli"
file "$PROJECT_ROOT/release/instantmeshes-cli"
