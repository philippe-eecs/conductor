#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
cd "$ROOT"

APP_NAME="Conductor"
VERSION="$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
OUT_ROOT="$ROOT/.build/release-app"
APP_DIR="$OUT_ROOT/${APP_NAME}.app"
ZIP_PATH="$OUT_ROOT/${APP_NAME}-${VERSION}.zip"

echo "Building $APP_NAME v$VERSION ..."

mkdir -p "$OUT_ROOT"
rm -rf "$APP_DIR" "$ZIP_PATH"

# Build universal binary (Apple Silicon + Intel)
swift build --disable-sandbox -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build --disable-sandbox -c release --arch arm64 --arch x86_64 --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

# Assemble .app bundle
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Sources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Stamp version into Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"

# Code signing
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Codesigning with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "Warning: no Developer ID identity found; using ad-hoc signing."
  echo "Testers will need: xattr -cr Conductor.app"
  codesign --force --deep --sign - "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# Create zip for distribution
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo ""
echo "=== Build complete ==="
echo "  App:     $APP_DIR"
echo "  Zip:     $ZIP_PATH"
echo "  Version: $VERSION"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v$VERSION '$ZIP_PATH' --title 'v$VERSION' --notes-file '$REPO_ROOT/CHANGELOG.md'"
