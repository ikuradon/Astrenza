import Foundation
import NostrProtocol

public enum NostrRelayRuntimeError: Error, Equatable, Sendable {
    case connectionUnavailable(relayURL: String)
    case noEligibleRelays(groupIDs: [String])
}

public struct NostrRelayRequestAttempt: Equatable, Sendable {
    public let requestID: String
    public let relayURL: String
    public let packet: NostrREQPacket
    public let startedAt: Int

    public init(requestID: String, relayURL: String, packet: NostrREQPacket, startedAt: Int) {
        self.requestID = requestID
        self.relayURL = relayURL
        self.packet = packet
        self.startedAt = startedAt
    }
}

public enum NostrRelayRequestAttemptEndReason: String, Equatable, Sendable {
    case installFailed
    case cancelled
    case superseded
}

public struct NostrRelayRequestAttemptEnd: Equatable, Sendable {
    public let requestID: String
    public let relayURL: String
    public let subscriptionID: String
    public let reason: NostrRelayRequestAttemptEndReason
    public let message: String?
    public let endedAt: Int

    public init(
        requestID: String,
        relayURL: String,
        subscriptionID: String,
        reason: NostrRelayRequestAttemptEndReason,
        message: String? = nil,
        endedAt: Int
    ) {
        self.requestID = requestID
        self.relayURL = relayURL
        self.subscriptionID = subscriptionID
        self.reason = reason
        self.message = message
        self.endedAt = endedAt
    }
}

public enum NostrRelayClosedDisposition: Equatable, Sendable {
    case retryAfterDelay
    case authenticationRequired
    case terminal

    public init(message: String) {
        let prefix = message
            .lowercased()
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)

        switch prefix {
        case "rate-limited", "error":
            self = .retryAfterDelay
        case "auth-required":
            self = .authenticationRequired
        default:
            self = .terminal
        }
    }
}

public enum NostrRelayConnectionState: String, Codable, Equatable, Sendable {
    case initialized
    case connecting
    case connected
    case waitingForRetry
    case retrying
    case dormant
    case error
    case rejected
    case suspended
    case terminated
}

public enum NostrSubscriptionStrategy: String, Codable, Equatable, Sendable {
    case forward
    case backward
}

public enum NostrREQMergeField: String, Codable, Equatable, Sendable {
    case authors
    case ids
}

public struct NostrREQChunkPolicy: Equatable, Sendable {
    public let maxIDsPerFilter: Int
    public let maxAuthorsPerFilter: Int
    public let maxFiltersPerRequest: Int

    public init(maxIDsPerFilter: Int = 250, maxAuthorsPerFilter: Int = 250, maxFiltersPerRequest: Int = 100) {
        self.maxIDsPerFilter = max(1, maxIDsPerFilter)
        self.maxAuthorsPerFilter = max(1, maxAuthorsPerFilter)
        self.maxFiltersPerRequest = max(1, maxFiltersPerRequest)
    }

    public func limit(for field: NostrREQMergeField) -> Int {
        switch field {
        case .authors:
            maxAuthorsPerFilter
        case .ids:
            maxIDsPerFilter
        }
    }
}

public struct NostrRelayRuntimeRetryPolicy: Equatable, Sendable {
    public let maxAttempts: Int
    public let initialDelayMilliseconds: Int
    public let delayStepMilliseconds: Int
    public let maximumDelayMilliseconds: Int
    public let jitterPercentage: Int

    public init(
        maxAttempts: Int = 5,
        initialDelayMilliseconds: Int = 1_000,
        delayStepMilliseconds: Int = 2_000,
        maximumDelayMilliseconds: Int = 30_000,
        jitterPercentage: Int = 20
    ) {
        self.maxAttempts = max(0, maxAttempts)
        self.initialDelayMilliseconds = max(0, initialDelayMilliseconds)
        self.delayStepMilliseconds = max(0, delayStepMilliseconds)
        self.maximumDelayMilliseconds = max(0, maximumDelayMilliseconds)
        self.jitterPercentage = min(100, max(0, jitterPercentage))
    }

