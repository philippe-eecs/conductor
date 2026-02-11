#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p /tmp/clang/ModuleCache /tmp/swiftpm-cache
export XDG_CACHE_HOME=/tmp
export SWIFTPM_CACHE_PATH=/tmp/swiftpm-cache
export CLANG_MODULE_CACHE_PATH=/tmp/clang/ModuleCache

BIN_DIR="$(swift build --disable-sandbox -c debug --show-bin-path)"
BIN="$BIN_DIR/Conductor"

APP_DIR="$ROOT/.build/dev-app/Conductor.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/Conductor"
chmod +x "$APP_DIR/Contents/MacOS/Conductor"

cp "$ROOT/Sources/Info.plist" "$APP_DIR/Contents/Info.plist"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Codesigning with: $SIGN_IDENTITY"
  if ! codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null 2>&1; then
    echo "Warning: codesign failed with '$SIGN_IDENTITY'; falling back to ad-hoc signing."
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
  fi
else
  echo "Warning: no Apple Development identity found; using ad-hoc signing. (TCC may re-prompt after rebuilds)"
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

open -n "$APP_DIR"
