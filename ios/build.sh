#!/bin/bash
#
# build.sh — build the pianobar iOS app with plain clang/swiftc
# (no Xcode project needed; the Xcode project in ios/ is for debugging).
#
# Usage:
#   ./ios/build.sh           # arm64 iOS simulator
#   ./ios/build.sh device    # arm64 device
#
# Output: ios/build/PianoApp.app
#
# Copyright (c) 2025 Spencer Graffunder
# MIT licensed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Use the full Xcode (not CommandLineTools) for the iOS SDKs.
if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app
fi

MODE="${1:-sim}"
if [ "$MODE" = "sim" ]; then
    SDK=$(xcrun --show-sdk-path --sdk iphonesimulator)
    TARGET="arm64-apple-ios16.0-simulator"
else
    SDK=$(xcrun --show-sdk-path --sdk iphoneos)
    TARGET="arm64-apple-ios16.0"
fi

BUILD=ios/build
rm -rf "$BUILD"
mkdir -p "$BUILD/obj" "$BUILD/PianoApp.app"

INC="-Isrc -Isrc/libpiano -Iios/Shim -Iios/Shim/avstubs -Iios/Glue"
CLANG="xcrun clang -target $TARGET -isysroot $SDK -Os -fPIC $INC"

# --- C core (unmodified), shims, glue ---
CORE_SOURCES="
    src/libpiano/piano.c
    src/libpiano/request.c
    src/libpiano/response.c
    src/libpiano/list.c
    src/libpiano/crypt.c
    ios/Shim/gcrypt_impl.c
    ios/Shim/curl_impl.c
    ios/Glue/piano_ios.c
"
for f in $CORE_SOURCES; do
    base=$(basename "$f" .c)
    echo "CC  $f"
    $CLANG -c "$f" -o "$BUILD/obj/$base.o"
done

echo "CC  ios/Shim/json_impl.m (objc)"
$CLANG -fobjc-arc -x objective-c -c ios/Shim/json_impl.m \
    -o "$BUILD/obj/json_impl.o"

echo "AR  libpiano_ios.a"
xcrun libtool -static -o "$BUILD/libpiano_ios.a" "$BUILD"/obj/*.o

# --- Swift app ---
echo "SWIFT PianoApp"
xcrun swiftc -O \
    -target "$TARGET" \
    -sdk "$SDK" \
    -import-objc-header ios/PianoApp/PianoBridging.h \
    -Xcc -Iios/Shim -Xcc -Iios/Shim/avstubs -Xcc -Iios/Glue \
    -Xcc -Isrc/libpiano -Xcc -Isrc \
    ios/PianoApp/PianoApp.swift \
    ios/PianoApp/ContentView.swift \
    ios/PianoApp/PianoClient.swift \
    ios/PianoApp/Player.swift \
    "$BUILD/libpiano_ios.a" \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework Security \
    -o "$BUILD/PianoApp.app/PianoApp"

# --- Info.plist (shared with the Xcode project) ---
# Expand the $(...) build variables for a standalone bundle.
sed -e 's/$(EXECUTABLE_NAME)/PianoApp/' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/net.6xq.pianobar.ios/' \
    -e 's/$(PRODUCT_NAME)/PianoApp/' \
    "$ROOT/ios/PianoApp/Info.plist" > "$BUILD/PianoApp.app/Info.plist"

echo
echo "Built $BUILD/PianoApp.app"
