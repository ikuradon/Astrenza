import Foundation

struct AccountID: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let debug = AccountID(rawValue: "debug-account")
}

struct EventID: Hashable, Codable, Sendable {
    let hex: String

    init(hex: String) {
        self.hex = hex
    }
}

struct FeedID: Hashable, Codable, Sendable {
    let rawValue: Int64

    init(rawValue: Int64) {
        self.rawValue = rawValue
    }

    static let debugHome = FeedID(rawValue: 0)
}

struct TimelineKey: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let home = TimelineKey(rawValue: "home")
}

struct TimelineEntryID: Codable, Sendable {
    let rawValue: String
    let sourceEventID: EventID?
    let sortAt: Int64?
    let tieBreakID: String?

    init(
        rawValue: String,
        sourceEventID: EventID? = nil,
        sortAt: Int64? = nil,
        tieBreakID: String? = nil
    ) {
        self.rawValue = rawValue
        self.sourceEventID = sourceEventID
        self.sortAt = sortAt
        self.tieBreakID = tieBreakID
    }

    static let debugItems = [
        TimelineEntryID(rawValue: "debug:timeline-engine:001", sortAt: 300, tieBreakID: "001"),
        TimelineEntryID(rawValue: "debug:timeline-engine:002", sortAt: 200, tieBreakID: "002"),
        TimelineEntryID(rawValue: "debug:timeline-engine:003", sortAt: 100, tieBreakID: "003")
    ]
}

extension TimelineEntryID: Hashable {
    static func == (lhs: TimelineEntryID, rhs: TimelineEntryID) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

enum TimelineSection: Hashable, Codable, Sendable {
    case main
}

enum ResolveApplyReason: Equatable, Codable, Sendable {
    case profile
    case media
    case linkPreview
    case repost
    case quote
    case replyParent
    case stats
    case visibility
    case debug

    var snapshotReason: TimelineSnapshotReason {
        .reconfigure(self)
    }
}

enum TimelineSnapshotReason: Equatable, Codable, Sendable {
    case initialRestore
    case userInsertedPendingNew
    case olderPageLoaded
    case gapFilled
    case reconfigure(ResolveApplyReason)
    case filterChanged
    case accountSwitched
    case timelineSwitched
    case debugReload

    var advancesReadMarker: Bool {
        false
    }
}

struct TimelineVisualAnchor: Codable, Equatable, Sendable {
    var accountID: AccountID
    var feedID: FeedID
    var timelineKey: TimelineKey
    var anchorItemKey: String
    var anchorEventID: EventID?
    var anchorSortAt: Int64
    var anchorTieBreakID: String
    var cellTopDeltaFromViewportTop: Double
    var viewportHeight: Double
    var viewportWidth: Double
    var contentInsetTop: Double
    var contentInsetBottom: Double
    var lastVisibleTopItemKey: String?
    var lastVisibleBottomItemKey: String?
    var markerEventID: EventID?
    var markerSortAt: Int64?
    var capturedAtMS: Int64
    var schemaVersion: Int
}

enum TimelineMutationStyle: String, Equatable, Codable, Sendable {
    case snapshot
    case reconfigure
}

struct TimelineSnapshotMutationPlan: Equatable, Sendable {
    var reason: TimelineSnapshotReason
    var mutationStyle: TimelineMutationStyle
    var itemIDs: [TimelineEntryID]
    var reconfigureIDs: [TimelineEntryID]
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
}
