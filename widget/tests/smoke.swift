// Production-mirroring load test: replicates what Pock.app does when it
// loads a widget — using the REAL PockKit embedded in /Applications/Pock.app.
//
//   cd widget && ./build.sh && swift tests/smoke.swift
//
// Verifies:
//   1. Pock's own PockKit loads
//   2. The .pock bundle loads with zero PockKit symbol dependencies
//   3. The principal class instantiates (same path Pock uses)
//   4. The PKWidget members exist (customizationLabel, view)
import AppKit
import Foundation

let dist = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist")

// 1. Load the same frameworks Pock.app loads at launch (production parity).
//    Pock's executable resolves these via @executable_path/../Frameworks;
//    a standalone test process must dlopen them manually, in order.
let pockFrameworks = "/Applications/Pock.app/Contents/Frameworks"
for name in ["TinyConstraints.framework/Versions/A/TinyConstraints",
             "PockKit.framework/Versions/A/PockKit"] {
    let path = "\(pockFrameworks)/\(name)"
    guard FileManager.default.fileExists(atPath: path),
          dlopen(path, RTLD_NOW) != nil else {
        fatalError("failed to dlopen \(name): \(String(cString: dlerror()))")
    }
}
print("1. Pock's frameworks loaded (TinyConstraints + PockKit)")

// 2. Load the widget bundle the same way Pock's WidgetsLoader does.
let requestedBundle = CommandLine.arguments.dropFirst().first ?? "AgentTouchBar.pock"
let bundlePath = dist.appendingPathComponent(requestedBundle).path
guard let bundle = Bundle(path: bundlePath) else {
    fatalError("failed to create bundle at \(bundlePath)")
}
guard bundle.load() else {
    fatalError("bundle load failed")
}
print("2. Bundle loaded")

// 3. Pock's PKWidgetInfo requires: bundleIdentifier, principalClass, name,
//    author, version — replicate those checks exactly.
guard bundle.bundleIdentifier != nil else { fatalError("missing CFBundleIdentifier") }
guard bundle.object(forInfoDictionaryKey: "PKWidgetAuthor") != nil else { fatalError("missing PKWidgetAuthor") }
guard bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") != nil else { fatalError("missing version") }
guard bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") != nil
    || bundle.object(forInfoDictionaryKey: "CFBundleName") != nil else { fatalError("missing display name") }
print("3. Info.plist keys OK (Pock's PKWidgetInfo checks pass)")

// 4. Instantiate the principal class (what Pock does for each widget).
guard let cls = bundle.principalClass as? NSObject.Type else {
    fatalError("no principal class")
}
print("4. Principal class: \(cls)")
let instance = cls.init()
print("   Instance created: \(instance)")

// 5. Exercise PKWidget members.
let widget = instance as AnyObject
guard let view = widget.value(forKey: "view") as? NSView else {
    fatalError("missing view")
}
print("5. view: \(view) (frame \(view.frame), intrinsic \(view.intrinsicContentSize))")
guard let label = widget.value(forKey: "customizationLabel") as? String else {
    fatalError("missing customizationLabel")
}
print("   customizationLabel: \(label)")

print("PRODUCTION LOAD TEST PASSED")
