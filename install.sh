#!/bin/bash
# Installs Agent Touch Bar: bridge daemon + LaunchAgent + Pock widget +
# agent hooks (Claude Code, Codex, opencode).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.agentbridge"
HOOK_PATH="$INSTALL_DIR/hooks/agentbridge-hook.py"

echo "==> Building bridge"
(cd "$ROOT/bridge" && swift build -c release)

echo "==> Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/hooks" "$INSTALL_DIR/logs"
cp "$ROOT/bridge/.build/release/AgentBridge" "$INSTALL_DIR/bin/agentbridge"
cp "$ROOT/hooks/agentbridge-hook.py" "$HOOK_PATH"
chmod +x "$HOOK_PATH" "$INSTALL_DIR/bin/agentbridge"

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
shutil.copy2(settings_path, settings_path + ".bak-agentbridge")
hooks = settings.setdefault("hooks", {})
for event, entries in snippet["hooks"].items():
    hooks.setdefault(event, [])
    for entry in entries:
        if entry not in hooks[event]:
            hooks[event].append(entry)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print("    merged into ~/.claude/settings.json (backup: settings.json.bak-agentbridge)")
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
with open(path, "w") as f:
    json.dump(hooks, f, indent=2)
print("    wrote ~/.codex/hooks.json (run /hooks in Codex to trust the new hooks)")
PYEOF

echo "==> Installing opencode plugin"
mkdir -p "$HOME/.config/opencode/plugins"
cp "$ROOT/plugin-opencode/agentbridge.js" "$HOME/.config/opencode/plugins/agentbridge.js"
echo "    copied to ~/.config/opencode/plugins/agentbridge.js"

echo
echo "Done. Next steps:"
echo "  1. Relaunch Pock, then drag 'Agent Status' into your Touch Bar via"
echo "     Customize Pock…"
echo "  2. In Codex, run /hooks and trust the AgentBridge hooks."
echo "  3. Restart Claude Code / Codex / opencode sessions."
echo "  4. Uninstall: ./uninstall.sh"
