import Foundation

enum TimelineRestoreGateDiagnostic: String, Equatable, Codable, Sendable {
    case notStarted
    case localInitialWindowQuery
    case initialSnapshotApplying
    case localSnapshotApplying
    case anchorRestoring
    case restoreGate
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
        case invalidAnchorItemKey
        case anchorItemMissing
        case layoutAttributesMissing
        case contentSizeUnavailable
        case targetOffsetClamped
    }

    var kind: Kind
    var anchorItemKey: String?
}

enum TimelineRestoreResult: Equatable, Codable, Sendable {
    case restored
    case skipped(reason: TimelineRestoreFallbackReason)
    case attemptedFallback(reason: TimelineRestoreFallbackReason)
    case failed(reason: TimelineRestoreFallbackReason)

    var fallbackReason: TimelineRestoreFallbackReason? {
        switch self {
        case .restored:
            nil
        case .skipped(let reason), .attemptedFallback(let reason), .failed(let reason):
            reason
        }
    }
}

enum TimelineRestoreGateBudgetResult: String, Equatable, Codable, Sendable {
    case withinBudget
    case overTarget
    case exceededBudget
}

struct TimelineRestoreGateBudget: Equatable, Codable, Sendable {
    var targetDurationMS: Double
    var hardLimitDurationMS: Double

    init(targetDurationMS: Double, hardLimitDurationMS: Double) {
        self.targetDurationMS = targetDurationMS
        self.hardLimitDurationMS = hardLimitDurationMS
    }

    func classify(durationMS: Double?) -> TimelineRestoreGateBudgetResult {
        guard let durationMS else {
            return .withinBudget
        }
        if durationMS <= targetDurationMS {
            return .withinBudget
        }
        if durationMS <= hardLimitDurationMS {
            return .overTarget
        }
        return .exceededBudget
    }

    static let localInitialWindowQuery = TimelineRestoreGateBudget(
        targetDurationMS: 120,
        hardLimitDurationMS: 300
    )
    static let initialSnapshotApply = TimelineRestoreGateBudget(
        targetDurationMS: 80,
        hardLimitDurationMS: 200
    )
    static let anchorRestore = TimelineRestoreGateBudget(
        targetDurationMS: 16,
        hardLimitDurationMS: 50
    )
    static let restoreGate = TimelineRestoreGateBudget(
        targetDurationMS: 250,
        hardLimitDurationMS: 500
    )
}

enum TimelineRestoreGateExceededReason: String, Equatable, Codable, Sendable {
    case localInitialWindowQueryExceededHardLimit
    case initialSnapshotApplyExceededHardLimit
    case anchorRestoreExceededHardLimit
    case restoreGateDurationExceededHardLimit
    case networkWaitedBeforeInteractiveScroll
    case readMarkerChangedDuringRestoreGate
}

enum TimelineRestoreGateFallbackPresentation: String, Equatable, Codable, Sendable {
    case inlineSkeleton
    case emptyState
    case recoverableState
}

struct TimelineRestoreGateMetric: Equatable, Codable, Sendable {
    var stage: TimelineRestoreGateDiagnostic
    var durationMS: Double?
    var timestampMS: Int64
    var exceededBudget: Bool
    var budget: TimelineRestoreGateBudget?
    var budgetResult: TimelineRestoreGateBudgetResult
    var exceededReason: TimelineRestoreGateExceededReason?

    init(
        stage: TimelineRestoreGateDiagnostic,
        durationMS: Double?,
        timestampMS: Int64,
        exceededBudget: Bool,
        budget: TimelineRestoreGateBudget? = nil,
        budgetResult: TimelineRestoreGateBudgetResult = .withinBudget,
        exceededReason: TimelineRestoreGateExceededReason? = nil
    ) {
        self.stage = stage
        self.durationMS = durationMS
        self.timestampMS = timestampMS
        self.exceededBudget = exceededBudget
        self.budget = budget
        self.budgetResult = budgetResult
        self.exceededReason = exceededReason
    }
}

struct TimelineRestoreGateDiagnostics: Equatable, Codable, Sendable {
    var metrics: [TimelineRestoreGateMetric]
    var firstInteractiveScrollAllowedAtMS: Int64
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var fallbackPresentation: TimelineRestoreGateFallbackPresentation?
    var continuesSplash: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool

