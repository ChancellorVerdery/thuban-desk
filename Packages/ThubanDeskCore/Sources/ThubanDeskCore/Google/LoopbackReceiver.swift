import Foundation
import Network

/// A one-shot HTTP listener on `127.0.0.1:<random port>` that receives Google's OAuth redirect
/// (`GET /?code=…&state=…` or `?error=…`), answers the browser with a short page and hands the query back.
/// Requests without `code` / `error` (favicon, prefetch) get a 404 and are ignored.
public final class LoopbackReceiver: @unchecked Sendable {
    public struct Callback: Sendable, Equatable {
        public var code: String?
        public var state: String?
        public var error: String?
        public var errorDescription: String?
    }

    private let queue = DispatchQueue(label: "com.thuban.desk.loopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Callback, Error>?
    private var pending: Result<Callback, Error>?
    private let successHTML: String

    public init(successHTML: String = LoopbackReceiver.defaultPage) {
        self.successHTML = successHTML
    }

    public static let defaultPage = """
    <!doctype html><html><head><meta charset="utf-8"><title>Thuban Desk</title>
    <style>body{font:16px -apple-system,system-ui,sans-serif;background:#f6f2e8;color:#1d1a14;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
    div{text-align:center}h1{font:600 24px ui-serif,Georgia,serif}</style></head>
    <body><div><h1>You can close this tab.</h1><p>Thuban Desk finished signing in.</p></div></body></html>
    """

    /// Starts listening; returns the redirect URI to register with the authorization request (`http://127.0.0.1:PORT`).
    public func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch { throw ThubanError.oauth("Could not open a local port for sign-in: \(error.localizedDescription)") }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        let port: UInt16 = try await withCheckedThrowingContinuation { (ready: CheckedContinuation<UInt16, Error>) in
            // The handler runs on the serial `queue`; the box only exists to satisfy Sendable checking.
            let resumed = Flag()
            listener.stateUpdateHandler = { state in
                guard !resumed.value else { return }
                switch state {
                case .ready:
                    resumed.value = true
                    ready.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed.value = true
                    ready.resume(throwing: ThubanError.oauth("Local sign-in listener failed: \(error.localizedDescription)"))
                case .cancelled:
                    resumed.value = true
                    ready.resume(throwing: ThubanError.oauth("Sign-in was cancelled."))
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard port != 0 else { throw ThubanError.oauth("Local sign-in listener has no port.") }
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    /// Waits for the redirect (or throws after `timeout` seconds / on `cancel()`).
    public func waitForCallback(timeout: TimeInterval = 300) async throws -> Callback {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish(.failure(ThubanError.oauth("Sign-in timed out. Try again.")))
        }
        defer { timeoutTask.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let pending = self.pending {
                        self.pending = nil
                        continuation.resume(with: pending)
                    } else {
                        self.continuation = continuation
                    }
                }
            }
        } onCancel: { [weak self] in
            self?.cancel()
        }
    }

    public func cancel() {
        finish(.failure(ThubanError.oauth("Sign-in was cancelled.")))
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func finish(_ result: Result<Callback, Error>) {
        queue.async {
            if let continuation = self.continuation {
                self.continuation = nil
                continuation.resume(with: result)
            } else if self.pending == nil {
                self.pending = result
            }
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
            } else if isComplete || error != nil || buffer.count > 65_536 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let target = parts.count >= 2 ? String(parts[1]) : "/"
        let callback = Self.parse(target: target)
        if let callback {
            let body = callback.error == nil ? successHTML : Self.errorPage(callback.errorDescription ?? callback.error ?? "Sign-in failed")
            send(status: "200 OK", body: body, on: connection)
            finish(.success(callback))
        } else {
            send(status: "404 Not Found", body: "Not found", on: connection)
        }
    }

    private func send(status: String, body: String, on connection: NWConnection) {
        let bytes = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bytes)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// `/?code=…&state=…` → callback; nil when the request carries neither `code` nor `error`.
    static func parse(target: String) -> Callback? {
        guard let components = URLComponents(string: "http://127.0.0.1" + (target.hasPrefix("/") ? target : "/" + target)) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("code") != nil || value("error") != nil else { return nil }
        return Callback(code: value("code"), state: value("state"), error: value("error"), errorDescription: value("error_description"))
    }

    private static func errorPage(_ message: String) -> String {
        let escaped = message.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>Thuban Desk</title></head><body style=\"font:16px -apple-system,sans-serif;padding:40px\"><h1>Sign-in did not finish</h1><p>\(escaped)</p><p>Return to Thuban Desk and try again.</p></body></html>"
    }
}

private final class Flag: @unchecked Sendable {
    var value = false
}
