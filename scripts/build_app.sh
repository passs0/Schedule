#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Schedule"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building ${APP_NAME} (release)..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Binary not found at $BIN_PATH"
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/${APP_NAME}"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

ICON_BUNDLE="$ROOT_DIR/Resources/Schedule.icon"
if [[ -d "$ICON_BUNDLE" ]] && xcrun --find actool >/dev/null 2>&1; then
    echo "Compiling dynamic icon bundle ($ICON_BUNDLE) with actool..."
    xcrun actool "$ICON_BUNDLE" \
        --compile "$RESOURCES_DIR" \
        --app-icon Schedule \
        --platform macosx \
        --target-device mac \
        --minimum-deployment-target 15.0 \
        --output-partial-info-plist "$ROOT_DIR/.build/icon-info.plist"
    if [[ ! -f "$RESOURCES_DIR/AppIcon.icns" && -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
        cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    fi
elif [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built app bundle at: $APP_BUNDLE"
