#!/bin/bash
set -e

# Change to project root (script location's parent)
SCRIPT_DIR="$(dirname "$0")"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Configuration
APP_NAME="Conductor"
BUNDLE_ID="com.conductor.app"
SPM_DIR="Conductor"
BUILD_DIR="$SPM_DIR/.build/release"
APP_DIR="build/${APP_NAME}.app"

# Build release binary
cd "$SPM_DIR"
swift build -c release
cd "$PROJECT_ROOT"

# Create app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"

# Copy Info.plist
cp "$SPM_DIR/Sources/Info.plist" "$APP_DIR/Contents/"

# Create ad-hoc entitlements (without keychain-access-groups which needs team ID)
cat > "$APP_DIR/Contents/Entitlements.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.personal-information.calendars</key>
    <true/>
    <key>com.apple.security.personal-information.reminders</key>
    <true/>
</dict>
</plist>
EOF

# Prefer a stable signing identity so macOS privacy permissions (TCC) persist across rebuilds.
# You can override via CONDUCTOR_CODESIGN_IDENTITY (e.g. "Apple Development: Name (TEAMID)").
SIGN_IDENTITY="${CONDUCTOR_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '\"' '/\"Apple Development: /{print $2; exit} /\"Developer ID Application: /{print $2; exit}')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="-"
    echo "codesign: No signing identity found; using ad-hoc signing (privacy prompts may re-appear after rebuilds)."
else
    echo "codesign: Using identity: $SIGN_IDENTITY"
fi

# Sign the app
codesign --force --deep --sign "$SIGN_IDENTITY" \
    --entitlements "$APP_DIR/Contents/Entitlements.plist" \
    "$APP_DIR"

# Clean up temporary entitlements
rm "$APP_DIR/Contents/Entitlements.plist"

echo "Built: $APP_DIR"
