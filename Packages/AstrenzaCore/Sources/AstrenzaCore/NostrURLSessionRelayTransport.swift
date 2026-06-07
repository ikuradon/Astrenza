import Foundation

public struct NostrURLSessionRelayTransport: NostrRelayTransport {
    public let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func connect(relayURL: String) async throws -> any NostrRelayTransportConnection {
        guard let url = URL(string: relayURL) else {
            throw NostrRelayClientError.invalidRelayURL(relayURL)
        }
        let task = urlSession.webSocketTask(with: url)
        task.resume()
        return NostrURLSessionRelayTransportConnection(task: task)
    }
}

public final class NostrURLSessionRelayTransportConnection: NostrRelayTransportConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    public func send(_ textFrame: String) async throws {
        try await task.send(.string(textFrame))
    }

    public func receive() async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let value):
            return value
        case .data(let data):
            return String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return ""
        }
    }

    public func close() async {
        task.cancel(with: .goingAway, reason: nil)
    }
}
