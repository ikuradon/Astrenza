import Foundation

enum TimelineRestoreGateDiagnostic: String, Equatable, Codable, Sendable {
    case notStarted
    case localSnapshotApplying
    case anchorRestoring
    case firstInteractiveScrollReady
}

struct TimelineDiagnosticsRecord: Equatable, Sendable {
    var mutationReason: TimelineSnapshotReason
    var anchorBefore: TimelineVisualAnchor?
    var anchorAfter: TimelineVisualAnchor?
    var anchorDelta: Double?
    var visibleIDsBefore: [TimelineEntryID]
    var visibleIDsAfter: [TimelineEntryID]
    var restoreGate: TimelineRestoreGateDiagnostic?
    var capturedAtMS: Int64
}

final class TimelineDiagnosticsRecorder {
    private(set) var records: [TimelineDiagnosticsRecord] = []
    private(set) var restoreGateRecords: [TimelineRestoreGateDiagnostic] = []

    func recordMutation(
        reason: TimelineSnapshotReason,
        anchorBefore: TimelineVisualAnchor?,
        anchorAfter: TimelineVisualAnchor?,
        visibleIDsBefore: [TimelineEntryID],
        visibleIDsAfter: [TimelineEntryID],
        restoreGate: TimelineRestoreGateDiagnostic? = nil
    ) {
        records.append(TimelineDiagnosticsRecord(
            mutationReason: reason,
            anchorBefore: anchorBefore,
            anchorAfter: anchorAfter,
            anchorDelta: TimelinePositionRecorder.anchorDelta(before: anchorBefore, after: anchorAfter),
            visibleIDsBefore: visibleIDsBefore,
            visibleIDsAfter: visibleIDsAfter,
            restoreGate: restoreGate,
            capturedAtMS: TimelinePositionRecorder.currentTimeMilliseconds()
        ))
    }

    func recordRestoreGate(_ diagnostic: TimelineRestoreGateDiagnostic) {
        restoreGateRecords.append(diagnostic)
    }
}
