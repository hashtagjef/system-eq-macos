#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-debug}"
APP_DIR="$ROOT_DIR/build/System EQ.app"
STAGING_ROOT="$(mktemp -d "/private/tmp/system-eq-build.XXXXXX")"
STAGED_APP="$STAGING_ROOT/System EQ.app"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-cache"
swift build -c "$CONFIGURATION" --disable-sandbox --scratch-path "$ROOT_DIR/.build"

BIN_DIR="$(swift build -c "$CONFIGURATION" --disable-sandbox --scratch-path "$ROOT_DIR/.build" --show-bin-path)"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/SystemEQ" "$STAGED_APP/Contents/MacOS/SystemEQ"
cp "$ROOT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
xattr -cr "$STAGED_APP"
codesign --force --deep --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

mkdir -p "$APP_DIR"
ditto --noextattr --norsrc "$STAGED_APP" "$APP_DIR"
xattr -cr "$APP_DIR"

echo "$APP_DIR"
