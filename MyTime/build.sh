#!/bin/bash
# Builds MyTime.app. No Xcode project, no package manager - just swiftc.
set -euo pipefail
cd "$(dirname "$0")"

NAME="MyTime"
APP="build/$NAME.app"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -wmo \
    -target "${ARCH}-apple-macos11.0" \
    -o "$APP/Contents/MacOS/$NAME" \
    Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for a locally built app to run without complaint.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "built $(cd "$(dirname "$APP")" && pwd)/$NAME.app"