    init(
        metrics: [TimelineRestoreGateMetric],
        firstInteractiveScrollAllowedAtMS: Int64,
        networkWaitedBeforeInteractiveScrollMS: Double,
        readMarkerChanged: Bool = false,
        fallbackPresentation: TimelineRestoreGateFallbackPresentation? = nil,
        continuesSplash: Bool = false,
        requiresNetworkWork: Bool = false,
        requiresDBWork: Bool = false
    ) {
        self.metrics = metrics
        self.firstInteractiveScrollAllowedAtMS = firstInteractiveScrollAllowedAtMS
        self.networkWaitedBeforeInteractiveScrollMS = networkWaitedBeforeInteractiveScrollMS
        self.readMarkerChanged = readMarkerChanged
        self.fallbackPresentation = fallbackPresentation
        self.continuesSplash = continuesSplash
        self.requiresNetworkWork = requiresNetworkWork
        self.requiresDBWork = requiresDBWork
    }

    var budgetResult: TimelineRestoreGateBudgetResult {
        if metrics.contains(where: { $0.budgetResult == .exceededBudget }) {
            return .exceededBudget
        }
        if metrics.contains(where: { $0.budgetResult == .overTarget }) {
            return .overTarget
        }
        return .withinBudget
    }

    var exceededReasons: [TimelineRestoreGateExceededReason] {
        metrics.compactMap(\.exceededReason)
    }

    var releaseBlockingReasons: [TimelineRestoreGateExceededReason] {
        var reasons: [TimelineRestoreGateExceededReason] = []
        if networkWaitedBeforeInteractiveScrollMS > 0 {
            reasons.append(.networkWaitedBeforeInteractiveScroll)
        }
        if readMarkerChanged {
            reasons.append(.readMarkerChangedDuringRestoreGate)
        }
        return reasons
    }

    var isValidForRelease: Bool {
        releaseBlockingReasons.isEmpty
    }

    func metric(for stage: TimelineRestoreGateDiagnostic) -> TimelineRestoreGateMetric? {
        metrics.first { $0.stage == stage }
    }
}

struct TimelineRestoreGateMetricBuilder: Sendable {
    static func metric(
        stage: TimelineRestoreGateDiagnostic,
        durationMS: Double?,
        budget: TimelineRestoreGateBudget,
        timestampMS: Int64
    ) -> TimelineRestoreGateMetric {
        let result = budget.classify(durationMS: durationMS)
        let exceededReason = result == .exceededBudget ? exceededReason(for: stage) : nil
        return TimelineRestoreGateMetric(
            stage: stage,
            durationMS: durationMS,
            timestampMS: timestampMS,
            exceededBudget: result == .exceededBudget,
            budget: budget,
            budgetResult: result,
            exceededReason: exceededReason
        )
    }

    static func diagnostics(
        localInitialWindowQueryDurationMS: Double,
        initialSnapshotApplyDurationMS: Double,
        anchorRestoreDurationMS: Double,
        restoreGateDurationMS: Double,
        firstInteractiveScrollAllowedAtMS: Int64,
        networkWaitedBeforeInteractiveScrollMS: Double = 0,
        readMarkerChanged: Bool = false,
        fallbackPresentation: TimelineRestoreGateFallbackPresentation? = nil,
        timestampMS: Int64
    ) -> TimelineRestoreGateDiagnostics {
        let metrics = [
            metric(
                stage: .localInitialWindowQuery,
                durationMS: localInitialWindowQueryDurationMS,
                budget: .localInitialWindowQuery,
                timestampMS: timestampMS
            ),
            metric(
                stage: .initialSnapshotApplying,
                durationMS: initialSnapshotApplyDurationMS,
                budget: .initialSnapshotApply,
                timestampMS: timestampMS
            ),
            metric(
                stage: .anchorRestoring,
                durationMS: anchorRestoreDurationMS,
                budget: .anchorRestore,
                timestampMS: timestampMS
            ),
            metric(
                stage: .restoreGate,
                durationMS: restoreGateDurationMS,
                budget: .restoreGate,
                timestampMS: timestampMS
            ),
            TimelineRestoreGateMetric(
                stage: .firstInteractiveScrollReady,
                durationMS: Double(max(0, firstInteractiveScrollAllowedAtMS - timestampMS)),
                timestampMS: firstInteractiveScrollAllowedAtMS,
                exceededBudget: false
            )
        ]

        return TimelineRestoreGateDiagnostics(
            metrics: metrics,
            firstInteractiveScrollAllowedAtMS: firstInteractiveScrollAllowedAtMS,
            networkWaitedBeforeInteractiveScrollMS: networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: readMarkerChanged,
            fallbackPresentation: fallbackPresentation
        )
    }

