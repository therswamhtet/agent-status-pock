#!/bin/bash
# Builds the "ready-to-use" release bundle: prebuilt bridge + widgets +
# hooks, packaged with a no-compiler install script.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

source widget/version.env
VERSION="$AGENT_TOUCH_BAR_VERSION"
BUILD="$AGENT_TOUCH_BAR_BUILD"
STAGE="$ROOT/.release/agent-status-pock-$VERSION"
ZIP="$ROOT/.release/agent-status-pock-$VERSION-ready.zip"

echo "==> Building bridge (universal)"
cd "$ROOT/bridge"
swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1

echo "==> Building widgets"
cd "$ROOT/widget"
./build.sh >/dev/null 2>&1

echo "==> Staging release bundle"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/hooks/claude" "$STAGE/hooks/codex" "$STAGE/plugin-opencode"

cp "$ROOT/bridge/.build/out/Products/Release/AgentBridge" "$STAGE/bin/agentbridge"
chmod +x "$STAGE/bin/agentbridge"

cp "$ROOT/hooks/agentbridge-hook.py" "$STAGE/hooks/"
cp "$ROOT/hooks/claude/settings.hooks.json" "$STAGE/hooks/claude/"
cp "$ROOT/hooks/codex/hooks.json.template" "$STAGE/hooks/codex/"
cp "$ROOT/plugin-opencode/agentbridge.js" "$STAGE/plugin-opencode/"

cp -R "$ROOT/widget/dist/AgentTouchBar.pock" "$STAGE/"

cp "$ROOT/scripts/install-release.sh" "$STAGE/install.sh"
cp "$ROOT/uninstall.sh" "$STAGE/uninstall.sh"
cp "$ROOT/scripts/RELEASE-README.md" "$STAGE/README.md"
chmod +x "$STAGE/install.sh" "$STAGE/uninstall.sh"

echo "==> Packaging $ZIP"
(cd "$STAGE/.." && rm -f "$ZIP" && zip -r -q "$ZIP" "agent-status-pock-$VERSION")

echo "==> Done"
echo "    Version : $VERSION (build $BUILD)"
echo "    Artifact: $ZIP"
echo "    Size    : $(du -h "$ZIP" | cut -f1)"
