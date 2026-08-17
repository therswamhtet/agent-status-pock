import AppKit
import PockKit

/// Agent Status widget for Pock.
///
/// Shows live activity (thinking / editing / searching …) of coding agents
/// (Claude Code, Codex, OpenCode) with a shimmering status label, and takes
/// over the Touch Bar with Allow/Deny buttons when an agent requests
/// permission. Data comes from the local AgentBridge daemon.
public final class AgentTouchBarWidget: NSObject, PKWidget {

    // MARK: Protocol compatibility

    // New PockKit: deprecated static identifier (String).
    @available(*, deprecated, message: "Identifier is read from the bundle's Info.plist")
    public static var identifier: String = "com.touchbar.agentstatus"

    // Old PockKit (≤2021): instance identifier requirement.
    @objc public var identifier: NSTouchBarItem.Identifier = NSTouchBarItem.Identifier("com.touchbar.agentstatus")

    public var customizationLabel = "Agent Status"
    public var view: NSView!

    // Old PockKit declares imageForCustomization / prepareForCustomization /
    // lifecycle callbacks as CLASS members; newer PockKit declares them as
    // instance members. Implement both and forward the class forms to the
    // live instance so the widget works with every Pock release.
    private static weak var shared: AgentTouchBarWidget?

    @objc public static func viewWillAppear() { shared?.viewWillAppear() }
    @objc public static func viewDidAppear() { shared?.viewDidAppear() }
    @objc public static func viewWillDisappear() { shared?.viewWillDisappear() }
    @objc public static func viewDidDisappear() { shared?.viewDidDisappear() }
    @objc public static func prepareForCustomization() { shared?.prepareForCustomization() }
    @objc public static var imageForCustomization: NSImage { makeCustomizationImage() }

    // Instance forms (used by newer Pock releases).
    @objc public func viewDidAppear() {}
    @objc public func viewWillDisappear() {}
    @objc public func prepareForCustomization() {}
    @objc public var imageForCustomization: NSImage { Self.makeCustomizationImage() }

    private static func makeCustomizationImage() -> NSImage {
        let size = NSSize(width: 118, height: 30)
        return NSImage(size: size, flipped: false) { rect in
            if let icon = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white])) {
                icon.draw(in: NSRect(x: 10, y: (rect.height - 15) / 2, width: 15, height: 15))
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let text = "Agent Status" as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: 33, y: (rect.height - textSize.height) / 2), withAttributes: attrs)
            return true
        }
    }

    // MARK: State

    private let statusView: StatusView
    private let client = BridgeClient()
    private var pollTimer: Timer?
    private var isPolling = false
    private var answeredPermissionIDs: Set<String> = []

    override public required init() {
        statusView = StatusView(frame: NSRect(x: 0, y: 0, width: StatusView.preferredWidth, height: 30))
        super.init()
        view = statusView
        statusView.onTap = { [weak self] in
            self?.statusView.cycleSelection()
        }
        statusView.onDeny = { [weak self] item in
            self?.answer(item, decision: "deny", ruleIndex: nil)
        }
        statusView.onAllow = { [weak self] item in
            self?.answer(item, decision: "allow", ruleIndex: nil)
        }
        statusView.onSuggestion = { [weak self] item, index in
            // A numbered suggestion = "allow + remember" (the bridge echoes
            // the permission-update entry back to the agent).
            self?.answer(item, decision: "allow", ruleIndex: index)
        }
        AgentTouchBarWidget.shared = self
    }

    // MARK: Lifecycle

    @objc public func viewWillAppear() {
        startPolling()
    }

    @objc public func viewDidDisappear() {
        stopPolling()
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        poll()
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        client.fetchState { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isPolling = false
                if let state = state {
                    self.apply(state: state)
                }
            }
        }
    }

    private func apply(state: BridgeClient.BridgeState) {
        let pending = state.pending.filter { !answeredPermissionIDs.contains($0.id) }
        statusView.apply(agents: state.agents, pendingCount: pending.count, permission: pending.first)
    }

    private func answer(_ item: BridgeClient.PermissionItem, decision: String, ruleIndex: Int?) {
        guard !answeredPermissionIDs.contains(item.id) else { return }
        answeredPermissionIDs.insert(item.id)
        client.sendDecision(id: item.id, decision: decision, ruleIndex: ruleIndex) { _ in }
    }
}

// MARK: - Cursor-mode clicks

extension AgentTouchBarWidget: PKScreenEdgeMouseDelegate {

    public func screenEdgeController(_ controller: PKScreenEdgeController, mouseClickAtLocation location: NSPoint, in view: NSView) {
        guard let statusView = self.view as? StatusView else { return }
        let local = statusView.convert(location, from: view)
        if statusView.bounds.contains(local) {
            statusView.cycleSelection()
        }
    }

    public func screenEdgeController(_ controller: PKScreenEdgeController, mouseEnteredAtLocation location: NSPoint, in view: NSView) {}

    public func screenEdgeController(_ controller: PKScreenEdgeController, mouseMovedAtLocation location: NSPoint, in view: NSView) {}

    public func screenEdgeController(_ controller: PKScreenEdgeController, mouseExitedAtLocation location: NSPoint, in view: NSView) {}
}
