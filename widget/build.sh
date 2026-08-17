#!/bin/bash
# Builds the vendored PockKit framework-dylib and both Pock widgets.
set -euo pipefail
cd "$(dirname "$0")"

DIST="dist"
ARCHS=("arm64" "x86_64")
MIN_MACOS="15.0"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
MODULE_DIR="$DIST/PockKit.swiftmodule"
POCKKIT_INSTALL_NAME="@rpath/PockKit.framework/PockKit"

# Single source of truth for every Agent Status artifact.
source version.env

rm -rf "$DIST"
mkdir -p "$DIST/archs" "$MODULE_DIR" "$DIST/lib"

echo "==> Building PockKit ($POCKKIT_INSTALL_NAME)"
for arch in "${ARCHS[@]}"; do
    swiftc -target "${arch}-apple-macos${MIN_MACOS}" -sdk "$SDKROOT" \
        -emit-library -emit-module -module-name PockKit -O \
        -emit-module-path "$MODULE_DIR/${arch}.swiftmodule" \
        -Xlinker -install_name -Xlinker "$POCKKIT_INSTALL_NAME" \
        -o "$DIST/archs/PockKit-${arch}" \
        Vendor/PockKit/*.swift
done
lipo -create "$DIST"/archs/PockKit-* -output "$DIST/lib/libPockKit.dylib"

# Shim so test executables can resolve @rpath/PockKit.framework/PockKit.
mkdir -p "$DIST/lib/PockKit.framework"
ln -sf ../libPockKit.dylib "$DIST/lib/PockKit.framework/PockKit"

echo "==> Building AgentTouchBar widget"
# The widget resolves PockKit symbols at load time from Pock's own embedded
# framework (plugin-style, -undefined dynamic_lookup). This makes the bundle
# load in ANY Pock version regardless of how its PockKit was built.
for arch in "${ARCHS[@]}"; do
    swiftc -target "${arch}-apple-macos${MIN_MACOS}" -sdk "$SDKROOT" \
        -emit-library -module-name AgentTouchBar -O \
        -I "$DIST" \
        -Xlinker -undefined -Xlinker dynamic_lookup \
        Sources/*.swift \
        -o "$DIST/archs/AgentTouchBar-${arch}"
done

BUNDLE="$DIST/AgentTouchBar.pock"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
lipo -create "$DIST"/archs/AgentTouchBar-* -output "$BUNDLE/Contents/MacOS/AgentTouchBar"
cp Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/*.png "$BUNDLE/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $AGENT_TOUCH_BAR_VERSION" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $AGENT_TOUCH_BAR_BUILD" "$BUNDLE/Contents/Info.plist"

echo "==> Bundle: $BUNDLE"
otool -L "$BUNDLE/Contents/MacOS/AgentTouchBar" | head -6
echo "==> Agent Status version: $AGENT_TOUCH_BAR_VERSION ($AGENT_TOUCH_BAR_BUILD)"

# Always emit installable archives so the .pock and .pkarchive can never
# drift to different versions. Pock expects the .pock folder at archive root.
(
    cd "$DIST"
    rm -f AgentTouchBar.pkarchive "AgentTouchBar-$AGENT_TOUCH_BAR_VERSION.pkarchive"
    zip -r -q AgentTouchBar.pkarchive AgentTouchBar.pock
    cp AgentTouchBar.pkarchive "AgentTouchBar-$AGENT_TOUCH_BAR_VERSION.pkarchive"
)
echo "==> Archive: $DIST/AgentTouchBar.pkarchive"
echo "==> Archive: $DIST/AgentTouchBar-$AGENT_TOUCH_BAR_VERSION.pkarchive"

if [[ "${1:-}" == "--install" ]]; then
    WIDGETS_DIR="$HOME/Library/Application Support/Pock/Widgets"
    mkdir -p "$WIDGETS_DIR"
    rm -rf "$WIDGETS_DIR/AgentTouchBar.pock"
    cp -R "$BUNDLE" "$WIDGETS_DIR/AgentTouchBar.pock"
    echo "==> Installed to $WIDGETS_DIR/AgentTouchBar.pock"
    echo "==> Restart Pock (menu bar icon → Relaunch) to load the widget."
fi
