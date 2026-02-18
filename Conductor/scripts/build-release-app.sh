#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Conductor"
OUT_ROOT="$ROOT/.build/release-app"
APP_DIR="$OUT_ROOT/${APP_NAME}.app"
ZIP_PATH="$OUT_ROOT/${APP_NAME}.zip"

mkdir -p "$OUT_ROOT"
rm -rf "$APP_DIR" "$ZIP_PATH"

BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Sources/Info.plist" "$APP_DIR/Contents/Info.plist"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Codesigning with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "Warning: no Developer ID identity found; using ad-hoc signing."
  echo "This is fine for local testing but not for distribution."
  codesign --force --deep --sign - "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "Built app: $APP_DIR"
echo "Zipped app: $ZIP_PATH"
