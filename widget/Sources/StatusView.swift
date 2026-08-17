import AppKit

/// Main widget view. Shows the live agent status with a shimmering label.
/// Bounded width while active, can collapse when all enabled agents are idle.
///
/// Attention tiers (from agent-status UX patterns):
/// - active (thinking/answering/working) → white text + shimmer sweep
/// - response ready                       → green breathing text
/// - ready / connected                    → brand-colored text, gentle pulse
/// - needs input                          → amber pulsing text
final class StatusView: NSView {

    /// Bounded width: wide enough for useful status text, but leaves room
    /// for Pock widgets and the system control strip on either side.
    static let preferredWidth: CGFloat = 360

    // MARK: Callbacks

    var onTap: (() -> Void)?

    // MARK: Subviews

    private let iconView = NSImageView(frame: .zero)
    private let label = ShimmerLabel(frame: .zero)

    // MARK: State

    private var agents: [BridgeClient.AgentInfo] = []
    private var activeAgents: [BridgeClient.AgentInfo] = []
    private var selectedIndex = 0
    private var pinned = false
    private var pinnedSince: Date?
    private var presentationWidth = StatusView.preferredWidth
    private var compactWhenIdle = false

    // Anti-flicker: a displayed agent stays displayed until it has been
    // quiet for this long while another agent is active.
    private let switchHysteresis: TimeInterval = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .white
        iconView.wantsLayer = true
        addSubview(iconView)
        addSubview(label)

