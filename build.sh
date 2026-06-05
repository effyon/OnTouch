#!/bin/bash
# Build OnTouch and assemble a .app bundle, then ad-hoc code-sign it so macOS
# remembers its Accessibility / Input Monitoring permissions across builds.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
APP="OnTouch.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/OnTouch"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OnTouch"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> ad-hoc code signing"
codesign --force --sign - --identifier com.local.ontouch "$APP"

echo "==> done: $(pwd)/$APP"
echo "    Launch with: open '$APP'   (or ./run.sh to see logs)"
