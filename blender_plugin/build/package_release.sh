#!/bin/bash
set -euo pipefail

# Package the Blender addon + platform binaries for release
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$PROJECT_ROOT/release"
ADDON_DIR="$PROJECT_ROOT/blender_plugin"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "=== Packaging Instant Meshes Blender Addon Release ==="

# 1. Package just the addon (user installs via Blender Preferences)
echo "--- Packaging addon ---"
ADDON_ZIP="$RELEASE_DIR/instant-meshes-blender-addon.zip"
cd "$PROJECT_ROOT"
zip -r "$ADDON_ZIP" blender_plugin/ \
  -x "blender_plugin/build/*" \
  -x "*.pyc" \
  -x "*__pycache__*" \
  -x ".DS_Store"
echo "  $ADDON_ZIP"

# 2. Build CLI binaries (if available)
echo "--- Checking CLI binaries ---"
if [ -f "$RELEASE_DIR/instantmeshes-cli" ]; then
  echo "  macOS universal: $(file "$RELEASE_DIR/instantmeshes-cli")"
fi

# 3. Create platform-specific addon packages (addon + binary)
# macOS
if [ -f "$RELEASE_DIR/instantmeshes-cli" ]; then
  echo "--- Packaging macOS addon+binary ---"
  MACOS_ZIP="$RELEASE_DIR/instant-meshes-blender-macos.zip"
  mkdir -p /tmp/im_pkg/blender_plugin/bin
  cp -r "$ADDON_DIR"/*.py /tmp/im_pkg/blender_plugin/
  cp "$RELEASE_DIR/instantmeshes-cli" /tmp/im_pkg/blender_plugin/bin/
  cd /tmp/im_pkg
  zip -r "$MACOS_ZIP" blender_plugin/
  rm -rf /tmp/im_pkg
  echo "  $MACOS_ZIP"
fi

echo ""
echo "=== Release files ==="
ls -lh "$RELEASE_DIR"/
