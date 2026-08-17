import AppKit
import PockKit

public final class VoiceInkDictationWidget: NSObject, PKWidget {
    @available(*, deprecated, message: "Identifier is read from the bundle's Info.plist")
    public static var identifier: String = "com.touchbar.voiceinkdictation"

    @objc public var identifier = NSTouchBarItem.Identifier("com.touchbar.voiceinkdictation")
    public var customizationLabel = "VoiceInk Dictation"
    public var view: NSView!

    private static weak var shared: VoiceInkDictationWidget?

    @objc public static func viewWillAppear() { shared?.viewWillAppear() }
    @objc public static func viewDidAppear() { shared?.viewDidAppear() }
    @objc public static func viewWillDisappear() { shared?.viewWillDisappear() }
    @objc public static func viewDidDisappear() { shared?.viewDidDisappear() }
    @objc public static func prepareForCustomization() { shared?.prepareForCustomization() }
    @objc public static var imageForCustomization: NSImage { makeCustomizationImage() }

    @objc public func viewWillAppear() {}
    @objc public func viewDidAppear() {}
    @objc public func viewWillDisappear() {}
    @objc public func viewDidDisappear() {}
    @objc public func prepareForCustomization() {}
    @objc public var imageForCustomization: NSImage { Self.makeCustomizationImage() }

    override public required init() {
        let button = VoiceInkDictationButton(
            frame: NSRect(x: 0, y: 0, width: VoiceInkDictationButton.preferredWidth, height: 30)
        )
        super.init()
        view = button
        button.onTap = {
            _ = VoiceInkShortcutEmitter.tap()
        }
        Self.shared = self
    }

    private static func makeCustomizationImage() -> NSImage {
        let size = NSSize(width: 142, height: 30)
        return NSImage(size: size, flipped: false) { rect in
            let icon = VoiceInkDictationButton.microphoneImage()
            icon.draw(in: NSRect(x: 10, y: (rect.height - 17) / 2, width: 17, height: 17))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let text = "VoiceInk Dictation" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: 35, y: (rect.height - textSize.height) / 2), withAttributes: attributes)
            return true
        }
    }
}

extension VoiceInkDictationWidget: PKScreenEdgeMouseDelegate {
    public func screenEdgeController(
        _ controller: PKScreenEdgeController,
        mouseClickAtLocation location: NSPoint,
        in view: NSView
    ) {
        guard let button = self.view as? VoiceInkDictationButton else { return }
        let local = button.convert(location, from: view)
        guard button.bounds.contains(local) else { return }
        button.handleTap()
    }

    public func screenEdgeController(_ controller: PKScreenEdgeController, mouseEnteredAtLocation location: NSPoint, in view: NSView) {}
    public func screenEdgeController(_ controller: PKScreenEdgeController, mouseMovedAtLocation location: NSPoint, in view: NSView) {}
    public func screenEdgeController(_ controller: PKScreenEdgeController, mouseExitedAtLocation location: NSPoint, in view: NSView) {}
}
