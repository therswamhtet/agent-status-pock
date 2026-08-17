# Agent Status — ready-to-use bundle

No compiler needed. Everything is prebuilt: Pock widgets, the AgentBridge
daemon (universal arm64 + x86_64), and the agent hooks.

## Requirements

- macOS 15+ on a **Touch Bar MacBook Pro**
- [Pock](https://pock.app) 0.9.0-22 or later
- Python 3 (ships with macOS)
- At least one of: **Claude Code**, **Codex CLI**, **opencode**

## Install

```bash
chmod +x install.sh uninstall.sh
./install.sh
```

Then:

1. **Relaunch Pock** (menu bar icon → Relaunch), open **Customize Pock…** and
   drag **Agent Status** into your Touch Bar.
2. In **Codex**, run `/hooks` and trust the AgentBridge hooks (Codex requires
   this for non-managed hooks).
3. **Restart** your agent sessions.

That's it. The bridge starts automatically at login and the widget starts
polling it the moment you add it to the Touch Bar.

## Quick checks

- Is the bridge up? `curl -s localhost:3939/v1/health` → `{"ok":true}`
- Logs: `~/.agentbridge/logs/stderr.log`
- Uninstall: `./uninstall.sh`

## Troubleshooting

- **Widget missing from Customize Pock…** — relaunch Pock after installing.
- **No status updates** — the bridge is down or the widget isn't in the bar.
  Re-run `./install.sh` and add the widget again.
- **Codex hooks don't run** — run `/hooks` inside Codex and trust them once.

The **VoiceInkDictation.pock** widget is optional: it adds a dedicated
microphone key that emits virtual F19 for the VoiceInk dictation app.
