import Foundation
import NostrProtocol
import NostrRelay
import NostrReconciliationAPI
import NostrReconciliationNegentropy

public struct NostrHomeFetchPlanner: Sendable {
    public let authors: [String]
    public let pageLimit: Int

    public init(authors: [String], pageLimit: Int = 100) {
        self.authors = authors
        self.pageLimit = max(1, min(pageLimit, 250))
    }

    public func initialRequest(subscriptionID: String) -> NostrRelayRequest {
        request(subscriptionID: subscriptionID)
    }

    public func newerRequest(subscriptionID: String, after createdAt: Int) -> NostrRelayRequest {
        request(subscriptionID: subscriptionID, since: createdAt + 1)
    }

    public func olderRequest(subscriptionID: String, before createdAt: Int) -> NostrRelayRequest {
        request(subscriptionID: subscriptionID, until: max(0, createdAt - 1))
    }

    private func request(subscriptionID: String, since: Int? = nil, until: Int? = nil) -> NostrRelayRequest {
        var filter: [String: AnySendableJSON] = [
            "authors": .strings(authors),
            "kinds": .ints([1]),
            "limit": .int(pageLimit)
        ]
        if let since {
            filter["since"] = .int(since)
        }
        if let until {
            filter["until"] = .int(until)
        }
        return NostrRelayRequest(subscriptionID: subscriptionID, filters: [filter])
    }
}

public struct NostrRelayFilter: Codable, Equatable, Sendable {
    public var kinds: [Int]?
    public var authors: [String]?
    public var since: Int?
    public var until: Int?
    public var limit: Int?

    public init(kinds: [Int]? = nil, authors: [String]? = nil, since: Int? = nil, until: Int? = nil, limit: Int? = nil) {
        self.kinds = kinds
        self.authors = authors
        self.since = since
        self.until = until
        self.limit = limit
    }
}

public enum NIP77ClientMessage: Equatable, Sendable {
    case negOpen(subscriptionID: String, filter: NostrRelayFilter, initialMessageHex: String)
    case negMsg(subscriptionID: String, messageHex: String)
    case negClose(subscriptionID: String)

    public func textFrame() throws -> String {
        let frame: [Any]
        switch self {
        case let .negOpen(subscriptionID, filter, initialMessageHex):
            try Self.validateHex(initialMessageHex)
            let filterObject = try filter.jsonObject()
            frame = ["NEG-OPEN", subscriptionID, filterObject, initialMessageHex]
        case let .negMsg(subscriptionID, messageHex):
            try Self.validateHex(messageHex)
            frame = ["NEG-MSG", subscriptionID, messageHex]
        case let .negClose(subscriptionID):
            frame = ["NEG-CLOSE", subscriptionID]
        }
        let data = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func validateHex(_ value: String) throws {
        guard value.count.isMultiple(of: 2),
              value.isEmpty == false,
              value.allSatisfy({ character in
                  ("0"..."9").contains(character) || ("a"..."f").contains(character) || ("A"..."F").contains(character)
              })
        else {
            throw NIP77RelayMessageError.invalidHex(value)
        }
    }
}

public enum NIP77RelayMessage: Equatable, Sendable {
    case negMsg(subscriptionID: String, messageHex: String)
    case negErr(subscriptionID: String, reason: String)

    public static func parse(_ raw: String) -> NIP77RelayMessage? {
        guard let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = array.first as? String
        else { return nil }

        switch type {
        case "NEG-MSG":
            guard array.count == 3,
                  let subscriptionID = array[1] as? String,
                  let messageHex = array[2] as? String,
                  isHex(messageHex)
            else { return nil }
            return .negMsg(subscriptionID: subscriptionID, messageHex: messageHex)
        case "NEG-ERR":
            guard array.count == 3,
                  let subscriptionID = array[1] as? String,
                  let reason = array[2] as? String
            else { return nil }
            return .negErr(subscriptionID: subscriptionID, reason: reason)
        default:
            return nil
        }
    }

    private static func isHex(_ value: String) -> Bool {
        value.count.isMultiple(of: 2)
            && value.isEmpty == false
            && value.allSatisfy { character in
                ("0"..."9").contains(character) || ("a"..."f").contains(character) || ("A"..."F").contains(character)
            }
    }
}

public enum NIP77RelayMessageError: Error, Equatable {
    case invalidHex(String)
}

public final class NIP77SyncSession {
    private let reconciliationSession: any NostrReconciliationSession

    public init(
        localEvents: [NostrEvent],
        frameSizeLimit: Int = 60_000,
        reconciliationFactory: any NostrReconciliationSessionCreating = NegentropySwiftReconciliationSessionFactory()
    ) throws {
        let records = localEvents.compactMap { event -> NostrReconciliationRecord? in
            guard NostrHex.isLowercaseHex(event.id, byteCount: 32),
                  let idBytes = NostrHex.bytes(fromLowercaseHex: event.id)
            else { return nil }
            return NostrReconciliationRecord(
                timestamp: UInt64(max(0, event.createdAt)),
                id: idBytes
            )
        }
        reconciliationSession = try reconciliationFactory.makeSession(
            records: records,
            frameSizeLimit: frameSizeLimit
        )
    }

    public func openMessage(subscriptionID: String, filter: NostrRelayFilter) throws -> NIP77ClientMessage {
        let initialMessageHex = NostrHex.hexString(try reconciliationSession.initiate())
        return .negOpen(subscriptionID: subscriptionID, filter: filter, initialMessageHex: initialMessageHex)
    }

    public func reconcile(_ relayMessageHex: String) throws -> NIP77ReconcileResult {
        guard let relayMessage = NostrHex.bytes(fromLowercaseHex: relayMessageHex) else {
            throw NIP77RelayMessageError.invalidHex(relayMessageHex)
        }

        let result = try reconciliationSession.reconcile(relayMessage)
        return NIP77ReconcileResult(
            missingEventIDs: result.needIDs.map(NostrHex.hexString),
            nextMessageHex: result.nextMessage.map(NostrHex.hexString)
        )
    }
}

public struct NIP77ReconcileResult: Equatable, Sendable {
    public let missingEventIDs: [String]
    public let nextMessageHex: String?

    public init(missingEventIDs: [String], nextMessageHex: String?) {
        self.missingEventIDs = missingEventIDs
        self.nextMessageHex = nextMessageHex
    }
}

private extension Encodable {
    func jsonObject() throws -> Any {
        let data = try JSONEncoder().encode(self)
        return try JSONSerialization.jsonObject(with: data)
    }
}
