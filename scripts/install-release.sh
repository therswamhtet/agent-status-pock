#!/bin/bash
# Installs the ready-to-use Agent Status bundle: bridge daemon + LaunchAgent +
# Pock widgets + agent hooks (Claude Code, Codex, opencode).
# No compiler required, everything is prebuilt.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.agentbridge"
HOOK_PATH="$INSTALL_DIR/hooks/agentbridge-hook.py"

echo "==> Installing bridge to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/hooks" "$INSTALL_DIR/logs"
cp "$ROOT/bin/agentbridge" "$INSTALL_DIR/bin/agentbridge"
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

echo "==> Installing Pock widgets"
mkdir -p "$HOME/Library/Application Support/Pock/Widgets"
cp -R "$ROOT/AgentTouchBar.pock" "$HOME/Library/Application Support/Pock/Widgets/"
cp -R "$ROOT/VoiceInkDictation.pock" "$HOME/Library/Application Support/Pock/Widgets/"
echo "    AgentTouchBar.pock + VoiceInkDictation.pock copied"

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
echo "  1. Relaunch Pock, then drag 'Agent Status' and/or 'VoiceInk Dictation'"
echo "     into your Touch Bar via Customize Pock…"
echo "  2. Open VoiceInk's Primary Shortcut recorder, then tap the microphone button."
echo "     VoiceInk will register the dedicated button as F19; use Toggle or Hybrid mode."
echo "  3. In Codex, run /hooks and trust the AgentBridge hooks."
echo "  4. Restart Claude Code / Codex / opencode sessions."
echo "  5. Uninstall: ./uninstall.sh"
