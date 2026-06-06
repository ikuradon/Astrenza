import Foundation

public enum NostrRelayClientError: Error {
    case invalidRelayURL(String)
    case negentropyRelayError(String)
}

public enum NostrRelayMessage: Equatable {
    case event(subscriptionID: String, event: NostrEvent)
    case eose(subscriptionID: String)
    case closed(subscriptionID: String, message: String)
    case notice(String)
    case auth(String)

    public static func parse(_ raw: String) -> NostrRelayMessage? {
        guard let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = array.first as? String
        else { return nil }

        switch type {
        case "EVENT":
            guard array.count == 3,
                  let subscriptionID = array[1] as? String,
                  let object = array[2] as? [String: Any],
                  let event = decodeEvent(object)
            else { return nil }
            return .event(subscriptionID: subscriptionID, event: event)
        case "EOSE":
            guard array.count == 2, let subscriptionID = array[1] as? String else { return nil }
            return .eose(subscriptionID: subscriptionID)
        case "CLOSED":
            guard array.count == 3,
                  let subscriptionID = array[1] as? String,
                  let message = array[2] as? String
            else { return nil }
            return .closed(subscriptionID: subscriptionID, message: message)
        case "NOTICE":
            guard array.count == 2, let message = array[1] as? String else { return nil }
            return .notice(message)
        case "AUTH":
            guard array.count == 2, let challenge = array[1] as? String else { return nil }
            return .auth(challenge)
        default:
            return nil
        }
    }

    private static func decodeEvent(_ object: [String: Any]) -> NostrEvent? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let event = try? JSONDecoder().decode(NostrEvent.self, from: data)
        else { return nil }
        return event
    }
}

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
    public var eventValidator: NostrEventValidator

    public init(
        urlSession: URLSession = .shared,
        timeoutNanoseconds: UInt64 = 7_000_000_000,
        eventValidator: NostrEventValidator = NostrEventValidator()
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
                return []
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
                return []
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
        eventValidator: NostrEventValidator
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
            case .closed, .notice, .auth:
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