    /// `delayStepMilliseconds`を指数的に増幅し、relay群が同時に再接続しないようjitterを加えます。
    /// `jitterUnit`は0...1で、0.5ならjitterなし、0/1なら許容範囲の下限/上限です。
    public func delayNanoseconds(
        forAttempt attempt: Int,
        jitterUnit: Double = 0.5
    ) -> UInt64 {
        let safeAttempt = max(1, attempt)
        let exponent = min(30, safeAttempt - 1)
        let multiplier = pow(2.0, Double(exponent))
        let exponentialMilliseconds = Double(initialDelayMilliseconds) +
            (Double(delayStepMilliseconds) * (multiplier - 1))
        let cappedMilliseconds = min(
            Double(maximumDelayMilliseconds),
            max(0, exponentialMilliseconds)
        )
        let normalizedJitter = min(1, max(0, jitterUnit))
        let jitterScale = (normalizedJitter * 2) - 1
        let jitterRatio = Double(jitterPercentage) / 100
        let jitteredMilliseconds = cappedMilliseconds * (1 + (jitterScale * jitterRatio))
        let boundedMilliseconds = min(
            Double(maximumDelayMilliseconds),
            max(0, jitteredMilliseconds)
        )
        return UInt64(boundedMilliseconds.rounded()) * 1_000_000
    }

    public func recoveryDelayNanoseconds(
        forAttempt attempt: Int,
        jitterUnit: Double = 0.5
    ) -> UInt64 {
        max(
            delayNanoseconds(forAttempt: attempt, jitterUnit: jitterUnit),
            10_000_000
        )
    }
}

public struct NostrRelayRuntimeHeartbeatPolicy: Equatable, Sendable {
    public let isEnabled: Bool
    public let initialDelayMilliseconds: Int
    public let intervalMilliseconds: Int
    public let reconnectAfterMisses: Int

    public init(
        isEnabled: Bool = true,
        initialDelayMilliseconds: Int = 30_000,
        intervalMilliseconds: Int = 60_000,
        reconnectAfterMisses: Int = 3
    ) {
        self.isEnabled = isEnabled
        self.initialDelayMilliseconds = max(0, initialDelayMilliseconds)
        self.intervalMilliseconds = max(1, intervalMilliseconds)
        self.reconnectAfterMisses = max(1, reconnectAfterMisses)
    }

    public static let disabled = NostrRelayRuntimeHeartbeatPolicy(isEnabled: false)

    public var initialDelayNanoseconds: UInt64 {
        UInt64(initialDelayMilliseconds) * 1_000_000
    }

    public var intervalNanoseconds: UInt64 {
        UInt64(intervalMilliseconds) * 1_000_000
    }
}

public struct NostrRelayRuntimeBackwardPolicy: Equatable, Sendable {
    public let idleTimeoutMilliseconds: Int

    public init(idleTimeoutMilliseconds: Int = 7_000) {
        self.idleTimeoutMilliseconds = max(0, idleTimeoutMilliseconds)
    }

    public static let disabled = NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 0)

    public var isEnabled: Bool {
        idleTimeoutMilliseconds > 0
    }

    public var idleTimeoutNanoseconds: UInt64 {
        UInt64(idleTimeoutMilliseconds) * 1_000_000
    }
}

public enum NostrBackwardREQCompletionStatus: String, Codable, Equatable, Sendable {
    case completed
    case partial
    case closed
    case timedOut
}

public struct NostrBackwardREQCompletion: Codable, Equatable, Sendable {
    public let groupID: String
    public let relayURLs: [String]
    public let subscriptionIDs: [String]
    public let eventCount: Int
    public let eoseCount: Int
    public let closedCount: Int
    public let timeoutCount: Int

    public init(
        groupID: String,
        relayURLs: [String],
        subscriptionIDs: [String],
        eventCount: Int,
        eoseCount: Int,
        closedCount: Int,
        timeoutCount: Int
    ) {
        self.groupID = groupID
        self.relayURLs = relayURLs
        self.subscriptionIDs = subscriptionIDs
        self.eventCount = eventCount
        self.eoseCount = eoseCount
        self.closedCount = closedCount
        self.timeoutCount = timeoutCount
    }

    public var status: NostrBackwardREQCompletionStatus {
        if (timeoutCount > 0 || closedCount > 0) && (eoseCount > 0 || eventCount > 0) {
            return .partial
        }
        if timeoutCount > 0 {
            return .timedOut
        }
        if closedCount > 0 {
            return .closed
        }
        return .completed
    }
}

