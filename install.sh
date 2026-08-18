#!/bin/bash
# Installs Agent Status from GitHub, a release bundle, or a source checkout.
set -Eeuo pipefail

REPOSITORY="therswamhtet/agent-status-pock"
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
ROOT=""
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
    ROOT="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
fi
INSTALL_DIR="$HOME/.agentbridge"
HOOK_PATH="$INSTALL_DIR/hooks/agentbridge-hook.py"

die() {
    echo "Error: $*" >&2
    exit 1
}

command -v sw_vers >/dev/null 2>&1 || die "Agent Status requires macOS."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$MACOS_MAJOR" -ge 15 ]] || die "macOS 15 or newer is required."
command -v python3 >/dev/null 2>&1 || die "Python 3 is required. Install the Xcode Command Line Tools and try again."
command -v curl >/dev/null 2>&1 || die "curl is required to install and verify AgentBridge."

# When piped from GitHub, fetch the prebuilt artifact and hand installation to it.
if [[ -z "$ROOT" ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required to download the release."
    command -v unzip >/dev/null 2>&1 || die "unzip is required to unpack the release."
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT
    ARCHIVE="$TMP_DIR/download.zip"
    URL="$(curl --fail --silent --show-error --retry 3 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPOSITORY/releases/latest" | python3 -c '
import json, sys
assets = json.load(sys.stdin).get("assets", [])
matches = [asset["browser_download_url"] for asset in assets
           if asset.get("name", "").endswith("-ready.zip")]
if not matches:
    raise SystemExit("No ready-to-use release asset was found.")
print(next((url for url in matches if url.endswith("agent-status-pock-ready.zip")), matches[0]))
')" || die "Could not resolve the latest release."
    echo "==> Downloading the latest Agent Status release"
    curl --fail --location --silent --show-error --retry 3 --output "$ARCHIVE" "$URL" \
        || die "Could not download $URL. Check that the repository has a published release."
    unzip -q "$ARCHIVE" -d "$TMP_DIR"
    BUNDLES=("$TMP_DIR"/agent-status-pock-*/)
    [[ ${#BUNDLES[@]} -eq 1 && -f "${BUNDLES[0]}/install.sh" ]] \
        || die "The downloaded release has an unexpected structure."
    bash "${BUNDLES[0]}/install.sh"
    exit 0
fi

if [[ -x "$ROOT/bin/agentbridge" && -d "$ROOT/AgentTouchBar.pock" ]]; then
    exec bash "$ROOT/scripts/install-release.sh"
fi

command -v swift >/dev/null 2>&1 || die "Swift is required for a source install. Use a release or install Xcode Command Line Tools."
command -v xcrun >/dev/null 2>&1 || die "Xcode Command Line Tools are required for a source install."

echo "==> Building bridge"
(cd "$ROOT/bridge" && swift build -c release)

echo "==> Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/hooks" "$INSTALL_DIR/logs"
cp "$ROOT/bridge/.build/release/AgentBridge" "$INSTALL_DIR/bin/agentbridge"
cp "$ROOT/hooks/agentbridge-hook.py" "$HOOK_PATH"
cp "$ROOT/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
chmod +x "$HOOK_PATH" "$INSTALL_DIR/bin/agentbridge" "$INSTALL_DIR/uninstall.sh"

echo "==> Installing LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"
PLIST="$HOME/Library/LaunchAgents/com.touchbar.agentbridge.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.touchbar.agentbridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/bin/agentbridge</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/logs/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/logs/stderr.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "    AgentBridge daemon started on http://127.0.0.1:3939"

echo "==> Building and installing Pock widget"
(cd "$ROOT/widget" && ./build.sh --install)

echo "==> Installing Claude Code hooks"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
python3 - "$CLAUDE_SETTINGS" "$ROOT/hooks/claude/settings.hooks.json" <<'PYEOF'
import json, os, shutil, sys
settings_path, snippet_path = sys.argv[1], sys.argv[2]
with open(snippet_path) as f:
    snippet = json.load(f)
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
    backup = settings_path + ".bak-agentbridge"
    if not os.path.exists(backup):
        shutil.copy2(settings_path, backup)
hooks = settings.setdefault("hooks", {})
for event, entries in snippet["hooks"].items():
    hooks.setdefault(event, [])
    for entry in entries:
        if entry not in hooks[event]:
            hooks[event].append(entry)
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
temp_path = settings_path + ".tmp-agentbridge"
with open(temp_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(temp_path, settings_path)
print("    merged into ~/.claude/settings.json")
PYEOF

echo "==> Installing Codex hooks"
CODEX_HOOKS="$HOME/.codex/hooks.json"
python3 - "$CODEX_HOOKS" "$ROOT/hooks/codex/hooks.json.template" "$HOOK_PATH" <<'PYEOF'
import json, os, sys
path, template_path, hook_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(template_path) as f:
    template = json.loads(f.read().replace("@@HOOK_PATH@@", hook_path))
hooks = {}
if os.path.exists(path):
    with open(path) as f:
        hooks = json.load(f)
events = hooks.setdefault("hooks", {})
for event, entries in template["hooks"].items():
    events.setdefault(event, [])
    # Replace older AgentBridge entries so stale wildcard matchers/args do
    # not remain active alongside the corrected command.
    events[event] = [entry for entry in events[event]
                     if hook_path not in json.dumps(entry)]
    for entry in entries:
        if entry not in events[event]:
            events[event].append(entry)
os.makedirs(os.path.dirname(path), exist_ok=True)
temp_path = path + ".tmp-agentbridge"
with open(temp_path, "w") as f:
    json.dump(hooks, f, indent=2)
    f.write("\n")
os.replace(temp_path, path)
print("    wrote ~/.codex/hooks.json (run /hooks in Codex to trust the new hooks)")
PYEOF

echo "==> Installing opencode plugin"
mkdir -p "$HOME/.config/opencode/plugins"
OPENCODE_PLUGIN="$HOME/.config/opencode/plugins/agentbridge.js"
if [[ -f "$OPENCODE_PLUGIN" && ! -f "$OPENCODE_PLUGIN.bak-agentbridge" ]]; then
    cp "$OPENCODE_PLUGIN" "$OPENCODE_PLUGIN.bak-agentbridge"
fi
cp "$ROOT/plugin-opencode/agentbridge.js" "$OPENCODE_PLUGIN"
echo "    copied to ~/.config/opencode/plugins/agentbridge.js"

echo "==> Verifying AgentBridge"
HEALTHY=false
for _ in {1..20}; do
    if curl --fail --silent "http://127.0.0.1:3939/v1/health" >/dev/null; then
        HEALTHY=true
        break
    fi
    sleep 0.25
done
[[ "$HEALTHY" == true ]] || die "AgentBridge did not start. See $INSTALL_DIR/logs/stderr.log."

echo
echo "Done. Next steps:"
echo "  1. Relaunch Pock, then drag 'Agent Status' into your Touch Bar via"
echo "     Customize Pock…"
echo "  2. In Codex, run /hooks and trust the AgentBridge hooks."
echo "  3. Restart Claude Code / Codex CLI / OpenCode sessions."
echo "  4. Uninstall at any time with: $INSTALL_DIR/uninstall.sh"
