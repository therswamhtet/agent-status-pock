# Agent Status, ready-to-use bundle

**One Touch Bar. Three AI coding agents: Claude Code, Codex CLI, and OpenCode.**

Everything is prebuilt. No compiler needed. This zip contains the Pock widget,
the AgentBridge daemon (universal arm64 + x86_64) and the agent hooks.

## Requirements

- macOS 15 or newer on a MacBook Pro with a Touch Bar
- Pock 0.9.0-22 or later
- Python 3 (from Xcode Command Line Tools or python.org)
- At least one of: Claude Code, Codex CLI, OpenCode

## Install

```bash
chmod +x install.sh uninstall.sh
./install.sh
```

Then:

1. Relaunch Pock (menu bar icon, Relaunch), open Customize Pock and drag
   **Agent Status** into your Touch Bar.
2. Restart your Claude Code, Codex CLI, or OpenCode sessions.

That is it. The bridge starts automatically at login, and the widget starts
polling it as soon as you add it to the Touch Bar.

## Quick checks

- Is the bridge up? `curl -s localhost:3939/v1/health` should return
  `{"ok":true}`
- Logs: `~/.agentbridge/logs/stderr.log`
- Uninstall: `./uninstall.sh`

## Troubleshooting

- **Widget missing from Customize Pock.** Relaunch Pock after installing.
- **No status updates.** The bridge is down or the widget is not in the bar.
  Re-run `./install.sh` and add the widget again.
- **Codex hooks do not run.** Run `/hooks` inside Codex and trust them once.