public struct NostrREQPacket: Equatable, Sendable {
    public let strategy: NostrSubscriptionStrategy
    public let subscriptionID: String
    public let groupID: String
    public let filters: [[String: AnySendableJSON]]
    public let relayURLs: [String]

    public init(
        strategy: NostrSubscriptionStrategy,
        subscriptionID: String,
        groupID: String? = nil,
        filters: [[String: AnySendableJSON]],
        relayURLs: [String] = []
    ) {
        self.strategy = strategy
        self.subscriptionID = subscriptionID
        self.groupID = groupID ?? subscriptionID
        self.filters = filters
        self.relayURLs = relayURLs
    }

    public static func forward(
        subscriptionID: String,
        filters: [[String: AnySendableJSON]],
        relayURLs: [String] = []
    ) -> NostrREQPacket {
        NostrREQPacket(
            strategy: .forward,
            subscriptionID: subscriptionID,
            groupID: subscriptionID,
            filters: filters,
            relayURLs: relayURLs
        )
    }

    public static func backward(
        purpose: String,
        filters: [[String: AnySendableJSON]],
        relayURLs: [String] = [],
        groupID: String? = nil,
        subscriptionID: String? = nil
    ) -> NostrREQPacket {
        let stablePurpose = purpose.isEmpty ? "backward" : purpose
        let packetGroupID = groupID ?? "astrenza-\(stablePurpose)-\(UUID().uuidString)"
        return NostrREQPacket(
            strategy: .backward,
            subscriptionID: subscriptionID ?? "\(packetGroupID)-req",
            groupID: packetGroupID,
            filters: filters,
            relayURLs: relayURLs
        )
    }

    public var relayRequest: NostrRelayRequest {
        NostrRelayRequest(subscriptionID: subscriptionID, filters: filters)
    }

    public func replacing(filters newFilters: [[String: AnySendableJSON]], subscriptionID newSubscriptionID: String? = nil) -> NostrREQPacket {
        NostrREQPacket(
            strategy: strategy,
            subscriptionID: newSubscriptionID ?? subscriptionID,
            groupID: groupID,
            filters: newFilters,
            relayURLs: relayURLs
        )
    }
}

public enum NostrREQScheduler {
    public static func batch(_ packets: [NostrREQPacket], mergeField: NostrREQMergeField) -> [NostrREQPacket] {
        scheduledBatches(packets, mergeField: mergeField).map(\.packet)
    }

    package static func scheduledBatches(
        _ packets: [NostrREQPacket],
        mergeField: NostrREQMergeField
    ) -> [NostrREQScheduledBatch] {
        let grouped = Dictionary(grouping: packets) { packet in
            NostrREQBatchKey(packet: packet, mergeField: mergeField)
        }

        return grouped.values.map { bucket in
            let first = bucket[0]
            let mergedValues = bucket
                .flatMap(\.filters)
                .flatMap { $0.strings(for: mergeField.rawValue) }
                .dedupedSorted()

            let mergedFilters = first.filters.map { filter in
                guard filter[mergeField.rawValue] != nil else {
                    return filter
                }
                return filter.settingStrings(mergedValues, for: mergeField.rawValue)
            }

            return NostrREQScheduledBatch(
                packet: first.replacing(filters: mergedFilters),
                logicalPackets: bucket
            )
        }
        .sorted { lhs, rhs in
            if lhs.packet.strategy.rawValue == rhs.packet.strategy.rawValue {
                return lhs.packet.subscriptionID < rhs.packet.subscriptionID
            }
            return lhs.packet.strategy.rawValue < rhs.packet.strategy.rawValue
        }
    }

    public static func chunk(_ packet: NostrREQPacket, mergeField: NostrREQMergeField, policy: NostrREQChunkPolicy = NostrREQChunkPolicy()) -> [NostrREQPacket] {
        let fieldName = mergeField.rawValue
        var chunkedFilters: [[String: AnySendableJSON]] = []

        for filter in packet.filters {
            let values = filter.strings(for: fieldName).dedupedSorted()
            guard values.count > policy.limit(for: mergeField) else {
                chunkedFilters.append(filter)
                continue
            }

            for slice in values.chunked(size: policy.limit(for: mergeField)) {
                chunkedFilters.append(filter.settingStrings(slice, for: fieldName))
            }
        }

        return chunkedFilters
            .chunked(size: policy.maxFiltersPerRequest)
            .enumerated()
            .map { index, filters in
                let suffix = chunkedFilters.count <= policy.maxFiltersPerRequest ? nil : "-chunk\(index + 1)"
                return packet.replacing(filters: filters, subscriptionID: suffix.map { packet.subscriptionID + $0 })
            }
    }

