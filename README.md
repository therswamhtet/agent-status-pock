# Agent Status — Pock

> Live status and tap-to-approve permissions for your coding agents, right on
> the MacBook **Touch Bar**.

Turn the Touch Bar into a real-time cockpit for **Claude Code**, **Codex CLI**
and **opencode**. See exactly what your agent is doing — thinking, answering,
editing, running shell commands — and approve permission requests with a tap,
without ever leaving your keyboard.

![Working](docs/screenshots/render-working.png)
![Permission allow](docs/screenshots/render-panel-allow.png)
![Permission suggestions](docs/screenshots/render-panel-suggestions.png)
![Answering](docs/screenshots/render-answering.png)
![Ready](docs/screenshots/render-ready.png)

## Highlights

- **Live agent status** — `Thinking…`, `Answering…`, `Editing code`,
  `Reading`, `Searching`, `Executing shell` with a shimmering sweep. Idle
  agents pulse "ready"; finished answers flash **Response ready**.
- **Permission approval by tap** — permission prompts appear on the Touch Bar
  as a **Deny** (red) / **Allow** (green) bar, or numbered buttons (1/2/3)
  for the agent's suggested answers. Unanswered requests fall back to the
  agent's own prompt after 60 seconds.
- **Multi-agent, brand-colored** — Claude clay, Codex teal, opencode violet.
  The bar follows the most recently active agent; tap to cycle between them.
- **Zero-dependency widget** — the `.pock` bundle loads in *any* Pock version
  (dynamically resolved symbols, no linked PockKit).
- **Bonus: VoiceInk dictation key** — a dedicated microphone button that emits
  virtual **F19**, a key that doesn't exist on Touch Bar MacBook keyboards.
- **Universal binaries** — arm64 + x86_64, macOS 15+.

## Requirements

