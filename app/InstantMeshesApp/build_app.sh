#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
CORE_LIB="$BUILD_DIR/libinstantmeshes_core.a"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
TARGET="arm64-apple-macosx15.0"
OUTPUT_APP="$APP_DIR/build/Instant Meshes.app"

echo "=== Building Instant Meshes SwiftUI App ==="

if [ ! -f "$CORE_LIB" ]; then
    echo "ERROR: libinstantmeshes_core.a not found at $CORE_LIB"
    echo "Run: cmake --build ../../build --target instantmeshes_core"
    exit 1
fi

rm -rf "$APP_DIR/build"
mkdir -p "$APP_DIR/build"

CXX_INCLUDES=(
    -I"$PROJECT_ROOT/src"
    -I"$PROJECT_ROOT/ext/nanogui/ext/eigen"
    -I"$PROJECT_ROOT/ext/tbb/include"
    -I"$PROJECT_ROOT/ext/dset"
    -I"$PROJECT_ROOT/ext/half"
    -I"$PROJECT_ROOT/ext/pcg32"
    -I"$PROJECT_ROOT/ext/pss"
    -I"$PROJECT_ROOT/ext/rply"
    -I"$APP_DIR"
)

SDK_OPTS=(-sdk "$SDK_PATH" -target "$TARGET")

# --- Step 1: Compile C API bridge (ObjC++) ---
echo "--- Compiling C API bridge ---"
clang++ -std=c++14 -c \
    -arch arm64 \
    -isysroot "$SDK_PATH" \
    -mmacosx-version-min=13.0 \
    -D__TBB_NO_IMPLICIT_LINKAGE \
    -Wno-deprecated-declarations \
    -Wno-int-in-bool-context \
    -Wno-deprecated-copy \
    "${CXX_INCLUDES[@]}" \
    -o "$APP_DIR/build/MeshEngineCAPI.o" \
    "$APP_DIR/MeshEngineCAPI.mm"

# --- Step 2: Compile Swift ---
echo "--- Compiling Swift ---"

MODULE_CACHE="$APP_DIR/build/ModuleCache"
rm -rf "$MODULE_CACHE"

# Compile each Swift file separately to avoid -o conflict
for sf in App ContentView GLMeshView MeshViewModel; do
    swiftc "${SDK_OPTS[@]}" \
        -O \
        -Xfrontend -disable-implicit-swift-modules \
        -module-cache-path "$MODULE_CACHE" \
        -framework SwiftUI \
        -framework AppKit \
        -framework OpenGL \
        -framework UniformTypeIdentifiers \
        -import-objc-header "$APP_DIR/bridging_header.h" \
        -I "$APP_DIR" \
        -c \
        "$APP_DIR/${sf}.swift" \
        -o "$APP_DIR/build/${sf}.o"
done

# --- Step 3: Link with swiftc ---
echo "--- Linking ---"
mkdir -p "$OUTPUT_APP/Contents/MacOS"

swiftc "${SDK_OPTS[@]}" \
    -Xlinker -rpath -Xlinker /usr/lib/swift \
    -L "$BUILD_DIR" \
    -linstantmeshes_core \
    -framework SwiftUI \
    -framework AppKit \
    -framework OpenGL \
    -framework UniformTypeIdentifiers \
    -framework Foundation \
    "$APP_DIR/build/MeshEngineCAPI.o" \
    "$APP_DIR/build/App.o" \
    "$APP_DIR/build/ContentView.o" \
    "$APP_DIR/build/GLMeshView.o" \
    "$APP_DIR/build/MeshViewModel.o" \
    -o "$OUTPUT_APP/Contents/MacOS/Instant Meshes"

# --- Step 4: Bundle ---
cp "$APP_DIR/Info.plist" "$OUTPUT_APP/Contents/Info.plist"
mkdir -p "$OUTPUT_APP/Contents/Resources"

echo ""
echo "=== Build complete ==="
echo "App: $OUTPUT_APP"
echo "Run: open '$OUTPUT_APP'"