    public static func forwardChunks(_ packet: NostrREQPacket, policy: NostrREQChunkPolicy = NostrREQChunkPolicy()) -> [NostrREQPacket] {
        let forwardPacket = packet.strategy == .forward ? packet : NostrREQPacket.forward(
            subscriptionID: packet.subscriptionID,
            filters: packet.filters,
            relayURLs: packet.relayURLs
        )
        var filters: [[String: AnySendableJSON]] = []

        for filter in forwardPacket.filters {
            let authors = filter.strings(for: NostrREQMergeField.authors.rawValue).dedupedSorted()
            guard authors.count > policy.maxAuthorsPerFilter else {
                filters.append(filter)
                continue
            }

            for slice in authors.chunked(size: policy.maxAuthorsPerFilter) {
                filters.append(filter.settingStrings(slice, for: NostrREQMergeField.authors.rawValue))
            }
        }

        guard filters.count > 1 else {
            return [forwardPacket.replacing(filters: filters)]
        }

        return filters.enumerated().map { index, filter in
            forwardPacket.replacing(
                filters: [filter],
                subscriptionID: index == 0 ? forwardPacket.subscriptionID : "\(forwardPacket.subscriptionID)-chunk\(index + 1)"
            )
        }
    }
}

package struct NostrREQScheduledBatch: Equatable, Sendable {
    package let packet: NostrREQPacket
    package let logicalPackets: [NostrREQPacket]
}

public enum NostrHomeForwardREQBuilder {
    public static let subscriptionID = "astrenza-home-forward"

    public static func packet(
        authors: [String],
        since: Int?,
        relayURLs: [String] = []
    ) -> NostrREQPacket {
        var filter: [String: AnySendableJSON] = [
            "kinds": .ints([1, 5, 6])
        ]
        let uniqueAuthors = authors.dedupedSorted()
        if !uniqueAuthors.isEmpty {
            filter["authors"] = .strings(uniqueAuthors)
        }
        if let since {
            filter["since"] = .int(since)
        }

        return NostrREQPacket.forward(
            subscriptionID: subscriptionID,
            filters: [filter],
            relayURLs: relayURLs
        )
    }

    public static func reconnectPacket(
        authors: [String],
        newestCreatedAt: Int?,
        overlapSeconds: Int = 10,
        relayURLs: [String] = []
    ) -> NostrREQPacket {
        let since = newestCreatedAt.map { max(0, $0 - max(0, overlapSeconds)) }
        return packet(authors: authors, since: since, relayURLs: relayURLs)
    }
}

public struct NostrEventDependencies: Equatable, Sendable {
    public let profilePubkeys: [String]
    public let sourceEventIDs: [String]
    public let profileRelayURLsByPubkey: [String: [String]]
    public let sourceRelayURLsByEventID: [String: [String]]

    public init(
        profilePubkeys: [String] = [],
        sourceEventIDs: [String] = [],
        profileRelayURLsByPubkey: [String: [String]] = [:],
        sourceRelayURLsByEventID: [String: [String]] = [:]
    ) {
        self.profilePubkeys = profilePubkeys.dedupedSorted()
        self.sourceEventIDs = sourceEventIDs.dedupedSorted()
        self.profileRelayURLsByPubkey = profileRelayURLsByPubkey.mapValues { $0.normalizedRelayHints() }
            .filter { !$0.value.isEmpty }
        self.sourceRelayURLsByEventID = sourceRelayURLsByEventID.mapValues { $0.normalizedRelayHints() }
            .filter { !$0.value.isEmpty }
    }

