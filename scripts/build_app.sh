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
    if ! xcrun actool "$ICON_BUNDLE" \
        --compile "$RESOURCES_DIR" \
        --app-icon Schedule \
        --platform macosx \
        --minimum-deployment-target 26.0 \
        --development-region en \
        --enable-on-demand-resources NO \
        --output-partial-info-plist "$ROOT_DIR/.build/icon-info.plist"; then

        echo "Retrying actool with Xcode 26 compatible icon.json (stripping macOS 27 refractivity keys)..."
        STAGE_ICON="$ROOT_DIR/.build/Schedule.icon"
        rm -rf "$STAGE_ICON"
        cp -R "$ICON_BUNDLE" "$STAGE_ICON"
        python3 -c '
import json, pathlib
p = pathlib.Path("'"$STAGE_ICON"'/icon.json")
data = json.loads(p.read_text())
data.pop("features", None)
for g in data.get("groups", []):
    g.pop("refractivity", None)
p.write_text(json.dumps(data, indent=2))
'
        xcrun actool "$STAGE_ICON" \
            --compile "$RESOURCES_DIR" \
            --app-icon Schedule \
            --platform macosx \
            --minimum-deployment-target 26.0 \
            --development-region en \
            --enable-on-demand-resources NO \
            --output-partial-info-plist "$ROOT_DIR/.build/icon-info.plist"
    fi
    ls -la "$RESOURCES_DIR"
fi

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built app bundle at: $APP_BUNDLE"
