#!/bin/bash
set -e

# FineTune Local Build Script
#
# Builds a Release .app from the current working tree, signed ad-hoc, that
# actually launches on this machine. Intended for running your own branch
# without an Apple Developer account.
#
# Two things this handles that a plain `xcodebuild` does not:
#
#  1. Library validation. The project enables hardened runtime. Under an ad-hoc
#     signature there is no Team ID, so the runtime refuses to load the embedded
#     Sparkle.framework ("mapping process and mapped file have different Team
#     IDs") and the app dies in dyld before main() — no window, no icon, no
#     error. Fixed by adding com.apple.security.cs.disable-library-validation
#     and re-signing every nested bundle from the inside out.
#
#  2. Sparkle downgrades. A local build carries the project's default version
#     (1.0.0), which is older than every entry in appcast.xml. With
#     SUAutomaticallyUpdate on, Sparkle would silently replace your build with
#     the latest public release. The version is stamped above the appcast so
#     that cannot happen.
#
# Usage:
#   scripts/build-local.sh                 # build to ./build/local
#   scripts/build-local.sh ~/Desktop/Test  # build to a chosen directory
#   VERSION=2.0.0 scripts/build-local.sh   # override the stamped version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEST="${1:-$PROJECT_DIR/build/local}"
VERSION="${VERSION:-1.9.99}"
BUILD_NUMBER="${BUILD_NUMBER:-9999}"

DERIVED="$PROJECT_DIR/build/DerivedData-local"
ENTITLEMENTS="$PROJECT_DIR/build/local-adhoc.entitlements"
APP="$DEST/FineTune.app"

echo "==> Building Release ($VERSION build $BUILD_NUMBER)..."
mkdir -p "$PROJECT_DIR/build"
xcodebuild -project "$PROJECT_DIR/FineTune.xcodeproj" \
    -scheme FineTune \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    build > "$PROJECT_DIR/build/build-local.log" 2>&1 \
  || { echo "Build failed. Last errors:"; grep -E "error:" "$PROJECT_DIR/build/build-local.log" | grep -v CoreSimulator | head -10; exit 1; }

BUILT="$DERIVED/Build/Products/Release/FineTune.app"
[ -d "$BUILT" ] || { echo "Build succeeded but $BUILT is missing."; exit 1; }

echo "==> Staging to $DEST..."
mkdir -p "$DEST"
rm -rf "$APP"
cp -R "$BUILT" "$APP"

echo "==> Writing ad-hoc entitlements..."
# Mirrors FineTune/FineTune.entitlements, plus the library-validation opt-out
# that ad-hoc signing requires. Keep in sync if the shipping entitlements change.
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.device.bluetooth</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
PLIST

sign() {
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$1" 2>&1 \
        | grep -v "replacing existing signature" || true
}

echo "==> Re-signing nested code (inside out)..."
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FRAMEWORK" ]; then
    for xpc in "$FRAMEWORK/Versions/B/XPCServices/"*.xpc; do
        [ -e "$xpc" ] && sign "$xpc"
    done
    [ -d "$FRAMEWORK/Versions/B/Updater.app" ] && sign "$FRAMEWORK/Versions/B/Updater.app"
    [ -e "$FRAMEWORK/Versions/B/Autoupdate" ] && sign "$FRAMEWORK/Versions/B/Autoupdate"
    sign "$FRAMEWORK/Versions/B"
fi
sign "$APP"

echo "==> Verifying..."
codesign --verify --strict "$APP" || { echo "Signature verification failed."; exit 1; }
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "disable-library-validation" \
    || { echo "Entitlement missing — the app will not launch."; exit 1; }

# Signature validity is not enough: the Team ID mismatch only surfaces at load
# time. Launch it and confirm the process survives.
echo "==> Launch check..."
# Wait for any previous instance to actually exit. Calling open() while
# LaunchServices still holds the dying process returns -600 (procNotFound).
pkill -x FineTune 2>/dev/null || true
for _ in $(seq 1 10); do
    pgrep -x FineTune > /dev/null || break
    sleep 1
done

# open can still lose the race on a freshly replaced bundle; retry once.
open "$APP" 2>/dev/null || { sleep 2; open "$APP"; }

for _ in $(seq 1 15); do
    if pgrep -x FineTune > /dev/null; then
        echo ""
        echo "Built and running: $APP"
        echo "Version $VERSION (build $BUILD_NUMBER) — above appcast, so Sparkle will not downgrade it."
        echo "FineTune is a menu bar app (LSUIElement): no Dock icon, look in the menu bar."

        # DDC probing blanks some external displays behind USB-C/HDMI adapters.
        # Running the test suite has been observed to rewrite the live settings
        # file, so re-check after a build rather than assume it stuck.
        SETTINGS="$HOME/Library/Application Support/FineTune/settings.json"
        if [ -f "$SETTINGS" ] && command -v python3 > /dev/null; then
            python3 - "$SETTINGS" <<'PY'
import json, sys
try:
    v = json.load(open(sys.argv[1])).get("ddcVolumeControlEnabled")
except Exception:
    sys.exit(0)
if v is not True:
    sys.exit(0)
print("")
print("NOTE: DDC monitor-volume control is ON.")
print("      If an external display goes dark, turn it off in Settings > Audio.")
PY
        fi
        exit 0
    fi
    sleep 1
done

echo "App did not stay running. Diagnose with:"
echo "  $APP/Contents/MacOS/FineTune"
exit 1