    public static func extract(from event: NostrEvent) -> NostrEventDependencies {
        var profilePubkeys = [event.pubkey]
        var profileRelayURLsByPubkey: [String: [String]] = [:]
        for tag in event.tags where tag.count >= 2 && tag[0] == "p" {
            let pubkey = tag[1]
            profilePubkeys.append(pubkey)
            if let relayURL = relayHint(from: tag, at: 2) {
                profileRelayURLsByPubkey[pubkey, default: []].append(relayURL)
            }
        }

        var sourceEventIDs: [String] = []
        var sourceRelayURLsByEventID: [String: [String]] = [:]
        if let reply = replyParentReference(from: event.tags) {
            sourceEventIDs.append(reply.eventID)
            if let relayURL = reply.relayURL {
                sourceRelayURLsByEventID[reply.eventID, default: []].append(relayURL)
            }
        }
        if let quote = quotedPostReference(from: event) {
            sourceEventIDs.append(quote.eventID)
            if let relayURL = quote.relayURL {
                sourceRelayURLsByEventID[quote.eventID, default: []].append(relayURL)
            }
        }
        if event.kind == 6, let repost = event.tags.last(where: { $0.count >= 2 && $0[0] == "e" }).map(eventReference) {
            sourceEventIDs.append(repost.eventID)
            if let relayURL = repost.relayURL {
                sourceRelayURLsByEventID[repost.eventID, default: []].append(relayURL)
            }
        }

        let richContent = NostrRichContentParser.parse(event: event)
        for reference in richContent.references {
            switch reference {
            case .profile(let pubkey, let relays):
                profilePubkeys.append(pubkey)
                profileRelayURLsByPubkey[pubkey, default: []].append(contentsOf: relays)
            case .event(let eventID, let relays, let author, _):
                sourceEventIDs.append(eventID)
                sourceRelayURLsByEventID[eventID, default: []].append(contentsOf: relays)
                if let author {
                    profilePubkeys.append(author)
                }
            }
        }

        return NostrEventDependencies(
            profilePubkeys: profilePubkeys,
            sourceEventIDs: sourceEventIDs,
            profileRelayURLsByPubkey: profileRelayURLsByPubkey,
            sourceRelayURLsByEventID: sourceRelayURLsByEventID
        )
    }

    private static func replyParentReference(from tags: [[String]]) -> NostrTaggedEventReference? {
        let replyTag = tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        if let replyTag, replyTag.count >= 2 {
            return eventReference(from: replyTag)
        }

        let eTags = tags.filter { tag in
            tag.count >= 2 && tag[0] == "e"
        }
        let hasMarkedThreadTags = eTags.contains { $0.count >= 4 }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last.map(eventReference)
    }

    private static func quotedPostReference(from event: NostrEvent) -> NostrTaggedEventReference? {
        if let quotedTag = event.tags.last(where: { $0.first == "q" && $0.count >= 2 }) {
            return eventReference(from: quotedTag)
        }
        if let contentReference = nip19EventReference(in: event.content) {
            return NostrTaggedEventReference(eventID: contentReference, relayURL: nil)
        }
        return event.tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "mention"
        }.map(eventReference)
    }

    private static func eventReference(from tag: [String]) -> NostrTaggedEventReference {
        NostrTaggedEventReference(
            eventID: tag.count >= 2 ? tag[1] : "",
            relayURL: relayHint(from: tag, at: 2)
        )
    }

    private static func relayHint(from tag: [String], at index: Int) -> String? {
        guard tag.count > index else { return nil }
        return tag[index].normalizedRelayHint()
    }

    private static func nip19EventReference(in content: String) -> String? {
        content
            .split(whereSeparator: \.isWhitespace)
            .lazy
            .compactMap { token -> String? in
                let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\n"))
                guard trimmed.hasPrefix("note1") || trimmed.hasPrefix("nostr:note1") else { return nil }
                return try? NostrNIP19.eventIDHex(from: trimmed)
            }
            .first
    }
}

private struct NostrTaggedEventReference: Equatable {
    let eventID: String
    let relayURL: String?
}

public enum NostrBackwardREQBuilder {
    public static let heartbeatPurpose = "heartbeat"
    public static let heartbeatID = String(repeating: "0", count: 64)

