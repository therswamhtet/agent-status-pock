import AppKit

/// Main widget view. Uses a bounded width while active and can collapse when
/// all enabled agents are idle; shows the live agent status, or a minimal
/// permission panel (Deny / numbered suggestions / Allow) when an agent
/// asks for approval.
///
/// Attention tiers (from agent-status UX patterns):
/// - active (thinking/answering/working) → white text + shimmer sweep
/// - response ready                       → green breathing text
/// - ready / connected                    → brand-colored text, gentle pulse
/// - needs input                          → amber pulsing text
final class StatusView: NSView {

    /// Bounded width: wide enough for useful status text and compact
    /// permission buttons, but leaves room for Pock widgets and the system
    /// control strip on either side.
    static let preferredWidth: CGFloat = 360

    // MARK: Callbacks

    var onTap: (() -> Void)?
    var onDeny: ((BridgeClient.PermissionItem) -> Void)?
    var onAllow: ((BridgeClient.PermissionItem) -> Void)?
    var onSuggestion: ((BridgeClient.PermissionItem, Int) -> Void)?

    // MARK: Subviews (status mode)

    private let iconView = NSImageView(frame: .zero)
    private let label = ShimmerLabel(frame: .zero)

    // MARK: Subviews (permission mode)

    private let panelContainer = NSView(frame: .zero)
    private let denyButton = NSButton(title: "Deny", target: nil, action: nil)
    private let panelIcon = NSImageView(frame: .zero)
    private let panelTitle = NSTextField(labelWithString: "")
    private let allowButton = NSButton(title: "Allow", target: nil, action: nil)
    private var suggestionButtons: [NSButton] = []
    private var questionButtons: [NSButton] = []
    private var isQuestionPanel = false

    // MARK: State

    private var agents: [BridgeClient.AgentInfo] = []
    private var activeAgents: [BridgeClient.AgentInfo] = []
    private var selectedIndex = 0
    private var pinned = false
    private var pinnedSince: Date?
    private var currentPermission: BridgeClient.PermissionItem?
    private(set) var pendingCount = 0
    private var presentationWidth = StatusView.preferredWidth
    private var compactWhenIdle = false

    // Anti-flicker: a displayed agent stays displayed until it has been
    // quiet for this long while another agent is active.
    private let switchHysteresis: TimeInterval = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // Do not consume all remaining Touch Bar space. A high hugging
        // priority keeps the widget bounded so side/control-strip items stay
        // visible; the content itself is still centered inside this area.
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

        // Permission mode. Laid out manually in layout() so the panel always
        // fits the available width, like the status mode.
        panelContainer.isHidden = true
        addSubview(panelContainer)
        panelContainer.addSubview(denyButton)
        panelContainer.addSubview(panelIcon)
        panelContainer.addSubview(panelTitle)
        panelContainer.addSubview(allowButton)

