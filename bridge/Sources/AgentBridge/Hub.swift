import Foundation

// MARK: - Model

enum AgentID: String, Codable, CaseIterable {
    case claude
    case codex
    case opencode

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "bolt.fill"
        case .opencode: return "terminal.fill"
        }
    }

    /// Brand color (hex RRGGBB).
    var color: String {
        switch self {
        case .claude: return "D97757"   // Claude clay
        case .codex: return "10A37F"    // OpenAI teal
        case .opencode: return "8B5CF6" // opencode violet
        }
    }
}

enum AgentStatus: String, Codable {
    case idle              // no session ever seen
    case ready             // session open, nothing happening
    case connected         // transient: session just started
    case thinking
    case answering
    case working
    case needsInput
    case responseReady     // transient: answer just finished
}

struct AgentSnapshot: Codable {
    let agent: AgentID
    let name: String
    let symbol: String
    let color: String
    var status: AgentStatus
    var label: String
    var tool: String?
    var detail: String?
    var lastActive: TimeInterval
    var transientUntil: TimeInterval?
}

struct BridgeState: Codable {
    let agents: [AgentSnapshot]
}

// MARK: - Activity hub

final class AgentHub: @unchecked Sendable {

    private let lock = NSLock()
    private var statuses: [AgentID: AgentSnapshot] = [:]
    // Per-agent ordering + display-dwell bookkeeping.
    private var lastEventAt: [AgentID: Double] = [:]
    private var labelSetAt: [AgentID: Double] = [:]
    private var heldEvent: [AgentID: HeldEvent] = [:]
    /// A tool state stays on the bar at least this long before a quieter
    /// state (thinking/answering/stop) may replace it.
    private let toolDisplayDwell: Double = 1.2
    /// Events older than the newest applied one (minus tolerance) are stale.
    private let staleTolerance: Double = 0.05

    private struct HeldEvent {
        let event: String
        let tool: String?
        let detail: String?
        let ts: Double
    }

    init() {
        for agent in AgentID.allCases {
            statuses[agent] = AgentSnapshot(
                agent: agent,
                name: agent.displayName,
                symbol: agent.symbol,
                color: agent.color,
                status: .idle,
                label: "No agent running",
                tool: nil,
                detail: nil,
                lastActive: 0,
                transientUntil: nil
            )
        }
    }

    // MARK: Preferences

    private var enabledAgents: [AgentID: Bool] {
        let defaults = UserDefaults(suiteName: "com.touchbar.agentstatus")
        guard let dict = defaults?.dictionary(forKey: "enabledAgents") else {
            return [.claude: true, .codex: true, .opencode: true]
        }
        var result: [AgentID: Bool] = [.claude: true, .codex: true, .opencode: true]
        for (key, value) in dict {
            if let agent = AgentID(rawValue: key), let enabled = value as? Bool {
                result[agent] = enabled
            }
        }
        return result
    }

    private func isEnabled(_ agent: AgentID) -> Bool {
        let defaults = UserDefaults(suiteName: "com.touchbar.agentstatus")
        if defaults?.object(forKey: "widgetEnabled") != nil,
           defaults?.bool(forKey: "widgetEnabled") == false {
            return false
        }
        return enabledAgents[agent] ?? true
    }