    public static func heartbeat(
        relayURLs: [String] = [],
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket {
        NostrREQPacket.backward(
            purpose: heartbeatPurpose,
            filters: [["ids": .strings([heartbeatID])]],
            relayURLs: relayURLs,
            groupID: "astrenza-heartbeat-\(requestID)",
            subscriptionID: "astrenza-heartbeat-\(requestID)-req"
        )
    }

    public static func profiles(
        authors: [String],
        relayURLs: [String] = [],
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket? {
        let uniqueAuthors = authors.dedupedSorted()
        guard !uniqueAuthors.isEmpty else { return nil }
        return NostrREQPacket.backward(
            purpose: "kind0",
            filters: [
                [
                    "kinds": .ints([0]),
                    "authors": .strings(uniqueAuthors)
                ]
            ],
            relayURLs: relayURLs,
            groupID: "astrenza-kind0-\(requestID)",
            subscriptionID: "astrenza-kind0-\(requestID)-req"
        )
    }

    public static func sourceEvents(
        ids: [String],
        relayURLs: [String] = [],
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket? {
        let uniqueIDs = ids.dedupedSorted()
        guard !uniqueIDs.isEmpty else { return nil }
        return NostrREQPacket.backward(
            purpose: "source-events",
            filters: [["ids": .strings(uniqueIDs)]],
            relayURLs: relayURLs,
            groupID: "astrenza-source-events-\(requestID)",
            subscriptionID: "astrenza-source-events-\(requestID)-req"
        )
    }

    public static func olderNotes(
        authors: [String],
        until: Int,
        limit: Int,
        relayURLs: [String] = [],
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket? {
        let uniqueAuthors = authors.dedupedSorted()
        guard !uniqueAuthors.isEmpty else { return nil }
        return NostrREQPacket.backward(
            purpose: "older-notes",
            filters: [
                [
                    "kinds": .ints([1, 5, 6]),
                    "authors": .strings(uniqueAuthors),
                    "until": .int(max(0, until)),
                    "limit": .int(max(1, limit))
                ]
            ],
            relayURLs: relayURLs,
            groupID: "astrenza-older-notes-\(requestID)",
            subscriptionID: "astrenza-older-notes-\(requestID)-req"
        )
    }

    public static func notesWindow(
        authors: [String],
        since: Int,
        until: Int,
        limit: Int,
        relayURLs: [String] = [],
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket? {
        let uniqueAuthors = authors.dedupedSorted()
        let safeSince = max(0, since)
        let safeUntil = max(0, until)
        guard !uniqueAuthors.isEmpty, safeSince <= safeUntil else { return nil }
        return NostrREQPacket.backward(
            purpose: "gap-notes",
            filters: [
                [
                    "kinds": .ints([1, 5, 6]),
                    "authors": .strings(uniqueAuthors),
                    "since": .int(safeSince),
                    "until": .int(safeUntil),
                    "limit": .int(max(1, limit))
                ]
            ],
            relayURLs: relayURLs,
            groupID: "astrenza-gap-notes-\(requestID)",
            subscriptionID: "astrenza-gap-notes-\(requestID)-req"
        )
    }
}

private struct NostrREQBatchKey: Hashable {
    let strategy: NostrSubscriptionStrategy
    let relayURLs: [String]
    let filterShapes: [String]

    init(packet: NostrREQPacket, mergeField: NostrREQMergeField) {
        strategy = packet.strategy
        relayURLs = packet.relayURLs
        filterShapes = packet.filters.map { filter in
            filter
                .filter { $0.key != mergeField.rawValue }
                .map { key, value in "\(key)=\(value.stableDescription)" }
                .sorted()
                .joined(separator: "&")
        }
    }
}

private extension Dictionary where Key == String, Value == AnySendableJSON {
    func strings(for key: String) -> [String] {
        guard let value = self[key] else { return [] }
        return value.stringArrayValue
    }

    func settingStrings(_ values: [String], for key: String) -> [String: AnySendableJSON] {
        var copy = self
        copy[key] = .strings(values)
        return copy
    }
}

private extension AnySendableJSON {
    var stableDescription: String {
        switch self {
        case .int(let value):
            "int:\(value)"
        case .string(let value):
            "string:\(value)"
        case .strings(let values):
            "strings:\(values.sorted().joined(separator: ","))"
        case .ints(let values):
            "ints:\(values.sorted().map(String.init).joined(separator: ","))"
        }
    }
}

private extension Array where Element == String {
    func dedupedSorted() -> [String] {
        Array(Set(self)).sorted()
    }

    func normalizedRelayHints() -> [String] {
        compactMap { $0.normalizedRelayHint() }.dedupedSorted()
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map { index in
            Array(self[index..<Swift.min(index + size, count)])
        }
    }
}

private extension String {
    func normalizedRelayHint() -> String? {
        NostrRelayURL(self)?.rawValue
    }
}
