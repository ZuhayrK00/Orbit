#!/bin/bash
set -euo pipefail
ORBIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ORBIT_ROOT"
ORBIT_CONFIGURATION="${1:-release}"
swift build -c "$ORBIT_CONFIGURATION"
ORBIT_BIN_DIR="$(swift build -c "$ORBIT_CONFIGURATION" --show-bin-path)"
ORBIT_APP="$ORBIT_ROOT/build/Orbit.app"
mkdir -p "$ORBIT_ROOT/build"
# Build and sign fresh files before replacing the bundle. Overwriting a running
# signed executable in place can leave macOS with stale code-signing cache data.
# https://developer.apple.com/documentation/security/updating-mac-software
ORBIT_STAGE="$(mktemp -d "$ORBIT_ROOT/build/.orbit-package.XXXXXX")"
trap 'rm -rf "$ORBIT_STAGE"' EXIT
ORBIT_STAGED_APP="$ORBIT_STAGE/Orbit.app"
mkdir -p "$ORBIT_STAGED_APP/Contents/MacOS" "$ORBIT_STAGED_APP/Contents/Resources"
cp "$ORBIT_BIN_DIR/Orbit" "$ORBIT_STAGED_APP/Contents/MacOS/Orbit"
cp Resources/Info.plist "$ORBIT_STAGED_APP/Contents/Info.plist"
ORBIT_ICON_DIR="$ORBIT_ROOT/build/Orbit.iconset"
mkdir -p "$ORBIT_ICON_DIR"
"$ORBIT_BIN_DIR/Orbit" --render-icon "$ORBIT_ROOT/build/icon-1024.png"
for ORBIT_SIZE in 16 32 128 256 512; do
    sips -z "$ORBIT_SIZE" "$ORBIT_SIZE" "$ORBIT_ROOT/build/icon-1024.png" --out "$ORBIT_ICON_DIR/icon_${ORBIT_SIZE}x${ORBIT_SIZE}.png" >/dev/null
    ORBIT_DOUBLE=$((ORBIT_SIZE * 2))
    sips -z "$ORBIT_DOUBLE" "$ORBIT_DOUBLE" "$ORBIT_ROOT/build/icon-1024.png" --out "$ORBIT_ICON_DIR/icon_${ORBIT_SIZE}x${ORBIT_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ORBIT_ICON_DIR" -o "$ORBIT_STAGED_APP/Contents/Resources/Orbit.icns"
if [[ -z "${ORBIT_SIGNING_IDENTITY:-}" ]]; then
    # A stable development identity lets macOS recognise permission grants across rebuilds.
    # Use the sole installed Apple Development identity; never guess between teams.
    ORBIT_DEVELOPMENT_IDENTITIES="$(security find-identity -v -p codesigning | sed -nE '/"Apple Development:/s/^[[:space:]]*[0-9]+\) ([A-F0-9]+).*/\1/p')"
    if [[ -n "$ORBIT_DEVELOPMENT_IDENTITIES" && "$ORBIT_DEVELOPMENT_IDENTITIES" != *$'\n'* ]]; then
        ORBIT_SIGNING_IDENTITY="$ORBIT_DEVELOPMENT_IDENTITIES"
    else
        ORBIT_SIGNING_IDENTITY="-"
        printf 'Using ad-hoc signing. macOS may require permission again after rebuilds.\n'
    fi
fi
codesign --force --sign "$ORBIT_SIGNING_IDENTITY" --options runtime --entitlements Resources/Orbit.entitlements "$ORBIT_STAGED_APP"
codesign --verify --strict "$ORBIT_STAGED_APP"
if [[ -e "$ORBIT_APP" ]]; then mv "$ORBIT_APP" "$ORBIT_STAGE/Previous.app"; fi
if ! mv "$ORBIT_STAGED_APP" "$ORBIT_APP"; then
    if [[ -e "$ORBIT_STAGE/Previous.app" ]] && ! mv "$ORBIT_STAGE/Previous.app" "$ORBIT_APP"; then
        trap - EXIT
        printf 'Previous app preserved at: %s\n' "$ORBIT_STAGE/Previous.app" >&2
    fi
    exit 1
fi
printf 'Built: %s\n' "$ORBIT_APP"
