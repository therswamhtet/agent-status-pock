#!/bin/bash
# Removes Agent Touch Bar: LaunchAgent, bridge files, widget, and agent hook
# entries added by install.sh (Claude Code / Codex / opencode).
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.touchbar.agentbridge.plist"

echo "==> Stopping AgentBridge"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true

echo "==> Removing bridge files"
rm -rf "$HOME/.agentbridge"

echo "==> Removing Pock widget"
rm -rf "$HOME/Library/Application Support/Pock/Widgets/AgentTouchBar.pock"

echo "==> Removing opencode plugin"
rm -f "$HOME/.config/opencode/plugins/agentbridge.js"

echo "==> Removing Claude Code hooks (restoring backup if present)"
python3 - "$HOME/.claude/settings.json" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)
backup = path + ".bak-agentbridge"
if os.path.exists(backup):
    import shutil
    shutil.move(backup, path)
    print("    restored", backup)
else:
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
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
    print("    removed AgentBridge hook entries")
PYEOF

echo "==> Removing Codex hooks"
python3 - "$HOME/.codex/hooks.json" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)
with open(path) as f:
    hooks = json.load(f)
for event in list(hooks.keys()):
    hooks[event] = [e for e in hooks[event]
                    if "agentbridge-hook.py" not in json.dumps(e)]
    if not hooks[event]:
        del hooks[event]
if not hooks:
    os.remove(path)
    print("    removed ~/.codex/hooks.json")
else:
    with open(path, "w") as f:
        json.dump(hooks, f, indent=2)
    print("    removed AgentBridge hook entries")
PYEOF

echo "Done."
