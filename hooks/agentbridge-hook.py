#!/usr/bin/env python3
"""AgentBridge hook for Claude Code and Codex.

Reads the hook JSON on stdin and forwards activity events to the local
AgentBridge daemon (fire-and-forget, never blocks the agent).

Usage: agentbridge-hook.py <claude|codex>
"""

import json
import os
import time
import sys
import urllib.request

BRIDGE = os.environ.get("AGENTBRIDGE_URL", "http://127.0.0.1:3939")


def post_json(url, payload, timeout=1.0):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode() or "{}")
    except Exception:
        return None


def stamp(payload):
    payload["ts"] = time.time_ns() / 1e9
    return payload


def fire_and_forget(raw_payload):
    payload = stamp(raw_payload)
    post_json(BRIDGE + "/v1/event", payload, timeout=0.25)


def summarize(tool_name, tool_input):
    if not isinstance(tool_input, dict):
        return None
    parts = []
    for key in ("command", "file_path", "pattern", "query", "description",
                "prompt", "path", "url", "subagent_type", "agent_type"):
        value = tool_input.get(key)
        if isinstance(value, str) and value.strip():
            parts.append(value)
    text = " | ".join(parts) if parts else json.dumps(tool_input)
    return text[:140]


def main():
    agent = sys.argv[1] if len(sys.argv) > 1 else "claude"
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    event = data.get("hook_event_name", "")
    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    if event == "PreToolUse":
        if tool_name == "AskUserQuestion":
            fire_and_forget({"agent": agent, "event": "needs_input",
                             "detail": "Agent is asking a question"})
        else:
            fire_and_forget({
                "agent": agent,
                "event": "tool_start",
                "tool": tool_name,
                "detail": summarize(tool_name, tool_input),
            })
    elif event == "MessageDisplay":
        fire_and_forget({"agent": agent, "event": "answering"})
    elif event in ("PostToolUse", "PostToolUseFailure", "UserPromptSubmit",
                   "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"):
        fire_and_forget({"agent": agent, "event": "thinking"})
    elif event == "SessionStart":
        fire_and_forget({"agent": agent, "event": "session_start"})
    elif event in ("Stop", "StopFailure"):
        fire_and_forget({"agent": agent, "event": "stop"})
    elif event == "SessionEnd":
        fire_and_forget({"agent": agent, "event": "session_end"})
    elif event == "Notification":
        notification_type = (data.get("notification_type") or data.get("message") or "").lower()
        if "input" in notification_type or "question" in notification_type:
            fire_and_forget({"agent": agent, "event": "needs_input",
                             "detail": "Agent is asking a question"})
        elif "idle" in notification_type or "completed" in notification_type:
            fire_and_forget({"agent": agent, "event": "ready"})
        else:
            fire_and_forget({"agent": agent, "event": "notification",
                             "detail": (data.get("message") or notification_type)[:120]})


if __name__ == "__main__":
    main()