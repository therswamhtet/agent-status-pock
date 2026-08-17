import Foundation

// MARK: - HTTP request

struct HTTPRequest {
    var method: String = "GET"
    var path: String = "/"
    var body: Data = Data()

    func jsonBody() -> [String: Any]? {
        guard !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

// MARK: - HTTP server (POSIX sockets, thread-per-connection)

final class HTTPServer: @unchecked Sendable {

    private let hub: AgentHub
    private let port: UInt16
    private let permissionTimeout: TimeInterval
    private var listenFd: Int32 = -1
    private var running = true

    init(hub: AgentHub, port: UInt16, permissionTimeout: TimeInterval) {
        self.hub = hub
        self.port = port
        self.permissionTimeout = permissionTimeout
    }

    func start() throws {
        listenFd = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFd >= 0 else { throw ServerError.socket(errno) }

        var yes: Int32 = 1
        setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw ServerError.bind(errno) }
        guard listen(listenFd, 32) == 0 else { throw ServerError.listen(errno) }

        print("[AgentBridge] listening on http://127.0.0.1:\(port)")

        while running {
            let clientFd = accept(listenFd, nil, nil)
            guard clientFd >= 0 else { continue }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(clientFd)
            }
        }
    }

    func stop() {
        running = false
        if listenFd >= 0 { close(listenFd); listenFd = -1 }
    }

    // MARK: Connection handling

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        guard let request = readRequest(fd) else {
            writeResponse(fd, status: 400, json: ["error": "bad request"])
            return
        }
        route(request, fd: fd)
    }

    private func readRequest(_ fd: Int32) -> HTTPRequest? {
        var buffer = [UInt8](repeating: 0, count: 65536)
        var total = 0
        var headerEnd: Int?

        while total < buffer.count {
            let n = read(fd, &buffer[total], buffer.count - total)
            if n <= 0 { break }
            total += n
            if headerEnd == nil {
                if let range = Data(buffer[0..<total]).range(of: Data("\r\n\r\n".utf8)) {
                    headerEnd = range.endIndex
                    break
                }
            }
        }

        guard total > 0, let headerLength = headerEnd else { return nil }
        let headerData = Data(buffer[0..<headerLength])
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var request = HTTPRequest()
        request.method = String(parts[0]).uppercased()
        request.path = String(parts[1])

        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        if contentLength > 0 {
            var body = Data(buffer[headerLength..<min(total, buffer.count)])
            while body.count < contentLength && body.count < 4_000_000 {
                var chunk = [UInt8](repeating: 0, count: min(65536, contentLength - body.count))
                let n = read(fd, &chunk, chunk.count)
                if n <= 0 { break }
                body.append(contentsOf: chunk[0..<n])
            }
            request.body = body.prefix(contentLength)
        }
        return request
    }

    // MARK: Router

    private func route(_ request: HTTPRequest, fd: Int32) {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path

        switch (request.method, path) {
        case ("GET", "/v1/health"):
            writeResponse(fd, status: 200, json: ["ok": true])

        case ("GET", "/v1/state"):
            let state = hub.snapshot()
            writeResponse(fd, status: 200, encodable: state)

        case ("POST", "/v1/event"):
            guard let body = request.jsonBody() else {
                writeResponse(fd, status: 400, json: ["error": "invalid body"])
                return
            }
            let agent = AgentID(rawValue: body["agent"] as? String ?? "") ?? .claude
            let event = body["event"] as? String ?? ""
            let tool = body["tool"] as? String
            let detail = body["detail"] as? String
            let ts = body["ts"] as? Double
            hub.record(event: event, agent: agent, tool: tool, detail: detail, ts: ts)
            writeResponse(fd, status: 200, json: ["ok": true])

        case ("POST", "/v1/permission"):
            guard let body = request.jsonBody() else {
                writeResponse(fd, status: 400, json: ["error": "invalid body"])
                return
            }
            let agent = AgentID(rawValue: body["agent"] as? String ?? "") ?? .claude
            let tool = body["tool"] as? String ?? "tool"
            let detail = body["detail"] as? String ?? ""
            let cwd = body["cwd"] as? String ?? ""
            var suggestions: [PermissionSuggestion] = []
            if let raw = body["suggestions"] as? [[String: Any]] {
                for item in raw.prefix(3) {
                    guard let label = item["label"] as? String else { continue }
                    let entryJSON = item["entry"] ?? [:]
                    let entryData = (try? JSONSerialization.data(withJSONObject: entryJSON, options: [.sortedKeys])) ?? Data("{}".utf8)
                    suggestions.append(PermissionSuggestion(label: label, entry: String(data: entryData, encoding: .utf8) ?? "{}"))
                }
            }
            let outcome = hub.requestPermission(
                agent: agent, tool: tool, detail: detail, cwd: cwd,
                suggestions: suggestions, timeout: permissionTimeout
            )
            var response: [String: Any] = ["decision": outcome.decision]
            if let ruleIndex = outcome.ruleIndex,
               ruleIndex >= 0, ruleIndex < suggestions.count,
               let entry = suggestions[ruleIndex].entry.data(using: .utf8),
               let entryObject = try? JSONSerialization.jsonObject(with: entry) {
                response["updatedPermissions"] = [entryObject]
            }
            if outcome.decision == "deny" {
                response["message"] = "Denied on Touch Bar"
            }
            writeResponse(fd, status: 200, json: response)

        case ("POST", "/v1/decision"):
            guard let body = request.jsonBody(),
                  let id = body["id"] as? String,
                  let decision = body["decision"] as? String else {
                writeResponse(fd, status: 400, json: ["error": "invalid body"])
                return
            }
            let ruleIndex = body["ruleIndex"] as? Int
            if hub.decide(id: id, decision: decision, ruleIndex: ruleIndex) {
                writeResponse(fd, status: 200, json: ["ok": true])
            } else {
                writeResponse(fd, status: 404, json: ["error": "unknown or expired permission"])
            }

        default:
            writeResponse(fd, status: 404, json: ["error": "not found"])
        }
    }

    // MARK: Response writer

    private func writeResponse(_ fd: Int32, status: Int, json: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [])) ?? Data("{}".utf8)
        write(fd, data: data, status: status)
    }

    private func writeResponse(_ fd: Int32, status: Int, encodable: Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(encodable)) ?? Data("{}".utf8)
        write(fd, data: data, status: status)
    }

    private func write(_ fd: Int32, data: Data, status: Int) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default: reason = "OK"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(data.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(data)
        out.withUnsafeBytes { buffer in
            var sent = 0
            while sent < out.count {
                let n = out[sent...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
                if n <= 0 { break }
                sent += n
            }
        }
    }

    enum ServerError: Error {
        case socket(Int32)
        case bind(Int32)
        case listen(Int32)
    }
}
