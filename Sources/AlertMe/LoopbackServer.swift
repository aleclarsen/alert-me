import Foundation
import Network

/// A throwaway HTTP listener on 127.0.0.1 used only to catch the OAuth redirect.
/// It accepts a single request, extracts the query parameters, shows the user a
/// "you can close this tab" page, and shuts down.
final class LoopbackServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.alertme.loopback")

    /// Starts listening on an ephemeral port and returns that port number.
    func start(onParams: @escaping ([String: String]) -> Void) throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection, onParams: onParams)
        }

        let ready = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                boundPort = port.rawValue
                ready.signal()
            }
        }
        listener.start(queue: queue)

        if ready.wait(timeout: .now() + 5) == .timedOut {
            throw AuthError.message("Timed out starting loopback server")
        }
        return boundPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection, onParams: @escaping ([String: String]) -> Void) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let params = Self.parseQueryParams(fromRequestLine: request)

            let body = """
            <html><head><meta charset="utf-8"><title>alert-me</title></head>
            <body style="font-family:-apple-system,sans-serif;text-align:center;padding-top:80px">
            <h2>You're connected to alert-me ✅</h2>
            <p>You can close this tab and return to the app.</p>
            </body></html>
            """
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            onParams(params)
        }
    }

    /// Pulls the query string out of the first request line: "GET /?code=...&scope=... HTTP/1.1"
    private static func parseQueryParams(fromRequestLine request: String) -> [String: String] {
        guard let firstLine = request.split(separator: "\r\n").first else { return [:] }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return [:] }
        let path = String(parts[1])
        guard let comps = URLComponents(string: "http://127.0.0.1\(path)") else { return [:] }
        var result: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }
}
