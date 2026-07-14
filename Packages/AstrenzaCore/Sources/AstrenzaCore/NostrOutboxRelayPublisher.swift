import Foundation

public struct NostrOutboxRelayPublishResult: Equatable, Sendable {
    public let relayURL: String
    public let accepted: Bool
    public let message: String?

    public init(relayURL: String, accepted: Bool, message: String?) {
        self.relayURL = relayURL
        self.accepted = accepted
        self.message = message
    }
}

public enum NostrOutboxRelayPublishError: Error, Equatable, Sendable {
    case invalidEventFrame
    case relayClosed(String)
    case authRequired(String)
    case timedOut
}

/// UIやdatabaseの状態を所有せず、署名済みeventをRelayへ送信します。
///
/// 再起動後にも送信処理を復元できるよう、databaseに基づくretry policyは呼び出し側が管理します。
public struct NostrOutboxRelayPublisher: Sendable {
    public typealias TransportFactory = @Sendable (String) -> any NostrRelayTransport

    private let transportFactory: TransportFactory
    private let timeoutNanoseconds: UInt64

    public init(
        transportFactory: @escaping TransportFactory = { _ in NostrURLSessionRelayTransport() },
        timeoutNanoseconds: UInt64 = 7_000_000_000
    ) {
        self.transportFactory = transportFactory
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    public func publish(
        event: NostrEvent,
        relayURLs: [String]
    ) async -> [NostrOutboxRelayPublishResult] {
        await withTaskGroup(of: NostrOutboxRelayPublishResult.self) { group in
            for relayURL in relayURLs {
                group.addTask {
                    await publish(event: event, relayURL: relayURL)
                }
            }

            var results: [NostrOutboxRelayPublishResult] = []
            results.reserveCapacity(relayURLs.count)
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.relayURL < $1.relayURL }
        }
    }

    public func publish(
        event: NostrEvent,
        relayURL: String
    ) async -> NostrOutboxRelayPublishResult {
        let transport = transportFactory(relayURL)
        do {
            let connection = try await transport.connect(relayURL: relayURL)
            do {
                try await connection.send(Self.eventFrame(event))
                let acknowledgement = try await waitForAcknowledgement(
                    eventID: event.id,
                    connection: connection
                )
                await connection.close()
                return NostrOutboxRelayPublishResult(
                    relayURL: relayURL,
                    accepted: acknowledgement.accepted,
                    message: acknowledgement.message
                )
            } catch {
                await connection.close()
                throw error
            }
        } catch {
            return NostrOutboxRelayPublishResult(
                relayURL: relayURL,
                accepted: false,
                message: Self.errorMessage(error)
            )
        }
    }

    private func waitForAcknowledgement(
        eventID: String,
        connection: any NostrRelayTransportConnection
    ) async throws -> Acknowledgement {
        try await withThrowingTaskGroup(of: Acknowledgement?.self) { group in
            group.addTask {
                try await Self.receiveAcknowledgement(eventID: eventID, connection: connection)
            }
            group.addTask {
                if timeoutNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                }
                return nil
            }

            guard let first = try await group.next() else {
                group.cancelAll()
                throw NostrOutboxRelayPublishError.timedOut
            }
            guard let acknowledgement = first else {
                await connection.close()
                group.cancelAll()
                throw NostrOutboxRelayPublishError.timedOut
            }

            group.cancelAll()
            return acknowledgement
        }
    }

    private static func receiveAcknowledgement(
        eventID: String,
        connection: any NostrRelayTransportConnection
    ) async throws -> Acknowledgement {
        while !Task.isCancelled {
            let raw = try await connection.receive()
            guard let data = raw.data(using: .utf8),
                  let frame = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let type = frame.first as? String
            else { continue }

            switch type {
            case "OK":
                guard frame.count == 4,
                      let acknowledgedEventID = frame[1] as? String,
                      acknowledgedEventID == eventID,
                      let accepted = frame[2] as? Bool,
                      let message = frame[3] as? String
                else { continue }
                return Acknowledgement(accepted: accepted, message: message)
            case "AUTH":
                let challenge = frame.count > 1 ? frame[1] as? String : nil
                throw NostrOutboxRelayPublishError.authRequired(challenge ?? "auth-required")
            case "CLOSED", "NOTICE":
                let message = frame.last as? String ?? type
                throw NostrOutboxRelayPublishError.relayClosed(message)
            default:
                continue
            }
        }
        throw CancellationError()
    }

    private static func eventFrame(_ event: NostrEvent) throws -> String {
        let eventData = try JSONEncoder().encode(event)
        let eventObject = try JSONSerialization.jsonObject(with: eventData)
        let frame: [Any] = ["EVENT", eventObject]
        guard JSONSerialization.isValidJSONObject(frame) else {
            throw NostrOutboxRelayPublishError.invalidEventFrame
        }
        let data = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NostrOutboxRelayPublishError.invalidEventFrame
        }
        return text
    }

    private static func errorMessage(_ error: any Error) -> String {
        switch error {
        case NostrOutboxRelayPublishError.invalidEventFrame:
            "invalid event frame"
        case NostrOutboxRelayPublishError.relayClosed(let message):
            message
        case NostrOutboxRelayPublishError.authRequired(let challenge):
            "auth-required: \(challenge)"
        case NostrOutboxRelayPublishError.timedOut:
            "publish timed out"
        case is CancellationError:
            "publish cancelled"
        default:
            String(describing: error)
        }
    }

    private struct Acknowledgement: Sendable {
        let accepted: Bool
        let message: String
    }
}
