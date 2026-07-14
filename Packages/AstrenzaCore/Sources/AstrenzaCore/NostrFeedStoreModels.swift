import CryptoKit
import Foundation

/// `sortTimestamp DESC, eventID ASC` で並ぶevent列上の安定した位置です。
public struct NostrTimelineEntryCursor: Codable, Equatable, Sendable {
    public let sortTimestamp: Int
    public let eventID: String

    public init(sortTimestamp: Int, eventID: String) {
        self.sortTimestamp = sortTimestamp
        self.eventID = eventID
    }
}

public struct NostrFeedDefinitionRecord: Codable, Equatable, Sendable {
    public let feedID: String
    public let accountID: String
    public let kind: String
    public let specificationJSON: Data
    public let specificationHash: String
    public let sortPolicy: String
    public let revision: Int
    public let createdAt: Int
    public let updatedAt: Int

    public init(
        feedID: String,
        accountID: String,
        kind: String,
        specificationJSON: Data,
        specificationHash: String,
        sortPolicy: String = "created_at_desc",
        revision: Int,
        createdAt: Int,
        updatedAt: Int
    ) {
        self.feedID = feedID
        self.accountID = accountID
        self.kind = kind
        self.specificationJSON = specificationJSON
        self.specificationHash = specificationHash
        self.sortPolicy = sortPolicy
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum NostrFeedProjectionError: Error, Equatable, Sendable {
    case mismatchedFeedID
    case mismatchedRevision
    case sourceWithoutMembership
    case gapWithoutBoundaryMembership
    case missingFeedDefinition
}

public struct NostrFeedMembershipRecord: Codable, Equatable, Sendable {
    public let feedID: String
    /// `nil` は保存時点のactive revisionを表します。
    public let feedRevision: Int?
    public let eventID: String
    public let subjectEventID: String?
    public let sortTimestamp: Int
    public let reason: String
    public let insertedAt: Int

    public init(
        feedID: String,
        eventID: String,
        subjectEventID: String? = nil,
        sortTimestamp: Int,
        reason: String,
        insertedAt: Int,
        feedRevision: Int? = nil
    ) {
        self.feedID = feedID
        self.feedRevision = feedRevision
        self.eventID = eventID
        self.subjectEventID = subjectEventID
        self.sortTimestamp = sortTimestamp
        self.reason = reason
        self.insertedAt = insertedAt
    }
}

/// 1つのmembershipが複数のlistやlocal actionに由来する場合のprovenanceです。
public struct NostrFeedMembershipSourceRecord: Codable, Equatable, Sendable {
    public let feedID: String
    /// `nil` は保存時点のactive revisionを表します。
    public let feedRevision: Int?
    public let eventID: String
    public let sourceType: String
    public let sourceID: String
    public let insertedAt: Int

    public init(
        feedID: String,
        eventID: String,
        sourceType: String,
        sourceID: String,
        insertedAt: Int,
        feedRevision: Int? = nil
    ) {
        self.feedID = feedID
        self.feedRevision = feedRevision
        self.eventID = eventID
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.insertedAt = insertedAt
    }
}

public enum NostrFeedGapState: String, Codable, Equatable, Sendable {
    case unresolved
    case requested
    case resolved
}

/// Feed内で隣接する2 event間の未取得区間です。coverageとは独立して管理します。
public struct NostrFeedGapRecord: Codable, Equatable, Sendable {
    public let feedID: String
    public let feedRevision: Int
    public let newerEventID: String
    public let olderEventID: String
    public let state: NostrFeedGapState
    public let sourceRequestID: String?
    public let createdAt: Int
    public let updatedAt: Int
    public let resolvedAt: Int?

    public init(
        feedID: String,
        feedRevision: Int,
        newerEventID: String,
        olderEventID: String,
        state: NostrFeedGapState,
        sourceRequestID: String? = nil,
        createdAt: Int,
        updatedAt: Int,
        resolvedAt: Int? = nil
    ) {
        self.feedID = feedID
        self.feedRevision = feedRevision
        self.newerEventID = newerEventID
        self.olderEventID = olderEventID
        self.state = state
        self.sourceRequestID = sourceRequestID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
    }
}

public struct NostrDeletedFeedItemRecord: Codable, Equatable, Sendable {
    public let feedID: String
    public let feedRevision: Int
    public let targetEventID: String
    public let deletionEventID: String?
    public let deletedAt: Int
    public let sortTimestamp: Int

    public init(
        feedID: String,
        feedRevision: Int,
        targetEventID: String,
        deletionEventID: String?,
        deletedAt: Int,
        sortTimestamp: Int
    ) {
        self.feedID = feedID
        self.feedRevision = feedRevision
        self.targetEventID = targetEventID
        self.deletionEventID = deletionEventID
        self.deletedAt = deletedAt
        self.sortTimestamp = sortTimestamp
    }
}

/// 1回のDB snapshotから構築したFeed表示windowです。
public struct NostrFeedWindow: Equatable, Sendable {
    public let definition: NostrFeedDefinitionRecord
    public let memberships: [NostrFeedMembershipRecord]
    public let events: [NostrEvent]
    public let deletedItems: [NostrDeletedFeedItemRecord]
    public let gaps: [NostrFeedGapRecord]

    public init(
        definition: NostrFeedDefinitionRecord,
        memberships: [NostrFeedMembershipRecord],
        events: [NostrEvent],
        deletedItems: [NostrDeletedFeedItemRecord],
        gaps: [NostrFeedGapRecord]
    ) {
        self.definition = definition
        self.memberships = memberships
        self.events = events
        self.deletedItems = deletedItems
        self.gaps = gaps
    }
}

public enum NostrFeedSyncProtocol: String, Codable, Equatable, Sendable {
    case req
    case nip77
}

public enum NostrFeedSyncDirection: String, Codable, Equatable, Sendable {
    case forward
    case backward
    case verification
}

public enum NostrFeedSyncPurpose: String, Codable, Equatable, Sendable {
    case initial
    case newer
    case older
    case gap
    case repair
}

public enum NostrFeedSyncEndReason: String, Codable, Equatable, Sendable {
    case completed
    case eose
    case closed
    case timeout
    case installFailed
    case cancelled
    case superseded
}

public enum NostrFeedVerificationOutcome: String, Codable, Equatable, Sendable {
    case noRemoteMissing
    case differencesFound
    case unsupported
    case failed
}

public enum NostrFeedCoverageConfidence: String, Codable, Equatable, Sendable {
    case relayEOSE
    case nip77Verified
}

/// Relayへ実際に送信を開始した1 packetを表します。再接続時の再送も別requestです。
public struct NostrFeedSyncRequestRecord: Codable, Equatable, Sendable {
    public let requestID: String
    public let feedID: String
    public let feedRevision: Int
    public let feedSpecificationHash: String
    public let relayURL: String
    public let subscriptionID: String
    public let syncProtocol: NostrFeedSyncProtocol
    public let direction: NostrFeedSyncDirection
    public let purpose: NostrFeedSyncPurpose
    public let requestedAt: Int
    public let installedAt: Int?
    public let eoseAt: Int?
    public let endedAt: Int?
    public let endReason: NostrFeedSyncEndReason?
    public let endMessage: String?
    public let eventCount: Int
    public let observedOldestPosition: NostrTimelineEntryCursor?
    public let observedNewestPosition: NostrTimelineEntryCursor?
    public let verificationOutcome: NostrFeedVerificationOutcome?
    public let differenceCount: Int?

    public init(
        requestID: String,
        feedID: String,
        feedRevision: Int,
        feedSpecificationHash: String,
        relayURL: String,
        subscriptionID: String,
        syncProtocol: NostrFeedSyncProtocol = .req,
        direction: NostrFeedSyncDirection,
        purpose: NostrFeedSyncPurpose,
        requestedAt: Int,
        installedAt: Int? = nil,
        eoseAt: Int? = nil,
        endedAt: Int? = nil,
        endReason: NostrFeedSyncEndReason? = nil,
        endMessage: String? = nil,
        eventCount: Int = 0,
        observedOldestPosition: NostrTimelineEntryCursor? = nil,
        observedNewestPosition: NostrTimelineEntryCursor? = nil,
        verificationOutcome: NostrFeedVerificationOutcome? = nil,
        differenceCount: Int? = nil
    ) {
        self.requestID = requestID
        self.feedID = feedID
        self.feedRevision = feedRevision
        self.feedSpecificationHash = feedSpecificationHash
        self.relayURL = relayURL
        self.subscriptionID = subscriptionID
        self.syncProtocol = syncProtocol
        self.direction = direction
        self.purpose = purpose
        self.requestedAt = requestedAt
        self.installedAt = installedAt
        self.eoseAt = eoseAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.endMessage = endMessage
        self.eventCount = max(0, eventCount)
        self.observedOldestPosition = observedOldestPosition
        self.observedNewestPosition = observedNewestPosition
        self.verificationOutcome = verificationOutcome
        self.differenceCount = differenceCount
    }
}

/// 1 packet内の実filterです。時間範囲を除いたscopeHashで同じ取得集合を識別します。
public struct NostrFeedSyncFilterRecord: Codable, Equatable, Sendable {
    public let requestID: String
    public let filterIndex: Int
    public let filterJSON: Data
    public let filterHash: String
    public let scopeHash: String
    public let requestedSince: Int?
    public let requestedUntil: Int?
    public let requestedLimit: Int?
    public let hitLimit: Bool

    public init(
        requestID: String,
        filterIndex: Int,
        filterJSON: Data,
        filterHash: String,
        scopeHash: String,
        requestedSince: Int?,
        requestedUntil: Int?,
        requestedLimit: Int?,
        hitLimit: Bool = false
    ) {
        self.requestID = requestID
        self.filterIndex = max(0, filterIndex)
        self.filterJSON = filterJSON
        self.filterHash = filterHash
        self.scopeHash = scopeHash
        self.requestedSince = requestedSince
        self.requestedUntil = requestedUntil
        self.requestedLimit = requestedLimit
        self.hitLimit = hitLimit
    }

    public init(
        requestID: String,
        filterIndex: Int,
        filter: [String: AnySendableJSON]
    ) throws {
        let object = filter.mapValues(\.jsonValue)
        let filterJSON = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var scopeObject = object
        scopeObject["since"] = nil
        scopeObject["until"] = nil
        scopeObject["limit"] = nil
        let scopeJSON = try JSONSerialization.data(withJSONObject: scopeObject, options: [.sortedKeys])
        self.init(
            requestID: requestID,
            filterIndex: filterIndex,
            filterJSON: filterJSON,
            filterHash: Self.sha256Hex(filterJSON),
            scopeHash: Self.sha256Hex(scopeJSON),
            requestedSince: filter["since"]?.intValue,
            requestedUntil: filter["until"]?.intValue,
            requestedLimit: filter["limit"]?.intValue
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// 完全性を確定できた範囲だけを保持します。in-flight/timeout/truncatedはsegmentになりません。
public struct NostrFeedCoverageSegmentRecord: Codable, Equatable, Sendable {
    public let segmentID: String
    public let feedID: String
    public let feedRevision: Int
    public let feedSpecificationHash: String
    public let relayURL: String
    public let scopeHash: String
    public let lowerTimestamp: Int?
    public let upperTimestamp: Int?
    public let snapshotAt: Int
    public let confidence: NostrFeedCoverageConfidence
    public let sourceRequestID: String
    public let createdAt: Int

    public init(
        segmentID: String,
        feedID: String,
        feedRevision: Int,
        feedSpecificationHash: String,
        relayURL: String,
        scopeHash: String,
        lowerTimestamp: Int?,
        upperTimestamp: Int?,
        snapshotAt: Int,
        confidence: NostrFeedCoverageConfidence,
        sourceRequestID: String,
        createdAt: Int
    ) {
        self.segmentID = segmentID
        self.feedID = feedID
        self.feedRevision = feedRevision
        self.feedSpecificationHash = feedSpecificationHash
        self.relayURL = relayURL
        self.scopeHash = scopeHash
        self.lowerTimestamp = lowerTimestamp
        self.upperTimestamp = upperTimestamp
        self.snapshotAt = snapshotAt
        self.confidence = confidence
        self.sourceRequestID = sourceRequestID
        self.createdAt = createdAt
    }
}

/// 次のREQを組み立てるための進捗です。coverageの証明には使用しません。
public struct NostrFeedSyncCheckpointRecord: Codable, Equatable, Sendable {
    public let feedID: String
    public let feedRevision: Int
    public let relayURL: String
    public let scopeHash: String
    public let newestPosition: NostrTimelineEntryCursor?
    public let oldestPosition: NostrTimelineEntryCursor?
    public let lastEOSEAt: Int?
    public let lastVerifiedAt: Int?
    public let updatedAt: Int

    public init(
        feedID: String,
        feedRevision: Int,
        relayURL: String,
        scopeHash: String,
        newestPosition: NostrTimelineEntryCursor?,
        oldestPosition: NostrTimelineEntryCursor?,
        lastEOSEAt: Int?,
        lastVerifiedAt: Int?,
        updatedAt: Int
    ) {
        self.feedID = feedID
        self.feedRevision = feedRevision
        self.relayURL = relayURL
        self.scopeHash = scopeHash
        self.newestPosition = newestPosition
        self.oldestPosition = oldestPosition
        self.lastEOSEAt = lastEOSEAt
        self.lastVerifiedAt = lastVerifiedAt
        self.updatedAt = updatedAt
    }
}

public struct NostrFeedReadStateRecord: Codable, Equatable, Sendable {
    public let feedID: String
    public let viewportAnchorEventID: String?
    public let viewportAnchorOffset: Double
    public let readBoundary: NostrTimelineEntryCursor?
    public let updatedAt: Int
    public let viewportUpdatedAt: Int
    public let readUpdatedAt: Int

    public init(
        feedID: String,
        viewportAnchorEventID: String?,
        viewportAnchorOffset: Double,
        readBoundary: NostrTimelineEntryCursor?,
        updatedAt: Int
    ) {
        self.feedID = feedID
        self.viewportAnchorEventID = viewportAnchorEventID
        self.viewportAnchorOffset = viewportAnchorOffset
        self.readBoundary = readBoundary
        self.updatedAt = updatedAt
        viewportUpdatedAt = updatedAt
        readUpdatedAt = updatedAt
    }

    public init(
        feedID: String,
        viewportAnchorEventID: String?,
        viewportAnchorOffset: Double,
        readBoundary: NostrTimelineEntryCursor?,
        viewportUpdatedAt: Int,
        readUpdatedAt: Int
    ) {
        self.feedID = feedID
        self.viewportAnchorEventID = viewportAnchorEventID
        self.viewportAnchorOffset = viewportAnchorOffset
        self.readBoundary = readBoundary
        self.viewportUpdatedAt = viewportUpdatedAt
        self.readUpdatedAt = readUpdatedAt
        updatedAt = max(viewportUpdatedAt, readUpdatedAt)
    }

    /// V3以前のcall siteを段階移行するための互換initializerです。
    public init(
        feedID: String,
        anchorEventID: String?,
        anchorOffset: Double,
        readPosition: NostrTimelineEntryCursor?,
        updatedAt: Int
    ) {
        self.init(
            feedID: feedID,
            viewportAnchorEventID: anchorEventID,
            viewportAnchorOffset: anchorOffset,
            readBoundary: readPosition,
            updatedAt: updatedAt
        )
    }

    public var anchorEventID: String? { viewportAnchorEventID }
    public var anchorOffset: Double { viewportAnchorOffset }
    public var readPosition: NostrTimelineEntryCursor? { readBoundary }

    private enum CodingKeys: String, CodingKey {
        case feedID
        case viewportAnchorEventID
        case viewportAnchorOffset
        case readBoundary
        case updatedAt
        case viewportUpdatedAt
        case readUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyUpdatedAt = try container.decode(Int.self, forKey: .updatedAt)
        self.init(
            feedID: try container.decode(String.self, forKey: .feedID),
            viewportAnchorEventID: try container.decodeIfPresent(
                String.self,
                forKey: .viewportAnchorEventID
            ),
            viewportAnchorOffset: try container.decode(Double.self, forKey: .viewportAnchorOffset),
            readBoundary: try container.decodeIfPresent(
                NostrTimelineEntryCursor.self,
                forKey: .readBoundary
            ),
            viewportUpdatedAt: try container.decodeIfPresent(
                Int.self,
                forKey: .viewportUpdatedAt
            ) ?? legacyUpdatedAt,
            readUpdatedAt: try container.decodeIfPresent(
                Int.self,
                forKey: .readUpdatedAt
            ) ?? legacyUpdatedAt
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(feedID, forKey: .feedID)
        try container.encodeIfPresent(viewportAnchorEventID, forKey: .viewportAnchorEventID)
        try container.encode(viewportAnchorOffset, forKey: .viewportAnchorOffset)
        try container.encodeIfPresent(readBoundary, forKey: .readBoundary)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(viewportUpdatedAt, forKey: .viewportUpdatedAt)
        try container.encode(readUpdatedAt, forKey: .readUpdatedAt)
    }
}
