#!/bin/bash
set -euo pipefail

# Build instantmeshes-cli for macOS (arm64 + x86_64 universal binary)
# and package a platform-specific Blender addon.
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build_macos"
ADDON_SRC="$PROJECT_ROOT/instant_meshes"
RELEASE_DIR="$PROJECT_ROOT/release"

echo "=== Building instantmeshes-cli for macOS ==="

rm -rf "$BUILD_DIR" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# ARM64 build (native)
echo "--- Building arm64 ---"
cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR/arm64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$BUILD_DIR/arm64" --target instantmeshes-cli -j$(sysctl -n hw.logicalcpu)

# x86_64 build
echo "--- Building x86_64 ---"
cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR/x86_64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$BUILD_DIR/x86_64" --target instantmeshes-cli -j$(sysctl -n hw.logicalcpu) || \
  echo "WARNING: x86_64 build failed (may need Rosetta 2). arm64-only binary will be used."

# Create universal binary if both exist
if [ -f "$BUILD_DIR/arm64/instantmeshes-cli" ] && [ -f "$BUILD_DIR/x86_64/instantmeshes-cli" ]; then
  echo "--- Creating universal binary ---"
  lipo -create \
    "$BUILD_DIR/arm64/instantmeshes-cli" \
    "$BUILD_DIR/x86_64/instantmeshes-cli" \
    -output "$RELEASE_DIR/instantmeshes-cli"
else
  cp "$BUILD_DIR/arm64/instantmeshes-cli" "$RELEASE_DIR/instantmeshes-cli"
fi

strip "$RELEASE_DIR/instantmeshes-cli"

# Package Blender addon with binary bundled
echo "--- Packaging Blender addon ---"
ADDON_TMP="/tmp/im_addon_macos"
rm -rf "$ADDON_TMP"
mkdir -p "$ADDON_TMP/instant_meshes/bin"
cp "$ADDON_SRC"/__init__.py "$ADDON_TMP/instant_meshes/"
cp "$ADDON_SRC"/operators.py "$ADDON_TMP/instant_meshes/"
cp "$ADDON_SRC"/panel.py "$ADDON_TMP/instant_meshes/"
cp "$ADDON_SRC"/preferences.py "$ADDON_TMP/instant_meshes/"
cp "$RELEASE_DIR/instantmeshes-cli" "$ADDON_TMP/instant_meshes/bin/instantmeshes-cli"
cd "$ADDON_TMP" && zip -r "$RELEASE_DIR/instant-meshes-blender-macos.zip" instant_meshes/

echo ""
echo "=== Done ==="
echo "Standalone CLI: $RELEASE_DIR/instantmeshes-cli"
echo "Blender addon:   $RELEASE_DIR/instant-meshes-blender-macos.zip"
file "$RELEASE_DIR/instantmeshes-cli"
ls -lh "$RELEASE_DIR/"
