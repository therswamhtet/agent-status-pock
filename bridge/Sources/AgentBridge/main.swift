import Foundation

let port = UInt16(ProcessInfo.processInfo.environment["AGENTBRIDGE_PORT"] ?? "3939") ?? 3939
let permissionTimeout = TimeInterval(
    ProcessInfo.processInfo.environment["AGENTBRIDGE_TIMEOUT"] ?? "60"
) ?? 60

let hub = AgentHub()
let server = HTTPServer(hub: hub, port: port, permissionTimeout: permissionTimeout)

signal(SIGPIPE, SIG_IGN)

do {
    try server.start()
} catch {
    fputs("[AgentBridge] failed to start: \(error)\n", stderr)
    exit(1)
}

RunLoop.main.run()