        style(denyButton, color: .systemRed, font: NSFont.systemFont(ofSize: 13, weight: .bold))
        denyButton.addGestureRecognizer(clickGesture(#selector(denyTapped)))

        panelIcon.imageScaling = .scaleProportionallyDown

        panelTitle.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        panelTitle.textColor = .white
        panelTitle.maximumNumberOfLines = 1
        panelTitle.lineBreakMode = .byTruncatingMiddle
        panelTitle.cell?.truncatesLastVisibleLine = true

        style(allowButton, color: .systemGreen, font: NSFont.systemFont(ofSize: 13, weight: .bold))
        allowButton.addGestureRecognizer(clickGesture(#selector(allowTapped)))
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: presentationWidth, height: 30)
    }

    override func layout() {
        super.layout()
        panelContainer.frame = bounds
        guard panelContainer.isHidden else {
            if isQuestionPanel {
                layoutQuestionPanel()
            } else {
                layoutPermissionPanel()
            }
            return
        }
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
        // Center icon + status text as a group, whatever width the Touch Bar
        // gives this view. The label truncates with an ellipsis only when
        // the measured text can't fit.
        let maxTextWidth = max(bounds.width - 56, 60)
        let textWidth = min(label.measuredWidth, maxTextWidth)
        let groupWidth = 16 + 8 + textWidth
        let groupX = max((bounds.width - groupWidth) / 2, 8)
        iconView.frame = NSRect(x: groupX, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: groupX + 24, y: 0, width: textWidth, height: bounds.height)
    }

    /// Manual permission-panel layout: fixed edges (Deny / Allow) with the
    /// numbered suggestion buttons and a flexible, truncating title between
    /// them. Guarantees the panel fits the bar without Auto Layout.
    private func layoutPermissionPanel() {
        let gap: CGFloat = 6
        let denyW: CGFloat = 52
        let iconW: CGFloat = 16
        let allowW: CGFloat = 56
        let midY = (bounds.height - 22) / 2

        let suggestionWidths = suggestionButtons.map { button -> CGFloat in
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]
            let textWidth = (button.title as NSString).size(withAttributes: attrs).width
            return min(max(textWidth + 12, 26), 58)
        }
        let suggestionTotal = suggestionWidths.reduce(0, +)
        let itemCount = CGFloat(3 + suggestionButtons.count)
        let fixed = denyW + iconW + allowW + suggestionTotal + gap * itemCount
        let titleWidth = max(min(bounds.width - fixed - 40, 220), 36)

        var x = max((bounds.width - fixed - titleWidth) / 2, 6)
        denyButton.frame = NSRect(x: x, y: midY, width: denyW, height: 22)
        x += denyW + gap
        panelIcon.frame = NSRect(x: x, y: (bounds.height - 16) / 2, width: iconW, height: 16)
        x += iconW + gap
        panelTitle.frame = NSRect(x: x, y: (bounds.height - 16) / 2, width: titleWidth, height: 16)
        x += titleWidth + gap
        for (button, width) in zip(suggestionButtons, suggestionWidths) {
            button.frame = NSRect(x: x, y: midY, width: width, height: 22)
            x += width + gap
        }
        allowButton.frame = NSRect(x: x, y: midY, width: allowW, height: 22)
    }

    /// Manual question-panel layout: icon + label + numbered option buttons.
    /// No Deny/Allow — the user answers in the terminal; the buttons are a
    /// visual aid so they can see the options on the Touch Bar.
    private func layoutQuestionPanel() {
        let gap: CGFloat = 6
        let iconW: CGFloat = 16
        let buttonW: CGFloat = 26
        let midY = (bounds.height - 22) / 2

        let buttonTotal = CGFloat(questionButtons.count) * buttonW
        let itemCount = CGFloat(2 + questionButtons.count)
        let fixed = iconW + buttonTotal + gap * itemCount
        let titleWidth = max(bounds.width - fixed - 40, 60)

        var x = max((bounds.width - fixed - titleWidth) / 2, 6)
        panelIcon.frame = NSRect(x: x, y: (bounds.height - 16) / 2, width: iconW, height: 16)
        x += iconW + gap
        panelTitle.frame = NSRect(x: x, y: (bounds.height - 16) / 2, width: titleWidth, height: 16)
        x += titleWidth + gap
        for button in questionButtons {
            button.frame = NSRect(x: x, y: midY, width: buttonW, height: 22)
            x += buttonW + gap
        }
    }

    private func style(_ button: NSButton, color: NSColor, font: NSFont) {
        button.bezelStyle = .rounded
        button.bezelColor = color
        button.font = font
        button.contentTintColor = .white
        button.focusRingType = .none
    }

    private func clickGesture(_ action: Selector) -> NSClickGestureRecognizer {
        let gesture = NSClickGestureRecognizer(target: self, action: action)
        gesture.allowedTouchTypes = .direct
        return gesture
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Tap

    @objc private func handleTap() {
        guard panelContainer.isHidden else { return }
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

    func apply(agents: [BridgeClient.AgentInfo], pendingCount: Int, permission: BridgeClient.PermissionItem?) {
        self.agents = agents
        self.pendingCount = pendingCount
        activeAgents = agents.filter { $0.lastActive > 0 }

        if let pinnedSince = pinnedSince, Date().timeIntervalSince(pinnedSince) > 300 {
            pinned = false
            self.pinnedSince = nil
        }
        if !pinned || activeAgents.isEmpty {
            selectedIndex = displayedAgentIndex()
        }
        selectedIndex = min(selectedIndex, max(activeAgents.count - 1, 0))

        let samePermission = permission?.id == currentPermission?.id
        currentPermission = permission
        if let permission = permission {
            isQuestionPanel = false
            updateIdlePresentation(forceVisible: true)
            if !samePermission { showPermissionPanel(permission) }
            panelContainer.isHidden = false
            label.isHidden = true
            iconView.isHidden = true
        } else if let questionOptions = currentQuestionOptions() {
            isQuestionPanel = true
            clearSuggestionButtons()
            updateIdlePresentation(forceVisible: true)
            showQuestionPanel(options: questionOptions)
            panelContainer.isHidden = false
            label.isHidden = true
            iconView.isHidden = true
        } else {
            isQuestionPanel = false
            panelContainer.isHidden = true
            clearSuggestionButtons()
            clearQuestionButtons()
            updateIdlePresentation(forceVisible: false)
        }
        refresh()
        needsLayout = true
    }

    private func currentQuestionOptions() -> [String]? {
        guard activeAgents.indices.contains(selectedIndex) else { return nil }
        let agent = activeAgents[selectedIndex]
        guard agent.status == "needsInput" else { return nil }
        if let opts = agent.options, !opts.isEmpty { return opts }
        return nil
    }

    private func updateIdlePresentation(forceVisible: Bool) {
        let activeStatuses: Set<String> = [
            "connected", "thinking", "answering", "working",
            "waitingPermission", "needsInput", "responseReady"
        ]
        let hasAttention = forceVisible || activeAgents.contains { activeStatuses.contains($0.status) }
        let mode = AgentPrefs.visibilityMode
        let widgetEnabled = AgentPrefs.widgetEnabled && AgentPrefs.hasEnabledAgents
        let shouldCollapse = !hasAttention && mode != "always"

        compactWhenIdle = shouldCollapse
        let nextWidth: CGFloat
        if !widgetEnabled {
            // Keep a stable tiny anchor so Pock can restore the item when the
            // master switch is turned back on.
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

    /// Sticky agent: keep the current selection until it has been quiet for
    /// a while and another agent took over — prevents flickering between
    /// concurrent agents.
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
        guard panelContainer.isHidden else { return }
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
        case "waitingPermission":
            iconView.contentTintColor = brand
            setDisplayText(text, textColor: .white, shimmer: false)
            setAmbient(.none)
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
        // Recompute the centered frame for the new text immediately —
        // otherwise the old width clips the new string.
        needsLayout = true
        layout()
    }

    // MARK: Permission panel

    private func showPermissionPanel(_ item: BridgeClient.PermissionItem) {
        clearSuggestionButtons()
        clearQuestionButtons()
        denyButton.isHidden = false
        allowButton.isHidden = false

        let badge = pendingCount > 1 ? "  +\(pendingCount - 1)" : ""
        panelTitle.stringValue = "\(item.agent.capitalized) · \(item.tool)\(badge)"
        let brand = NSColor(hex: item.agent == "claude" ? "D97757" : (item.agent == "codex" ? "10A37F" : "8B5CF6")) ?? .white
        panelIcon.contentTintColor = brand
        panelIcon.image = logo(for: item.agent)
            ?? NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)

        // Numbered suggestion buttons (1/2/3), as on the agent's own prompt.
        // Picking one echoes the "add rule" entry back to the agent so it
        // stops asking for that operation.
        let suggestions = Array(item.suggestions.prefix(3))
        let maxLabel = suggestions.count >= 3 ? 9 : (suggestions.count == 2 ? 12 : 18)
        for (index, suggestion) in suggestions.enumerated() {
            let title = "\(index + 1) \(Self.truncate(suggestion.label, to: maxLabel))"
            suggestionButtons.append(makeSuggestionButton(title: title, tooltip: suggestion.label, tag: index, color: brand))
        }
        for button in suggestionButtons {
            panelContainer.addSubview(button)
        }
    }

    private func makeSuggestionButton(title: String, tooltip: String, tag: Int, color: NSColor) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        style(button, color: color, font: NSFont.systemFont(ofSize: 10, weight: .semibold))
        button.toolTip = tooltip
        button.tag = tag
        button.addGestureRecognizer(clickGesture(#selector(suggestionTapped)))
        return button
    }

    private static func truncate(_ string: String, to maxChars: Int) -> String {
        guard string.count > maxChars else { return string }
        let end = string.index(string.startIndex, offsetBy: maxChars - 1)
        return String(string[..<end]) + "…"
    }

    private func clearSuggestionButtons() {
        for button in suggestionButtons {
            button.removeFromSuperview()
        }
        suggestionButtons.removeAll()
    }

    // MARK: Question panel

    private func showQuestionPanel(options: [String]) {
        clearQuestionButtons()
        denyButton.isHidden = true
        allowButton.isHidden = true

        let agent = activeAgents[selectedIndex]
        let brand = NSColor(hex: agent.color) ?? .white
        panelIcon.contentTintColor = brand
        panelIcon.image = logo(for: agent.agent)
            ?? NSImage(systemSymbolName: agent.symbol, accessibilityDescription: nil)
        panelTitle.stringValue = agent.label

        for (index, option) in options.enumerated() {
            let button = NSButton(title: "\(index + 1)", target: nil, action: nil)
            style(button, color: brand, font: NSFont.systemFont(ofSize: 13, weight: .bold))
            button.toolTip = option
            button.tag = index
            questionButtons.append(button)
            panelContainer.addSubview(button)
        }
    }

    private func clearQuestionButtons() {
        for button in questionButtons {
            button.removeFromSuperview()
        }
        questionButtons.removeAll()
        denyButton.isHidden = false
        allowButton.isHidden = false
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

    @objc private func denyTapped() {
        guard let item = currentPermission else { return }
        onDeny?(item)
    }

    @objc private func allowTapped() {
        guard let item = currentPermission else { return }
        onAllow?(item)
    }

    @objc private func suggestionTapped(_ sender: NSGestureRecognizer) {
        guard let button = sender.view as? NSButton, let item = currentPermission else { return }
        onSuggestion?(item, button.tag)
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