    private func log(_ message: String) {
        let logDir = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent(".agentbridge/logs")
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let path = (logDir as NSString).appendingPathComponent("events.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Events

    func record(event: String, agent: AgentID, tool: String?, detail: String?, ts: Double?) {
        lock.lock()

        guard isEnabled(agent) else {
            lock.unlock()
            log("[bridge] dropped event '\(event)' from disabled agent \(agent.rawValue)")
            return
        }

        // Out-of-order protection: detached hook processes race each other,
        // so a PostToolUse "thinking" can arrive before its PreToolUse
        // "tool_start". Drop anything older than what we already applied.
        let eventTime = ts ?? Date().timeIntervalSince1970
        if let last = lastEventAt[agent], eventTime < last - staleTolerance {
            lock.unlock()
            log("[\(agent.rawValue)] dropped stale event '\(event)'")
            return
        }
        lastEventAt[agent] = eventTime

        // Display dwell: keep an active tool state visible for at least
        // `toolDisplayDwell` before a quieter state replaces it, so fast
        // tools (Read/Edit in <300ms) don't flick by unseen.
        let now = Date().timeIntervalSince1970
        if let current = statuses[agent],
           current.status == .working,
           isQuietTransition(event),
           let setAt = labelSetAt[agent], now - setAt < toolDisplayDwell {
            let shouldSchedule = heldEvent[agent] == nil
            heldEvent[agent] = HeldEvent(event: event, tool: tool, detail: detail, ts: eventTime)
            let wait = toolDisplayDwell - (now - setAt)
            lock.unlock()
            log("[\(agent.rawValue)] holding '\(event)' for \(String(format: "%.2f", wait))s (tool dwell)")
            if shouldSchedule {
                DispatchQueue.global().asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.applyHeldEvent(for: agent)
                }
            }
            return
        }

        // Immediate/high-priority activity invalidates a held quiet state.
        if !isQuietTransition(event) {
            heldEvent[agent] = nil
        }
        apply(event: event, agent: agent, tool: tool, detail: detail, eventTime: eventTime)
        lock.unlock()
    }

    private func applyHeldEvent(for agent: AgentID) {
        lock.lock()
        defer { lock.unlock() }
        guard let held = heldEvent[agent] else { return }
        if let last = lastEventAt[agent], held.ts < last - staleTolerance { return }
        heldEvent[agent] = nil
        apply(event: held.event, agent: agent, tool: held.tool, detail: held.detail, eventTime: held.ts)
    }

    private func isQuietTransition(_ event: String) -> Bool {
        return ["thinking", "answering", "stop", "session_end", "answer_done", "ready", "idle", "notification"]
            .contains(event)
    }

    private func apply(event: String, agent: AgentID, tool: String?, detail: String?, eventTime: Double) {
        var status = statuses[agent] ?? AgentSnapshot(
            agent: agent, name: agent.displayName, symbol: agent.symbol, color: agent.color,
            status: .idle, label: "No agent running", tool: nil, detail: nil, lastActive: 0, transientUntil: nil
        )
        let now = Date().timeIntervalSince1970
        status.lastActive = now

        // Keep needsInput sticky: while a question is on the Touch Bar,
        // thinking/notification events must not overwrite it. Only a real
        // state change (tool_start, answering, stop, ready, session_start,
        // or a new needs_input) clears it.
        if status.status == .needsInput,
           ["thinking", "notification", "connected"].contains(event) {
            statuses[agent] = status
            return
        }

        switch event {
        case "session_start":
            status.status = .connected
            status.label = "\(agent.displayName) connected"
            status.tool = nil
            status.detail = nil
            status.transientUntil = now + 3

        case "thinking":
            status.status = .thinking
            status.label = "Thinking"
            status.tool = nil
            status.detail = detail
            status.transientUntil = nil

        case "answering":
            status.status = .answering
            status.label = "Writing the answer"
            status.tool = nil
            status.detail = nil
            status.transientUntil = nil

        case "tool_start":
            status.status = .working
            let toolName = tool ?? "tool"
            status.tool = toolName
            status.label = verb(for: toolName)
            status.detail = summarizedTarget(toolName: toolName, detail: detail)
            status.transientUntil = nil

        case "needs_input":
            status.status = .needsInput
            status.label = detail ?? "Needs your answer"
            status.tool = nil
            status.detail = nil
            status.transientUntil = nil

        case "ready", "idle":
            status.status = .ready
            status.label = "\(agent.displayName) is ready"
            status.tool = nil
            status.detail = nil
            status.transientUntil = nil

        case "stop", "session_end", "answer_done":
            status.status = .responseReady
            status.label = "Response ready"
            status.tool = nil
            status.detail = nil
            status.transientUntil = now + 6

        case "notification":
            if status.status == .idle || status.status == .ready {
                status.status = .ready
                status.label = detail ?? "\(agent.displayName) is ready"
            }
            status.transientUntil = nil

        default:
            break
        }

        // Track when this label started displaying (for the tool dwell).
        if let previous = statuses[agent], previous.label != status.label || previous.status != status.status {
            labelSetAt[agent] = Date().timeIntervalSince1970
        } else if labelSetAt[agent] == nil {
            labelSetAt[agent] = Date().timeIntervalSince1970
        }
        statuses[agent] = status
        log("[\(agent.rawValue)] \(event) tool=\(tool ?? "-") detail=\((detail ?? "-").prefix(60))")
    }

    func snapshot() -> BridgeState {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        let agents = AgentID.allCases
            .compactMap { statuses[$0] }
            .filter { isEnabled($0.agent) }
            .map { snapshot -> AgentSnapshot in
                var s = snapshot
                if let until = s.transientUntil, until < now {
                    s.transientUntil = nil
                    switch s.status {
                    case .connected:
                        s.status = .ready
                        s.label = "\(s.name) is ready"
                    case .responseReady:
                        s.status = .ready
                        s.label = "\(s.name) is ready"
                    case .ready:
                        s.label = "\(s.name) is ready"
                    default:
                        break
                    }
                }
                // Inactivity timeout: if the agent is stuck in an active
                // state (thinking/answering/working) with no events for 45s,
                // it probably finished without sending Stop. Fall back to
                // ready so the bar doesn't freeze on "Thinking".
                if s.status == .thinking || s.status == .answering || s.status == .working,
                   now - s.lastActive > 45 {
                    s.status = .ready
                    s.label = "\(s.name) is ready"
                    s.tool = nil
                    s.detail = nil
                    s.transientUntil = nil
                }
                return s
            }
            .sorted { $0.lastActive > $1.lastActive }
        return BridgeState(agents: agents)
    }

    // MARK: Label composition

    private func verb(for tool: String) -> String {
        let lower = tool.lowercased()
        switch lower {
        case let t where t.contains("edit") || t.contains("write") || t.contains("patch"):
            return "Editing"
        case let t where t.contains("read") || t.contains("view") || t.contains("cat "):
            return "Reading"
        case let t where t.contains("grep") || t.contains("search") || t.contains("find") || t.contains("glob"):
            return "Searching"
        case let t where t.contains("bash") || t.contains("shell") || t.contains("exec") || t.contains("run"):
            return "Running"
        case let t where t.contains("fetch") || t.contains("web") || t.contains("browse") || t.contains("curl"):
            return "Browsing"
        case let t where t.contains("task") || t.contains("delegate") || t.contains("subagent"):
            return "Delegating"
        case let t where t.contains("ask") || t.contains("question"):
            return "Asking"
        case let t where t.contains("todo") || t.contains("plan"):
            return "Planning"
        case let t where t.contains("test") || t.contains("lint") || t.contains("build") || t.contains("install"):
            return "Testing"
        default:
            return tool.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Short, human target for the current action: file basename, command
    /// head, or search pattern.
    private func summarizedTarget(toolName: String, detail: String?) -> String {
        guard var detail = detail, !detail.isEmpty else { return "" }
        detail = detail.split(separator: "|").first.map(String.init) ?? detail
        detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.hasPrefix("/") { // file path → basename
            detail = (detail as NSString).lastPathComponent
        }
        if detail.hasPrefix("{") { return "" }
        return String(detail.prefix(48))
    }
}