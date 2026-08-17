#!/usr/bin/env python3
"""AgentBridge hook for Claude Code and Codex.

Reads the hook JSON on stdin and forwards activity events to the local
AgentBridge daemon (fire-and-forget, never blocks the agent). For
PermissionRequest events it blocks until the user answers on the Touch Bar;
if the bridge is unreachable or times out, it falls back to the agent's own
permission prompt.

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
    # Local synchronous delivery preserves lifecycle ordering: PreToolUse
    # must reach the bridge before PostToolUse. localhost normally responds
    # in a few milliseconds; bridge-down fallback is capped at 250ms.
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
    cwd = data.get("cwd", "")
    session_id = data.get("session_id", "")
    permission_mode = data.get("permission_mode", "default")

    if event == "PermissionRequest":
        # Respect Codex's built-in approval mode. "Approve for me" reaches
        # hooks as dontAsk/bypassPermissions; acceptEdits only auto-approves
        # edit/write tools and still asks for shell/network escalation.
        codex_auto = agent == "codex" and permission_mode in (
            "dontAsk", "bypassPermissions"
        )
        codex_auto_edit = (
            agent == "codex"
            and permission_mode == "acceptEdits"
            and tool_name.lower() in ("edit", "write", "apply_patch", "patch")
        )
        if codex_auto or codex_auto_edit:
            print(json.dumps({
                "hook_specific_output": {
                    "hook_event_name": "PermissionRequest",
                    "decision": {"behavior": "allow"},
                }
            }))
            return

        # Questions asked via AskUserQuestion are harmless (they open the
        # question UI in the terminal) — auto-approve and show the answer
        # options as numbered buttons on the Touch Bar.
        if tool_name == "AskUserQuestion":
            options = []
            try:
                qs = tool_input.get("questions", [])
                if qs:
                    for opt in qs[0].get("options", [])[:4]:
                        if isinstance(opt, dict):
                            label = str(opt.get("label", opt.get("text", "")))
                        elif isinstance(opt, str):
                            label = opt
                        else:
                            continue
                        label = label.strip()
                        if label:
                            options.append(label[:40])
            except Exception:
                pass
            fire_and_forget({
                "agent": agent,
                "event": "needs_input",
                "detail": "Asking a question",
                "options": options,
            })
            if agent == "codex":
                print(json.dumps({
                    "hook_specific_output": {
                        "hook_event_name": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }))
            else:
                print(json.dumps({
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }))
            return

        # Turn permission_suggestions into numbered Touch Bar buttons. Picking
        # one echoes the entry back as updatedPermissions (= "don't ask again").
        suggestions = []
        raw_suggestions = data.get("permission_suggestions")
        if isinstance(raw_suggestions, list):
            for item in raw_suggestions[:3]:
                if isinstance(item, dict) and item.get("type") == "addRules":
                    rules = item.get("rules") or []
                    rule_text = ""
                    for rule in rules:
                        if isinstance(rule, dict):
                            rule_text = rule.get("ruleContent") or rule.get("toolName") or ""
                            if rule_text:
                                break
                    label = "Always allow" + (f" · {rule_text[:24]}" if rule_text else "")
                    suggestions.append({"label": label[:40], "entry": item})
                elif isinstance(item, dict):
                    suggestions.append({"label": "Always allow", "entry": item})

        payload = stamp({
            "agent": agent,
            "tool": tool_name,
            "detail": summarize(tool_name, tool_input) or tool_name,
            "cwd": cwd,
            "session": session_id,
            "suggestions": suggestions,
        })
        response = post_json(BRIDGE + "/v1/permission", payload, timeout=75) or {}
        decision = response.get("decision", "ask")

        if decision in ("allow", "deny"):
            decision_obj = {"behavior": decision}
            if decision == "allow" and response.get("updatedPermissions"):
                decision_obj["updatedPermissions"] = response["updatedPermissions"]
            if decision == "deny":
                decision_obj["message"] = "Denied on Touch Bar"
            if agent == "codex":
                print(json.dumps({
                    "hook_specific_output": {
                        "hook_event_name": "PermissionRequest",
                        "decision": decision_obj,
                    }
                }))
            else:
                print(json.dumps({
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": decision_obj,
                    }
                }))
        # No output → the agent shows its own approval prompt (timeout /
        # bridge down fallback).
        return

    # Activity events: fire-and-forget, never block the agent loop.
    if event == "PreToolUse":
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
        if "permission" in notification_type:
            fire_and_forget({"agent": agent, "event": "permission_pending", "tool": tool_name})
        elif "input" in notification_type or "question" in notification_type:
            fire_and_forget({"agent": agent, "event": "needs_input",
                             "detail": (data.get("message") or "")[:120]})
        elif "idle" in notification_type or "completed" in notification_type:
            fire_and_forget({"agent": agent, "event": "ready"})
        else:
            fire_and_forget({"agent": agent, "event": "notification",
                             "detail": (data.get("message") or notification_type)[:120]})


if __name__ == "__main__":
    main()
