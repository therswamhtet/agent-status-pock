import AppKit

final class VoiceInkDictationButton: NSView {
    static let preferredWidth: CGFloat = 52

    var onTap: (() -> Void)?

    private let iconView = NSImageView(frame: .zero)
    private var feedbackReset: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        iconView.image = Self.microphoneImage()
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])

        let tap = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        tap.allowedTouchTypes = .direct
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.preferredWidth, height: 30)
    }

    @objc func handleTap() {
        onTap?()
        showTapFeedback()
    }

    private func showTapFeedback() {
        feedbackReset?.cancel()
        iconView.contentTintColor = .systemRed
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.22).cgColor

        let reset = DispatchWorkItem { [weak self] in
            self?.iconView.contentTintColor = .white
            self?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        }
        feedbackReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: reset)
    }

    static func microphoneImage() -> NSImage {
        NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceInk dictation")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }
}
