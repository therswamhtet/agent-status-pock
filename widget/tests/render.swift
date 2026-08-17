// Render test: compiles the widget sources directly, renders each UI state
// to PNG. Usage: cd widget && ./build.sh && swiftc -parse-as-library -o dist/render-test \
//   tests/render.swift Sources/*.swift -I dist -L dist/lib -lPockKit && ./dist/render-test
import AppKit
import Foundation

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist")

func stats(_ file: String) -> (full: Int, mid: Int, faint: Int) {
    let url = outDir.appendingPathComponent(file)
    guard let img = NSImage(contentsOfFile: url.path),
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.bitmapData else {
        fatalError("unreadable \(file)")
    }
    let bpr = rep.bytesPerRow
    let spp = rep.samplesPerPixel
    var full = 0, mid = 0, faint = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            let offset = y * bpr + x * spp
            let r = Int(data[offset])
            let a = Int(data[offset + spp - 1])
            guard a > 200, r > 90 else { continue }
            if r > 200 { full += 1 }
            else if r > 150 { mid += 1 }
            else { faint += 1 }
        }
    }
    return (full, mid, faint)
}

func snapshot(_ view: NSView, width: CGFloat, file: String) {
    let frame = NSRect(x: 0, y: 0, width: width, height: 30)
    view.frame = frame
    view.needsLayout = true
    view.layoutSubtreeIfNeeded()
    view.layer?.layoutIfNeeded()
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width) * 2, pixelsHigh: 60,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("no rep") }
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.16, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width * 2, height: 60).fill()
    view.cacheDisplay(in: view.bounds, to: rep)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no data") }
    try! data.write(to: outDir.appendingPathComponent(file))
    print("wrote dist/\(file)")
}

func agent(_ a: String, _ n: String, _ s: String, _ c: String, _ st: String, _ l: String, _ la: Double) -> BridgeClient.AgentInfo {
    BridgeClient.AgentInfo(agent: a, name: n, symbol: s, color: c, status: st, label: l, tool: nil, detail: nil, lastActive: la)
}

@main
struct RenderTest {
    static func main() {
        guard dlopen(outDir.appendingPathComponent("lib/libPockKit.dylib").path, RTLD_NOW) != nil else {
            fatalError(String(cString: dlerror()))
        }
        let statusView = StatusView(frame: NSRect(x: 0, y: 0, width: StatusView.preferredWidth, height: 30))

        // Working (shimmering) — Claude editing, Codex idle.
        statusView.apply(agents: [
            agent("claude", "Claude", "sparkles", "D97757", "working", "Editing code", 100),
            agent("codex", "Codex", "bolt.fill", "10A37F", "idle", "Waiting for your request", 50),
        ])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        snapshot(statusView, width: StatusView.preferredWidth, file: "render-working.png")

        // Manually center the shimmer band over the text.
        if let label = statusView.subviews.compactMap({ $0 as? ShimmerLabel }).first,
           let bright = label.layer?.sublayers?.last, let mask = bright.mask {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.position = CGPoint(x: 0, y: label.bounds.midY)
            CATransaction.commit()
        }
        snapshot(statusView, width: StatusView.preferredWidth, file: "render-working-sweep.png")

        // Answering (opencode violet).
        statusView.apply(agents: [
            agent("opencode", "OpenCode", "terminal.fill", "8B5CF6", "answering", "Answering…", 200),
            agent("claude", "Claude", "sparkles", "D97757", "idle", "Waiting for your request", 100),
        ])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        snapshot(statusView, width: StatusView.preferredWidth, file: "render-answering.png")

        // Asking a question (yellow, breathing).
        statusView.apply(agents: [
            agent("claude", "Claude", "sparkles", "D97757", "needsInput", "Agent is asking a question", 100),
        ])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        snapshot(statusView, width: StatusView.preferredWidth, file: "render-question.png")

        // Ready state.
        statusView.apply(agents: [
            agent("claude", "Claude", "sparkles", "D97757", "ready", "Claude is ready", 100),
        ])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        snapshot(statusView, width: StatusView.preferredWidth, file: "render-ready.png")

        // No agent running.
        statusView.apply(agents: [
            agent("claude", "Claude", "sparkles", "D97757", "idle", "No agent running", 0),
        ])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        snapshot(statusView, width: StatusView.preferredWidth, file: "render-noagent.png")

        // Self-checks.
        let sweep = stats("render-working-sweep.png")
        let working = stats("render-working.png")
        let noagent = stats("render-noagent.png")
        let sweepBrightness = sweep.full + sweep.mid
        let workingBrightness = working.full + working.mid
        precondition(sweepBrightness - workingBrightness > 60,
                     "shimmer band does not brighten active text enough")
        precondition(noagent.faint > 150, "no-agent text missing")
        print("checks: sweep.band=\(sweepBrightness) working.base=\(workingBrightness) noagent.faint=\(noagent.faint) — PASSED")

        print("RENDER TEST DONE")
    }
}