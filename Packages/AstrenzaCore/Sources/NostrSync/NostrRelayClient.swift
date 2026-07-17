import Foundation
import NostrCryptoAPI
import NostrCryptoSecp256k1
import NostrProtocol
import NostrRelay

public protocol NostrRelayFetching: Sendable {
    func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent]
    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String]
}

public struct NostrRelayClient: Sendable {
    public var urlSession: URLSession
    public var timeoutNanoseconds: UInt64
    public var eventValidator: any NostrEventValidating

    public init(
        urlSession: URLSession = .shared,
        timeoutNanoseconds: UInt64 = 7_000_000_000,
        eventValidator: any NostrEventValidating = NostrEventValidator()
    ) {
        self.urlSession = urlSession
        self.timeoutNanoseconds = timeoutNanoseconds
        self.eventValidator = eventValidator
    }

    public func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent] {
        guard let url = URL(string: relayURL) else {
            return []
        }

        let task = urlSession.webSocketTask(with: url)
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        let eventValidator = eventValidator
        let timeoutNanoseconds = timeoutNanoseconds
        return try await withThrowingTaskGroup(of: [NostrEvent].self) { group in
            group.addTask {
                try await Self.receiveEvents(task: task, request: request, eventValidator: eventValidator)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw NostrRelayClientError.timeout
            }

            let result = try await group.next() ?? []
            group.cancelAll()
            task.cancel(with: .goingAway, reason: nil)
            return result
        }
    }

    public func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        guard let url = URL(string: relayURL) else {
            throw NostrRelayClientError.invalidRelayURL(relayURL)
        }

        let task = urlSession.webSocketTask(with: url)
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        let timeoutNanoseconds = timeoutNanoseconds
        return try await withThrowingTaskGroup(of: [String].self) { group in
            group.addTask {
                try await Self.receiveMissingEventIDs(
                    task: task,
                    filter: filter,
                    localEvents: localEvents,
                    subscriptionID: subscriptionID
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw NostrRelayClientError.timeout
            }

            let result = try await group.next() ?? []
            group.cancelAll()
            task.cancel(with: .goingAway, reason: nil)
            return result
        }
    }

    private static func receiveEvents(
        task: URLSessionWebSocketTask,
        request: NostrRelayRequest,
        eventValidator: any NostrEventValidating
    ) async throws -> [NostrEvent] {
        try await task.send(.string(request.textFrame()))
        let collector = NostrRelayEventCollector()

        while true {
            let message = try await task.receive()
            guard case .string(let raw) = message,
                  let relayMessage = NostrRelayMessage.parse(raw)
            else { continue }

            switch relayMessage {
            case .event(let subscriptionID, let event):
                guard subscriptionID == request.subscriptionID, eventValidator.isValid(event) else { continue }
                await collector.append(event)
            case .eose(let subscriptionID):
                guard subscriptionID == request.subscriptionID else { continue }
                return await collector.snapshot()
            case .closed(_, let message):
                if message.lowercased().contains("auth-required") {
                    throw NostrRelayClientError.authRequired(challenge: message)
                }
                if message.lowercased().contains("payment-required") {
                    throw NostrRelayClientError.paymentRequired(message)
                }
                throw NostrRelayClientError.relayClosed(message)
            case .auth(let challenge):
                throw NostrRelayClientError.authRequired(challenge: challenge)
            case .notice, .ok:
                continue
            }
        }
    }

    private static func receiveMissingEventIDs(
        task: URLSessionWebSocketTask,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        let session = try NIP77SyncSession(localEvents: localEvents)
        let openMessage = try session.openMessage(subscriptionID: subscriptionID, filter: filter)
        try await task.send(.string(openMessage.textFrame()))

        var missingIDs: [String] = []
        while true {
            let message = try await task.receive()
            guard case .string(let raw) = message,
                  let relayMessage = NIP77RelayMessage.parse(raw)
            else { continue }

            switch relayMessage {
            case .negMsg(let responseSubscriptionID, let messageHex):
                guard responseSubscriptionID == subscriptionID else { continue }
                let result = try session.reconcile(messageHex)
                missingIDs.append(contentsOf: result.missingEventIDs)
                if let nextMessageHex = result.nextMessageHex {
                    let nextMessage = NIP77ClientMessage.negMsg(
                        subscriptionID: subscriptionID,
                        messageHex: nextMessageHex
                    )
                    try await task.send(.string(nextMessage.textFrame()))
                } else {
                    let closeMessage = try NIP77ClientMessage.negClose(subscriptionID: subscriptionID).textFrame()
                    try await task.send(.string(closeMessage))
                    return Array(Set(missingIDs)).sorted()
                }
            case .negErr(let responseSubscriptionID, let reason):
                guard responseSubscriptionID == subscriptionID else { continue }
                throw NostrRelayClientError.negentropyRelayError(reason)
            }
        }
    }
}

extension NostrRelayClient: NostrRelayFetching {}

private actor NostrRelayEventCollector {
    private var eventsByID: [String: NostrEvent] = [:]

    func append(_ event: NostrEvent) {
        eventsByID[event.id] = event
    }

    func snapshot() -> [NostrEvent] {
        eventsByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
