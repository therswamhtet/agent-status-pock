import AppKit
import QuartzCore

/// A single-line status label with a shimmering light sweep.
///
/// Two stacked `CATextLayer`s render the same string: a dim base layer and a
/// bright layer masked by a moving soft-edged gradient band, producing the
/// classic "shimmer" effect. Layer-native text guarantees the mask renders
/// correctly in the Touch Bar's layer-backed context.
final class ShimmerLabel: NSView {

    private let baseLayer = CATextLayer()
    private let brightLayer = CATextLayer()
    private let maskGradient = CAGradientLayer()
    private var shimmerAnimation: CABasicAnimation?
    private var isShimmering = false
    private var font = NSFont.systemFont(ofSize: 13, weight: .semibold)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        for layer in [baseLayer, brightLayer] {
            layer.contentsScale = scale
            layer.font = font
            layer.fontSize = 13
            layer.foregroundColor = NSColor.white.cgColor
            layer.alignmentMode = .left
            layer.isWrapped = false
            layer.truncationMode = .end
            self.layer?.addSublayer(layer)
        }

        baseLayer.opacity = 0.55

        // Soft-edged band with a full-brightness plateau (~20% of width),
        // mirroring the reference shimmer: transparent → ramp up → white
        // plateau → ramp down → transparent.
        maskGradient.colors = [
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor.white.cgColor,
            NSColor.white.cgColor,
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
        ]
        maskGradient.locations = [0.0, 0.30, 0.40, 0.60, 0.70, 1.0]
        maskGradient.startPoint = CGPoint(x: 0, y: 0.5)
        maskGradient.endPoint = CGPoint(x: 1, y: 0.5)
        maskGradient.anchorPoint = CGPoint(x: 0, y: 0.5)
        brightLayer.mask = maskGradient
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateTextGeometry()
    }

    /// Vertically centers the single text line inside the 30pt bar height.
    private func updateTextGeometry() {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let lineHeight = ("Ag" as NSString).size(withAttributes: attrs).height
        let y = max((bounds.height - lineHeight) / 2, 0)
        let textRect = CGRect(x: 0, y: y, width: bounds.width, height: lineHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.frame = textRect
        brightLayer.frame = textRect
        CATransaction.commit()
        updateMaskGeometry()
    }

    var text: String = "" {
        didSet {
            baseLayer.string = text
            brightLayer.string = text
            updateTextGeometry()
        }
    }

    /// Measured width of the current text (plus a safety pad for glyph
    /// rounding at 2x) — used by the superview to size the label frame.
    var measuredWidth: CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let width = (text as NSString).size(withAttributes: attrs).width
        return width + 6
    }

    /// Text color for both layers (bright layer stays white for the sweep;
    /// the base layer tints to the state color).
    var textColor: NSColor = .white {
        didSet {
            baseLayer.foregroundColor = textColor.cgColor
            brightLayer.foregroundColor = blend(textColor, with: .white, ratio: 0.6).cgColor
        }
    }

    private func blend(_ a: NSColor, with b: NSColor, ratio: CGFloat) -> NSColor {
        let c1 = a.usingColorSpace(.deviceRGB) ?? a
        let c2 = b.usingColorSpace(.deviceRGB) ?? b
        return NSColor(
            red: c1.redComponent + (c2.redComponent - c1.redComponent) * ratio,
            green: c1.greenComponent + (c2.greenComponent - c1.greenComponent) * ratio,
            blue: c1.blueComponent + (c2.blueComponent - c1.blueComponent) * ratio,
            alpha: 1
        )
    }

    var isActive: Bool {
        return isShimmering
    }

    func setShimmering(_ shimmering: Bool) {
        guard shimmering != isShimmering else { return }
        isShimmering = shimmering
        if shimmering {
            startShimmer()
        } else {
            stopShimmer()
        }
    }

    // MARK: Shimmer

    private func updateMaskGeometry() {
        let width = max(bounds.width, 40)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskGradient.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        maskGradient.position = CGPoint(x: -width, y: bounds.midY)
        CATransaction.commit()
        if let animation = shimmerAnimation {
            animation.fromValue = CGPoint(x: -width, y: bounds.midY)
            animation.toValue = CGPoint(x: width * 2, y: bounds.midY)
        }
    }

    private func startShimmer() {
        updateMaskGeometry()
        let width = max(bounds.width, 40)
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -width
        animation.toValue = width * 2
        animation.duration = 1.8
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        maskGradient.add(animation, forKey: "shimmerSweep")
        shimmerAnimation = animation
        brightLayer.isHidden = false
    }

    private func stopShimmer() {
        maskGradient.removeAnimation(forKey: "shimmerSweep")
        shimmerAnimation = nil
        brightLayer.isHidden = true
    }
}