- macOS 15+ on a **Touch Bar MacBook Pro**
- [Pock](https://pock.app) 0.9.0-22 or later
- At least one of: **Claude Code**, **Codex CLI**, **opencode**
- To install the *source* build: Xcode Command Line Tools + Python 3

## Install (recommended — no compiler needed)

Grab the latest **ready-to-use** bundle from the
[Releases page](https://github.com/therswamhtet/agent-status-pock/releases)
(`agent-status-pock-<version>-ready.zip`). It ships prebuilt `.pock`
widgets, the AgentBridge daemon, agent hooks and an installer:

```bash
unzip agent-status-pock-2.2.0-ready.zip
cd agent-status-pock-2.2.0
chmod +x install.sh uninstall.sh
./install.sh
```

Then:

1. **Relaunch Pock** (menu bar icon → Relaunch), open **Customize Pock…** and
   drag **Agent Status** into your Touch Bar.
2. In **Codex**, run `/hooks` and trust the AgentBridge hooks (required for
   non-managed hooks).
3. **Restart** your agent sessions.

> Why not just the `.pock`? The widget itself has no agent connection — it
> polls the local **AgentBridge** daemon (`localhost:3939`), which aggregates
> status and holds permission requests. The bundle installs everything at once.

## Install from source

```bash
git clone https://github.com/therswamhtet/agent-status-pock.git
cd agent-status-pock
./install.sh
```

The source installer builds the bridge and widgets locally, then follows the
same steps above. See **Development** for build targets.

## How it works

```
┌──────────────┐   hooks (JSON stdin/stdout)   ┌───────────────┐
│ Claude Code  │ ────────────────────────────► │               │
│ Codex        │ ────────────────────────────► │  AgentBridge  │
│ opencode     │ ── plugin (HTTP POST) ──────► │  localhost    │
└──────────────┘                               │  :3939        │
                                               └───────┬───────┘
                                                       │ HTTP polling (300 ms)
                                               ┌───────▼───────┐
                                               │  Pock widget  │
                                               │ AgentTouchBar │
                                               └───────────────┘
```

1. **AgentBridge** — a tiny local daemon (`~/.agentbridge/bin/agentbridge`,
   LaunchAgent). Aggregates per-agent status and holds permission requests
   (60s timeout → fall back to the agent's own prompt).
2. **Agent hooks / plugins** — one shared Python hook for Claude Code and
   Codex; a JS plugin for opencode. They push activity events and block on
   permission requests until you tap the Touch Bar.
3. **Pock widget** (`AgentTouchBar.pock`) — polls the bridge, renders the
   shimmering status view, and presents the system-modal permission bar.

### What each agent reports

| Event | Claude Code | Codex | opencode |
|---|---|---|---|
| Tool activity (`Editing`, `Executing`…) | `PreToolUse` | `PreToolUse` | `tool.execute.before` |
| Thinking | `UserPromptSubmit` / `PostToolUse` | same | `message.part.updated` |
| Idle | `Stop` / `SessionEnd` | same | `session.idle` |
| Permission tap | `PermissionRequest` (allow/deny/ask JSON) | `PermissionRequest` (allow/deny JSON) | not supported yet |

## Usage

- **Status** — watch the bar while your agent works. Shimmering text = active;
  breathing icon = idle, waiting for you.
- **Permission** — when the bar switches to a full-width Deny/Allow prompt,
  tap **Allow** or **Deny**. Multiple pending requests are served in order.
- **Cycle agents** — tap the status area to cycle through recently active
  agents (works in cursor mode too).
- **VoiceInk dictation** — tap the microphone button to start/stop VoiceInk.
  It always emits its dedicated virtual F19; it does not mirror any shortcut.
  If macOS blocks synthetic keys, allow Pock under System Settings → Privacy
  & Security → Accessibility.

### Configuration

The bridge reads these env vars (set in the LaunchAgent plist):

| Variable | Default | Purpose |
|---|---|---|
| `AGENTBRIDGE_URL` | `http://127.0.0.1:3939` | Bridge endpoint (hook, plugin, widget) |
| `AGENTBRIDGE_PORT` | `3939` | Bridge listen port |
| `AGENTBRIDGE_TIMEOUT` | `60` | Seconds before an unanswered permission request falls back to the agent's own prompt |

Widget preferences live in Pock → Manage Widgets → **Agent Status**
(toggle agents, toggle the shimmer animation).

## Development

```bash
make bridge    # build AgentBridge (bridge/.build/release/AgentBridge)
make widget    # build dist/AgentTouchBar.pock
make test      # bridge curl tests + widget smoke test + render test
make install   # install everything
```

Widget layout: `widget/Sources/` (plain Swift, no Xcode project — `swiftc`
build). PockKit is vendored under `widget/Vendor/PockKit/` (MIT, from
[github.com/pock/pockkit](https://github.com/pock/pockkit)) and used at
compile time only: the bundle is linked with `-undefined dynamic_lookup`, so
it has **zero PockKit symbol dependencies** and loads in any Pock version.

The render test (`widget/tests/render.swift`) draws every UI state into
`widget/dist/render-*.png` (also mirrored in `docs/screenshots/`) so you can
eyeball the visuals without a Touch Bar.

### Releasing

```bash
./scripts/make-release.sh
```

Builds a universal bridge + widgets and packages
`.release/agent-status-pock-<version>-ready.zip` — the ready-to-use bundle.

## Troubleshooting

- **Widget missing from Customize Pock…** — make sure `AgentTouchBar.pock` is
  in `~/Library/Application Support/Pock/Widgets/` and relaunch Pock.
- **No status updates** — is the bridge up?
  `curl -s localhost:3939/v1/health` → `{"ok":true}`. Logs:
  `~/.agentbridge/logs/stderr.log`.
- **Permission prompts don't appear** — the hook falls back to the agent's own
  prompt when the bridge or Pock isn't running. Check bridge health and that
  the widget is placed in the Touch Bar.
- **Codex hooks don't run** — run `/hooks` inside Codex and trust them once.
- **Pock quirks on modern macOS** — after sleep/lock the default bar may
  reappear; relaunch Pock (see pock/pock issues).

## Uninstall

```bash
./uninstall.sh
```

## License

[MIT](LICENSE)