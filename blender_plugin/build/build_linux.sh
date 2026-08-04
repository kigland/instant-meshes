#!/bin/bash
set -euo pipefail

# Build instantmeshes-cli for Linux x86_64 and package a platform-specific Blender addon.
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build_linux"
ADDON_SRC="$PROJECT_ROOT/instant_meshes"
RELEASE_DIR="$PROJECT_ROOT/release"

echo "=== Building instantmeshes-cli for Linux x86_64 ==="

rm -rf "$BUILD_DIR" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build "$BUILD_DIR" --target instantmeshes-cli -j$(nproc)

strip "$BUILD_DIR/instantmeshes-cli"
cp "$BUILD_DIR/instantmeshes-cli" "$RELEASE_DIR/instantmeshes-cli-linux-x86_64"

# Package Blender addon
echo "--- Packaging Blender addon ---"
ADDON_TMP="/tmp/im_addon_linux"
rm -rf "$ADDON_TMP"
mkdir -p "$ADDON_TMP/instant_meshes/bin"
cp "$ADDON_SRC"/__init__.py "$ADDON_TMP/instant_meshes/"
cp "$ADDON_SRC"/operators.py "$ADDON_TMP/instant_meshes/"
cp "$ADDON_SRC"/panel.py "$ADDON_TMP/instant_meshes/"
cp "$ADDON_SRC"/preferences.py "$ADDON_TMP/instant_meshes/"
cp "$BUILD_DIR/instantmeshes-cli" "$ADDON_TMP/instant_meshes/bin/instantmeshes-cli"
cd "$ADDON_TMP" && zip -r "$RELEASE_DIR/instant-meshes-blender-linux.zip" instant_meshes/

echo ""
echo "=== Done ==="
echo "Standalone CLI: $RELEASE_DIR/instantmeshes-cli-linux-x86_64"
echo "Blender addon:   $RELEASE_DIR/instant-meshes-blender-linux.zip"
ls -lh "$RELEASE_DIR/"
