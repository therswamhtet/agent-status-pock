import Foundation

let port = UInt16(ProcessInfo.processInfo.environment["AGENTBRIDGE_PORT"] ?? "3939") ?? 3939

let hub = AgentHub()
let server = HTTPServer(hub: hub, port: port)

signal(SIGPIPE, SIG_IGN)

do {
    try server.start()
} catch {
    fputs("[AgentBridge] failed to start: \(error)\n", stderr)
    exit(1)
}

RunLoop.main.run()