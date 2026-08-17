import Foundation
import AppKit

final class BridgeClient {

    struct AgentInfo: Codable {
        let agent: String
        let name: String
        let symbol: String
        let color: String
        let status: String
        let label: String
        let tool: String?
        let detail: String?
        let lastActive: Double
    }

    struct PermissionSuggestion: Codable {
        let label: String
        let entry: String
    }

    struct PermissionItem: Codable {
        let id: String
        let agent: String
        let tool: String
        let detail: String
        let cwd: String
        let suggestions: [PermissionSuggestion]
        let requestedAt: Double
    }

    struct BridgeState: Codable {
        let agents: [AgentInfo]
        let pending: [PermissionItem]
    }

    private let baseURL: URL
    private let session: URLSession

    init() {
        let env = ProcessInfo.processInfo.environment
        let urlString = env["AGENTBRIDGE_URL"] ?? "http://127.0.0.1:3939"
        baseURL = URL(string: urlString) ?? URL(string: "http://127.0.0.1:3939")!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 3.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func fetchState(completion: @escaping (BridgeState?) -> Void) {
        let url = baseURL.appendingPathComponent("/v1/state")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0
        session.dataTask(with: request) { data, response, error in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data else {
                completion(nil)
                return
            }
            let state = try? JSONDecoder().decode(BridgeState.self, from: data)
            completion(state)
        }.resume()
    }

    func sendDecision(id: String, decision: String, ruleIndex: Int?, completion: @escaping (Bool) -> Void) {
        let url = baseURL.appendingPathComponent("/v1/decision")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2.0
        var body: [String: Any] = ["id": id, "decision": decision]
        if let ruleIndex = ruleIndex {
            body["ruleIndex"] = ruleIndex
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            completion(ok)
        }.resume()
    }
}

// MARK: - Shared preferences

enum AgentPrefs {
    static let suiteName = "com.touchbar.agentstatus"
    static let changedNotification = Notification.Name("AgentTouchBarPreferencesChanged")

    static var defaults: UserDefaults {
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    static var widgetEnabled: Bool {
        if defaults.object(forKey: "widgetEnabled") == nil { return true }
        return defaults.bool(forKey: "widgetEnabled")
    }

    static func isAgentEnabled(_ id: String) -> Bool {
        let dict = defaults.dictionary(forKey: "enabledAgents")
        if let dict = dict, let enabled = dict[id] as? Bool {
            return enabled
        }
        return true
    }

    static var shimmerEnabled: Bool {
        if defaults.object(forKey: "shimmerEnabled") == nil { return true }
        return defaults.bool(forKey: "shimmerEnabled")
    }

    static var permissionButtonsEnabled: Bool {
        if defaults.object(forKey: "permissionButtonsEnabled") == nil { return true }
        return defaults.bool(forKey: "permissionButtonsEnabled")
    }

    /// always: full ready state, compact: 36pt logo while idle,
    /// active: near-hidden 18pt anchor while idle (keeps Pock expandable).
    static var visibilityMode: String {
        if let mode = defaults.string(forKey: "visibilityMode") { return mode }
        // Migrate the previous boolean preference.
        return showOnlyWhileActive ? "compact" : "always"
    }

    static var hasEnabledAgents: Bool {
        return ["claude", "codex", "opencode"].contains { isAgentEnabled($0) }
    }

    static var showOnlyWhileActive: Bool {
        if defaults.object(forKey: "showOnlyWhileActive") == nil { return false }
        return defaults.bool(forKey: "showOnlyWhileActive")
    }

    /// `hidden` returns the Touch Bar space to neighboring items; `icon`
    /// keeps a compact 36pt neutral indicator while agents are idle.
    static var idlePresentation: String {
        return defaults.string(forKey: "idlePresentation") ?? "hidden"
    }
}

// MARK: - Color helper

extension NSColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