    private static func exceededReason(
        for stage: TimelineRestoreGateDiagnostic
    ) -> TimelineRestoreGateExceededReason? {
        switch stage {
        case .localInitialWindowQuery:
            .localInitialWindowQueryExceededHardLimit
        case .initialSnapshotApplying, .localSnapshotApplying:
            .initialSnapshotApplyExceededHardLimit
        case .anchorRestoring:
            .anchorRestoreExceededHardLimit
        case .restoreGate:
            .restoreGateDurationExceededHardLimit
        case .notStarted, .firstInteractiveScrollReady:
            nil
        }
    }
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

struct TimelineDiagnosticsExport: Equatable, Codable, Sendable {
    var mutationRecords: [TimelineSnapshotMutationRecord]
    var restoreGateRecords: [TimelineRestoreGateDiagnostic]
    var restoreGateMetrics: [TimelineRestoreGateMetric]
    var restoreGateDiagnostics: [TimelineRestoreGateDiagnostics]

    init(
        mutationRecords: [TimelineSnapshotMutationRecord] = [],
        restoreGateRecords: [TimelineRestoreGateDiagnostic] = [],
        restoreGateMetrics: [TimelineRestoreGateMetric] = [],
        restoreGateDiagnostics: [TimelineRestoreGateDiagnostics] = []
    ) {
        self.mutationRecords = mutationRecords
        self.restoreGateRecords = restoreGateRecords
        self.restoreGateMetrics = restoreGateMetrics
        self.restoreGateDiagnostics = restoreGateDiagnostics
    }
}

final class TimelineDiagnosticsRecorder {
    private(set) var records: [TimelineSnapshotMutationRecord] = []
    private(set) var restoreGateRecords: [TimelineRestoreGateDiagnostic] = []
    private(set) var restoreGateMetrics: [TimelineRestoreGateMetric] = []
    private(set) var restoreGateDiagnostics: [TimelineRestoreGateDiagnostics] = []

    @discardableResult
    func recordMutation(
        reason: TimelineSnapshotReason,
        anchorBefore: TimelineVisualAnchor?,
        anchorAfter: TimelineVisualAnchor?,
        visibleIDsBefore: [TimelineEntryID],
        visibleIDsAfter: [TimelineEntryID],
        fallbackReason: TimelineRestoreFallbackReason? = nil,
        readMarkerChanged: Bool = false,
        timestampMS: Int64 = TimelinePositionRecorder.currentTimeMilliseconds()
    ) -> TimelineSnapshotMutationRecord {
        let record = TimelineSnapshotCoordinator.makeMutationRecord(
            reason: reason,
            anchorBefore: anchorBefore,
            anchorAfter: anchorAfter,
            visibleIDsBefore: visibleIDsBefore,
            visibleIDsAfter: visibleIDsAfter,
            timestampMS: timestampMS,
            fallbackReason: fallbackReason,
            readMarkerChanged: readMarkerChanged
        )
        records.append(record)
        return record
    }

    func recordRestoreGate(_ diagnostic: TimelineRestoreGateDiagnostic) {
        restoreGateRecords.append(diagnostic)
    }

    @discardableResult
    func recordRestoreGateMetric(_ metric: TimelineRestoreGateMetric) -> TimelineRestoreGateMetric {
        restoreGateMetrics.append(metric)
        return metric
    }

    @discardableResult
    func recordRestoreGateDiagnostics(
        _ diagnostics: TimelineRestoreGateDiagnostics
    ) -> TimelineRestoreGateDiagnostics {
        restoreGateDiagnostics.append(diagnostics)
        return diagnostics
    }

    func export() -> TimelineDiagnosticsExport {
        TimelineDiagnosticsExport(
            mutationRecords: records,
            restoreGateRecords: restoreGateRecords,
            restoreGateMetrics: restoreGateMetrics,
            restoreGateDiagnostics: restoreGateDiagnostics
        )
    }
}
