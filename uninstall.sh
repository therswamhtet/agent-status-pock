#!/bin/bash
# Removes Agent Touch Bar: LaunchAgent, bridge files, widget, and agent hook
# entries added by install.sh (Claude Code / Codex / opencode).
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.touchbar.agentbridge.plist"

echo "==> Stopping AgentBridge"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "==> Removing Pock widget"
rm -rf "$HOME/Library/Application Support/Pock/Widgets/AgentTouchBar.pock"

echo "==> Removing opencode plugin"
OPENCODE_PLUGIN="$HOME/.config/opencode/plugins/agentbridge.js"
rm -f "$OPENCODE_PLUGIN"
if [[ -f "$OPENCODE_PLUGIN.bak-agentbridge" ]]; then
    mv "$OPENCODE_PLUGIN.bak-agentbridge" "$OPENCODE_PLUGIN"
    echo "    restored the previous opencode plugin"
fi

echo "==> Removing Claude Code hooks"
python3 - "$HOME/.claude/settings.json" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)
with open(path) as f:
    settings = json.load(f)
hooks = settings.get("hooks", {})
for event in list(hooks.keys()):
    hooks[event] = [e for e in hooks[event]
                    if "agentbridge-hook.py" not in json.dumps(e)]
    if not hooks[event]:
        del hooks[event]
if not hooks:
    settings.pop("hooks", None)
temp_path = path + ".tmp-agentbridge"
with open(temp_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(temp_path, path)
os.remove(path + ".bak-agentbridge") if os.path.exists(path + ".bak-agentbridge") else None
print("    removed AgentBridge hook entries")
PYEOF

echo "==> Removing Codex hooks"
python3 - "$HOME/.codex/hooks.json" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)
with open(path) as f:
    document = json.load(f)
hooks = document.get("hooks", {})
for event in list(hooks):
    hooks[event] = [e for e in hooks[event]
                    if "agentbridge-hook.py" not in json.dumps(e)]
    if not hooks[event]:
        del hooks[event]
if not hooks and set(document) == {"hooks"}:
    os.remove(path)
    print("    removed ~/.codex/hooks.json")
else:
    if not hooks:
        document.pop("hooks", None)
    temp_path = path + ".tmp-agentbridge"
    with open(temp_path, "w") as f:
        json.dump(document, f, indent=2)
        f.write("\n")
    os.replace(temp_path, path)
    print("    removed AgentBridge hook entries")
PYEOF

echo "==> Removing bridge files"
rm -rf "$HOME/.agentbridge"

echo "Done."
