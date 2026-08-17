import AppKit

/// Polished Agent Status preferences: master enable, branded agent rows,
/// visibility policy, animation and permission controls.
final class AgentTouchBarPreferencePane: NSViewController {

    private static let agents: [(id: String, name: String, subtitle: String, logo: String)] = [
        ("claude", "Claude", "Anthropic Claude Code", "Claude"),
        ("codex", "ChatGPT / Codex", "OpenAI coding agents", "ChatGPT"),
        ("opencode", "OpenCode", "OpenCode TUI and server", "OpenCode"),
    ]

    private var masterSwitch: NSSwitch!
    private var agentSwitches: [NSSwitch] = []
    private var visibilityControl: NSSegmentedControl!
    private var shimmerSwitch: NSSwitch!
    private var permissionSwitch: NSSwitch!
    private var dependentControls: [NSControl] = []

    // MARK: PKWidgetPreference compatibility

    static var nibName: NSNib.Name { NSNib.Name("AgentTouchBarPreferencePane") }
    override var nibName: NSNib.Name? { Self.nibName }

    @objc public static func reset() {
        AgentPrefs.defaults.removePersistentDomain(forName: AgentPrefs.suiteName)
        NotificationCenter.default.post(name: AgentPrefs.changedNotification, object: nil)
    }

    @objc public func reset() {
        Self.reset()
        loadValues()
    }

    // MARK: View

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))
        root.wantsLayer = true

        let title = NSTextField(labelWithString: "Agent Status")
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Choose what appears on your Touch Bar")
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 2

        masterSwitch = NSSwitch()
        masterSwitch.target = self
        masterSwitch.action = #selector(controlChanged)
        let masterRow = settingRow(
            icon: NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil),
            title: "Enable Agent Status",
            subtitle: "Show agent activity and requests on the Touch Bar",
            control: masterSwitch
        )

        let agentsTitle = sectionLabel("Agents")
        var rows: [NSView] = [heading, separator(), masterRow, agentsTitle]
        for agent in Self.agents {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(controlChanged)
            agentSwitches.append(toggle)
            dependentControls.append(toggle)
            rows.append(settingRow(
                icon: logo(named: agent.logo),
                title: agent.name,
                subtitle: agent.subtitle,
                control: toggle
            ))
        }

        let appearanceTitle = sectionLabel("Appearance")
        visibilityControl = NSSegmentedControl(labels: ["Always", "Compact", "Active only"], trackingMode: .selectOne, target: self, action: #selector(controlChanged))
        visibilityControl.segmentStyle = .rounded
        visibilityControl.setWidth(72, forSegment: 0)
        visibilityControl.setWidth(76, forSegment: 1)
        visibilityControl.setWidth(88, forSegment: 2)
        dependentControls.append(visibilityControl)

        let visibilityRow = settingRow(
            icon: NSImage(systemSymbolName: "eye", accessibilityDescription: nil),
            title: "Visibility",
            subtitle: "Always visible, compact while idle, or active only",
            control: visibilityControl
        )

        shimmerSwitch = NSSwitch()
        shimmerSwitch.target = self
        shimmerSwitch.action = #selector(controlChanged)
        dependentControls.append(shimmerSwitch)
        let shimmerRow = settingRow(
            icon: NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil),
            title: "Shimmer while working",
            subtitle: "Animate Thinking, Editing, Reading, and Running states",
            control: shimmerSwitch
        )

        permissionSwitch = NSSwitch()
        permissionSwitch.target = self
        permissionSwitch.action = #selector(controlChanged)
        dependentControls.append(permissionSwitch)
        let permissionRow = settingRow(
            icon: NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil),
            title: "Permission controls",
            subtitle: "Show Deny, Once, and Always actions on the Touch Bar",
            control: permissionSwitch
        )

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetTapped))
        resetButton.bezelStyle = .rounded

        rows.append(contentsOf: [separator(), appearanceTitle, visibilityRow, shimmerRow, permissionRow, separator(), resetButton])

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
        ])

        view = root
        loadValues()
    }

    private func settingRow(icon: NSImage?, title: String, subtitle: String, control: NSView) -> NSView {
        let iconView = NSImageView(frame: .zero)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.widthAnchor.constraint(equalToConstant: 26).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [iconView, labels, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 480).isActive = true
        return row
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 480).isActive = true
        return box
    }

    private func logo(named name: String) -> NSImage? {
        return Bundle(for: type(of: self)).image(forResource: name)
    }

    // MARK: Values

    private func loadValues() {
        masterSwitch.state = AgentPrefs.widgetEnabled ? .on : .off
        for (index, agent) in Self.agents.enumerated() {
            agentSwitches[index].state = AgentPrefs.isAgentEnabled(agent.id) ? .on : .off
        }
        switch AgentPrefs.visibilityMode {
        case "compact": visibilityControl.selectedSegment = 1
        case "active": visibilityControl.selectedSegment = 2
        default: visibilityControl.selectedSegment = 0
        }
        shimmerSwitch.state = AgentPrefs.shimmerEnabled ? .on : .off
        permissionSwitch.state = AgentPrefs.permissionButtonsEnabled ? .on : .off
        updateControlAvailability()
    }

    @objc private func controlChanged() {
        saveValues()
        updateControlAvailability()
    }

    @objc private func resetTapped() {
        reset()
    }

    private func saveValues() {
        let defaults = AgentPrefs.defaults
        defaults.set(masterSwitch.state == .on, forKey: "widgetEnabled")
        var enabled: [String: Bool] = [:]
        for (index, agent) in Self.agents.enumerated() {
            enabled[agent.id] = agentSwitches[index].state == .on
        }
        defaults.set(enabled, forKey: "enabledAgents")
        let modes = ["always", "compact", "active"]
        defaults.set(modes[max(visibilityControl.selectedSegment, 0)], forKey: "visibilityMode")
        defaults.set(shimmerSwitch.state == .on, forKey: "shimmerEnabled")
        defaults.set(permissionSwitch.state == .on, forKey: "permissionButtonsEnabled")
        defaults.synchronize()
        NotificationCenter.default.post(name: AgentPrefs.changedNotification, object: nil)
    }

    private func updateControlAvailability() {
        let enabled = masterSwitch.state == .on
        dependentControls.forEach { $0.isEnabled = enabled }
    }
}
