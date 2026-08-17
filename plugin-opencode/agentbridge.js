// AgentBridge plugin for opencode: pushes agent activity to the local
// AgentBridge daemon so the Pock Touch Bar widget can display it.
//
// Status-only: opencode has no wired permission hook, so Touch Bar
// permission approval is not supported for opencode yet.

const url = process.env.AGENTBRIDGE_URL || "http://127.0.0.1:3939"

const throttleState = {}

async function post(payload) {
  payload.ts = Date.now() / 1000
  await fetch(`${url}/v1/event`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  }).catch(() => {})
}

async function throttled(key, payload, ms = 1200) {
  const now = Date.now()
  if (throttleState[key] && now - throttleState[key] < ms) return
  throttleState[key] = now
  await post(payload)
}

export const AgentBridge = async () => {
  return {
    // OpenCode's documented generic event subscription is the stable path
    // across server versions. Direct lifecycle keys remain below for older
    // runtimes.
    event: async ({ event }) => {
      const type = event?.type
      const props = event?.properties ?? {}
      if (type === "session.status") {
        const status = props.status?.type
        if (status === "busy") post({ agent: "opencode", event: "thinking" })
        else if (status === "idle") post({ agent: "opencode", event: "ready" })
      } else if (type === "session.idle") {
        post({ agent: "opencode", event: "ready" })
      } else if (type === "session.created") {
        post({ agent: "opencode", event: "session_start" })
      } else if (type === "session.error") {
        post({ agent: "opencode", event: "stop" })
      } else if (type === "file.edited") {
        post({ agent: "opencode", event: "tool_start", tool: "edit", detail: props.file ?? "" })
      } else if (type === "command.executed") {
        post({ agent: "opencode", event: "tool_start", tool: "bash", detail: props.arguments ?? props.name ?? "" })
      } else if (type === "message.part.updated") {
        const part = props.part
        if (part?.type === "text") {
          if (props.delta || !part.time?.completed) post({ agent: "opencode", event: "answering" })
          else post({ agent: "opencode", event: "answer_done" })
        } else if (part?.type === "reasoning") {
          post({ agent: "opencode", event: "thinking" })
        }
      }
    },
    "session.created": async () => {
      await post({ agent: "opencode", event: "session_start" })
    },
    "session.idle": async () => {
      await post({ agent: "opencode", event: "ready" })
    },
    "session.error": async () => {
      await post({ agent: "opencode", event: "stop" })
    },
    "tool.execute.before": async (input, output) => {
      const args = output?.args ?? input?.args ?? {}
      let detail = ""
      if (typeof args.command === "string") {
        detail = args.command.slice(0, 140)
      } else if (typeof args.filePath === "string") {
        detail = args.filePath.slice(0, 140)
      } else if (typeof args.pattern === "string") {
        detail = args.pattern.slice(0, 140)
      } else if (Object.keys(args).length > 0) {
        detail = JSON.stringify(args).slice(0, 140)
      }
      await post({
        agent: "opencode",
        event: "tool_start",
        tool: input?.tool ?? "tool",
        detail,
      })
    },
    "tool.execute.after": async () => {
      await post({ agent: "opencode", event: "thinking" })
    },
    "message.part.updated": async (input, output) => {
      const part = output?.part ?? input?.part
      if (!part) return
      if (part.type === "text" && !part.done) {
        await throttled("answering", { agent: "opencode", event: "answering" })
      } else if (part.type === "text" && part.done) {
        await throttled("answer-done", { agent: "opencode", event: "answer_done" }, 3000)
      } else if (part.type === "reasoning") {
        await throttled("thinking", { agent: "opencode", event: "thinking" })
      }
    },
  }
}
