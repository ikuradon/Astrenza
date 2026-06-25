import Foundation

enum TimelineRestoreGateDiagnostic: String, Equatable, Codable, Sendable {
    case notStarted
    case localSnapshotApplying
    case anchorRestoring
    case firstInteractiveScrollReady
}

struct TimelineAnchorSnapshot: Equatable, Codable, Sendable {
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
    var capturedAtMS: Int64

    init(anchor: TimelineVisualAnchor) {
        self.anchorItemKey = anchor.anchorItemKey
        self.anchorEventID = anchor.anchorEventID
        self.anchorSortAt = anchor.anchorSortAt
        self.anchorTieBreakID = anchor.anchorTieBreakID
        self.cellTopDeltaFromViewportTop = anchor.cellTopDeltaFromViewportTop
        self.viewportHeight = anchor.viewportHeight
        self.viewportWidth = anchor.viewportWidth
        self.contentInsetTop = anchor.contentInsetTop
        self.contentInsetBottom = anchor.contentInsetBottom
        self.lastVisibleTopItemKey = anchor.lastVisibleTopItemKey
        self.lastVisibleBottomItemKey = anchor.lastVisibleBottomItemKey
        self.capturedAtMS = anchor.capturedAtMS
    }
}

struct TimelineAnchorDelta: Equatable, Codable, Sendable {
    var anchorItemKey: String
    var beforeCellTopDeltaFromViewportTop: Double
    var afterCellTopDeltaFromViewportTop: Double
    var deltaPoints: Double
}

struct TimelineRestoreFallbackReason: Equatable, Codable, Sendable {
    enum Kind: String, Equatable, Codable, Sendable {
        case noSavedAnchor
        case noVisibleItems
        case anchorItemMissing
        case layoutAttributesMissing
        case contentSizeUnavailable
        case targetOffsetClamped
    }

    var kind: Kind
    var anchorItemKey: String?
}

struct TimelineRestoreGateMetric: Equatable, Codable, Sendable {
    var stage: TimelineRestoreGateDiagnostic
    var durationMS: Double?
    var timestampMS: Int64
    var exceededBudget: Bool
}

struct TimelineSnapshotMutationRecord: Equatable, Codable, Sendable {
    var mutationReason: TimelineSnapshotReason
    var anchorBefore: TimelineAnchorSnapshot?
    var anchorAfter: TimelineAnchorSnapshot?
    var anchorDelta: TimelineAnchorDelta?
    var visibleIDsBefore: [TimelineEntryID]
    var visibleIDsAfter: [TimelineEntryID]
    var timestampMS: Int64
    var fallbackReason: TimelineRestoreFallbackReason? = nil
    var readMarkerChanged: Bool = false
}

final class TimelineDiagnosticsRecorder {
    private(set) var records: [TimelineSnapshotMutationRecord] = []
    private(set) var restoreGateRecords: [TimelineRestoreGateDiagnostic] = []
    private(set) var restoreGateMetrics: [TimelineRestoreGateMetric] = []

    func recordMutation(
        reason: TimelineSnapshotReason,
        anchorBefore: TimelineVisualAnchor?,
        anchorAfter: TimelineVisualAnchor?,
        visibleIDsBefore: [TimelineEntryID],
        visibleIDsAfter: [TimelineEntryID],
        fallbackReason: TimelineRestoreFallbackReason? = nil,
        timestampMS: Int64 = TimelinePositionRecorder.currentTimeMilliseconds()
    ) {
        records.append(TimelineSnapshotCoordinator.makeMutationRecord(
            reason: reason,
            anchorBefore: anchorBefore,
            anchorAfter: anchorAfter,
            visibleIDsBefore: visibleIDsBefore,
            visibleIDsAfter: visibleIDsAfter,
            timestampMS: timestampMS,
            fallbackReason: fallbackReason
        ))
    }

    func recordRestoreGate(_ diagnostic: TimelineRestoreGateDiagnostic) {
        restoreGateRecords.append(diagnostic)
    }

    func recordRestoreGateMetric(_ metric: TimelineRestoreGateMetric) {
        restoreGateMetrics.append(metric)
    }
}