        let tap = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        tap.allowedTouchTypes = .direct
        addGestureRecognizer(tap)
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: presentationWidth, height: 30)
    }

    override func layout() {
        super.layout()
        if presentationWidth <= 1 {
            iconView.isHidden = true
            label.isHidden = true
            return
        }
        if compactWhenIdle {
            label.isHidden = true
            iconView.isHidden = false
            iconView.frame = NSRect(
                x: max((bounds.width - 18) / 2, 0),
                y: (bounds.height - 18) / 2,
                width: 18,
                height: 18
            )
            return
        }
        label.isHidden = false
        iconView.isHidden = false
        let maxTextWidth = max(bounds.width - 56, 60)
        let textWidth = min(label.measuredWidth, maxTextWidth)
        let groupWidth = 16 + 8 + textWidth
        let groupX = max((bounds.width - groupWidth) / 2, 8)
        iconView.frame = NSRect(x: groupX, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: groupX + 24, y: 0, width: textWidth, height: bounds.height)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Tap

    @objc private func handleTap() {
        onTap?()
    }

    func cycleSelection() {
        guard activeAgents.count > 1 else { return }
        pinned = true
        pinnedSince = Date()
        selectedIndex = (selectedIndex + 1) % activeAgents.count
        refresh()
    }

    // MARK: State

    func apply(agents: [BridgeClient.AgentInfo]) {
        self.agents = agents
        activeAgents = agents.filter { $0.lastActive > 0 }

        if let pinnedSince = pinnedSince, Date().timeIntervalSince(pinnedSince) > 300 {
            pinned = false
            self.pinnedSince = nil
        }
        if !pinned || activeAgents.isEmpty {
            selectedIndex = displayedAgentIndex()
        }
        selectedIndex = min(selectedIndex, max(activeAgents.count - 1, 0))

        updateIdlePresentation()
        refresh()
        needsLayout = true
    }

    private func updateIdlePresentation() {
        let activeStatuses: Set<String> = [
            "connected", "thinking", "answering", "working",
            "needsInput", "responseReady"
        ]
        let hasAttention = activeAgents.contains { activeStatuses.contains($0.status) }
        let mode = AgentPrefs.visibilityMode
        let widgetEnabled = AgentPrefs.widgetEnabled && AgentPrefs.hasEnabledAgents
        let shouldCollapse = !hasAttention && mode != "always"

        compactWhenIdle = shouldCollapse
        let nextWidth: CGFloat
        if !widgetEnabled {
            nextWidth = 18
        } else if shouldCollapse {
            nextWidth = mode == "active" ? 18 : 36
        } else {
            nextWidth = Self.preferredWidth
        }
        guard nextWidth != presentationWidth else { return }
        presentationWidth = nextWidth
        alphaValue = (!widgetEnabled || (shouldCollapse && mode == "active")) ? 0.12 : 1
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
        needsLayout = true
    }

    private func displayedAgentIndex() -> Int {
        guard !activeAgents.isEmpty else { return 0 }
        let currentID = activeAgents[selectedIndex].agent
        let now = Date().timeIntervalSince1970
        let currentQuietFor = now - activeAgents[selectedIndex].lastActive
        let busiest = activeAgents.first!
        if currentID == busiest.agent { return selectedIndex }
        if currentQuietFor < switchHysteresis { return selectedIndex }
        return 0
    }

    private func refresh() {
        guard !activeAgents.isEmpty else {
            iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            iconView.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
            setDisplayText("No agent running", textColor: .white, shimmer: false)
            setAmbient(.none)
            return
        }
        let agent = activeAgents[selectedIndex]
        let brand = NSColor(hex: agent.color) ?? .white
        iconView.image = logo(for: agent.agent)
            ?? NSImage(systemSymbolName: agent.symbol, accessibilityDescription: nil)

        var text = agent.label
        if let detail = agent.detail, !detail.isEmpty {
            text = "\(agent.label) · \(detail)"
        }

        let shimmerAllowed = AgentPrefs.shimmerEnabled
        switch agent.status {
        case "thinking":
            iconView.contentTintColor = brand
            setDisplayText(text, textColor: .white, shimmer: shimmerAllowed)
            setAmbient(.none)
        case "answering":
            iconView.contentTintColor = brand
            setDisplayText(text, textColor: .white, shimmer: shimmerAllowed)
            setAmbient(.none)
        case "working":
            iconView.contentTintColor = brand
            setDisplayText(text, textColor: .white, shimmer: shimmerAllowed)
            setAmbient(.none)
        case "responseReady":
            iconView.contentTintColor = NSColor.systemGreen
            setDisplayText(text, textColor: NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.55, alpha: 1), shimmer: false)
            setAmbient(.breathe)
        case "connected":
            iconView.contentTintColor = brand
            setDisplayText(text, textColor: brand, shimmer: false)
            setAmbient(.breathe)
        case "needsInput":
            iconView.contentTintColor = NSColor.systemYellow
            setDisplayText(text, textColor: NSColor.systemYellow, shimmer: false)
            setAmbient(.breathe)
        default: // ready / idle
            iconView.contentTintColor = brand
            setDisplayText(text, textColor: .white, shimmer: false)
            setAmbient(.pulse)
        }
    }

    private func setDisplayText(_ text: String, textColor: NSColor, shimmer: Bool) {
        label.textColor = textColor
        label.text = text
        label.setShimmering(shimmer && AgentPrefs.shimmerEnabled)
        needsLayout = true
        layout()
    }

    private func logo(for agent: String) -> NSImage? {
        let resource: String
        switch agent {
        case "claude": resource = "Claude"
        case "codex": resource = "ChatGPT"
        case "opencode": resource = "OpenCode"
        default: return nil
        }
        guard let image = Bundle(for: type(of: self)).image(forResource: resource) else {
            return nil
        }
        image.isTemplate = false
        return image
    }

    // MARK: Ambient animation

    private enum Ambient {
        case none
        case pulse      // ready: gentle
        case breathe    // response ready / needs input: stronger
    }

    private var ambient: Ambient = .none

    private func setAmbient(_ mode: Ambient) {
        guard mode != ambient else { return }
        ambient = mode
        iconView.layer?.removeAnimation(forKey: "ambientPulse")
        switch mode {
        case .none:
            iconView.layer?.opacity = 1
        case .pulse:
            addAmbientAnimation(from: 0.55, to: 1.0, duration: 2.2)
        case .breathe:
            addAmbientAnimation(from: 0.35, to: 1.0, duration: 1.4)
        }
    }

    private func addAmbientAnimation(from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconView.layer?.add(animation, forKey: "ambientPulse")
    }
}