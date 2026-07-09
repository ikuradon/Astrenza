import AstrenzaCore
import Foundation

struct TimelineHomeCollectionViewRestoredRowDisplayQualityInput: Sendable {
    var launchArguments: [String]
    var routeRestoreDecision: TimelineHomeCollectionViewRouteRestoreDecision
    var initialWindow: TimelineRepositoryInitialWindow
}

enum TimelineHomeCollectionViewRestoredRowDisplayPath: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView
}

enum TimelineHomeCollectionViewRestoredRowDisplayKind: String, Codable, Equatable, Sendable {
    case note
    case quoteMissingTarget
    case repostMissingTarget
    case timelineRow
}

enum TimelineHomeCollectionViewRestoredRowTargetState: String, Codable, Equatable, Sendable {
    case notRequired
    case missingTarget
}

struct TimelineHomeCollectionViewRestoredRowDisplayItem: Codable, Equatable, Sendable {
    var displayKey: String
    var kind: TimelineHomeCollectionViewRestoredRowDisplayKind
    var headline: String
    var detail: String
    var targetState: TimelineHomeCollectionViewRestoredRowTargetState
    var safeContentOnly: Bool
}

struct TimelineHomeCollectionViewRestoredRowDisplaySideEffects: Codable, Equatable, Sendable {
    var networkStarted: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var requiresNetworkWork: Bool
    var dbWriteAttempted: Bool
    var requiresDBWrite: Bool
    var readMarkerChanged: Bool
    var readMarkerAdvanced: Bool
    var pendingNewMutated: Bool
    var dataSourceApplyFromRootCalled: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
}

struct TimelineHomeCollectionViewRestoredRowDisplayQualityResult: Codable, Equatable, Sendable {
    var displayPath: TimelineHomeCollectionViewRestoredRowDisplayPath
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var usedCollectionViewFlag: Bool
    var collectionViewRestorePlanBuilt: Bool
    var rows: [TimelineHomeCollectionViewRestoredRowDisplayItem]
    var restorePlanOrderTokens: [String]
    var displayOrderTokens: [String]
    var pendingExcludedCount: Int
    var hiddenExcludedCount: Int
    var sideEffects: TimelineHomeCollectionViewRestoredRowDisplaySideEffects
}

enum TimelineHomeCollectionViewRestoredRowDisplayQualityEvaluator {
    static func evaluate(
        _ input: TimelineHomeCollectionViewRestoredRowDisplayQualityInput
    ) -> TimelineHomeCollectionViewRestoredRowDisplayQualityResult {
        let decision = input.routeRestoreDecision
        let usedCollectionViewFlag = hasExplicitCollectionViewLaunchFlag(input.launchArguments)
        let initialSideEffects = sideEffects(from: decision, pendingNewMutated: false)

        guard usedCollectionViewFlag,
              decision.selectedRoute == .collectionView,
              decision.collectionViewRestorePlanBuilt,
              let restorePlan = decision.restorePlan else {
            return TimelineHomeCollectionViewRestoredRowDisplayQualityResult(
                displayPath: .legacy,
                selectedRoute: decision.selectedRoute,
                usedCollectionViewFlag: usedCollectionViewFlag,
                collectionViewRestorePlanBuilt: false,
                rows: [],
                restorePlanOrderTokens: [],
                displayOrderTokens: [],
                pendingExcludedCount: 0,
                hiddenExcludedCount: 0,
                sideEffects: initialSideEffects
            )
        }

        let rowsByKey = Dictionary(uniqueKeysWithValues: input.initialWindow.rows.map { ($0.itemKey, $0) })
        let restoredRows = restorePlan.snapshotItemKeys.compactMap { rowsByKey[$0] }
        let displayableRows = restoredRows.filter { !$0.pendingNew && $0.hiddenReason == nil }
        let displayRows = displayableRows.enumerated().map { index, row in
            displayItem(for: row, displayKey: "row-\(index + 1)")
        }
        let orderTokens = displayRows.map(\.displayKey)

        return TimelineHomeCollectionViewRestoredRowDisplayQualityResult(
            displayPath: .collectionView,
            selectedRoute: decision.selectedRoute,
            usedCollectionViewFlag: usedCollectionViewFlag,
            collectionViewRestorePlanBuilt: true,
            rows: displayRows,
            restorePlanOrderTokens: orderTokens,
            displayOrderTokens: orderTokens,
            pendingExcludedCount: restorePlan.pendingNewExcludedCount,
            hiddenExcludedCount: restorePlan.hiddenExcludedCount,
            sideEffects: sideEffects(from: decision, pendingNewMutated: restoredRows.contains { $0.pendingNew })
        )
    }

    private static func displayItem(
        for row: TimelineRepositoryFeedItemRow,
        displayKey: String
    ) -> TimelineHomeCollectionViewRestoredRowDisplayItem {
        let kind = displayKind(for: row)
        let targetState: TimelineHomeCollectionViewRestoredRowTargetState = switch kind {
        case .quoteMissingTarget, .repostMissingTarget:
            .missingTarget
        case .note, .timelineRow:
            .notRequired
        }
        let copy = displayCopy(for: kind)

        return TimelineHomeCollectionViewRestoredRowDisplayItem(
            displayKey: displayKey,
            kind: kind,
            headline: copy.headline,
            detail: copy.detail,
            targetState: targetState,
            safeContentOnly: true
        )
    }

    private static func displayKind(
        for row: TimelineRepositoryFeedItemRow
    ) -> TimelineHomeCollectionViewRestoredRowDisplayKind {
        if row.reason == .quote && row.subjectEventID == nil {
            return .quoteMissingTarget
        }
        if row.reason == .repost && row.subjectEventID == nil {
            return .repostMissingTarget
        }
        if row.reason == .author {
            return .note
        }
        return .timelineRow
    }

    private static func displayCopy(
        for kind: TimelineHomeCollectionViewRestoredRowDisplayKind
    ) -> (headline: String, detail: String) {
        switch kind {
        case .note:
            ("Restored note", "Safe local note summary")
        case .quoteMissingTarget:
            ("Quote unavailable", "Original note unavailable")
        case .repostMissingTarget:
            ("Repost unavailable", "Original note unavailable")
        case .timelineRow:
            ("Restored timeline row", "Safe local row summary")
        }
    }

    private static func sideEffects(
        from decision: TimelineHomeCollectionViewRouteRestoreDecision,
        pendingNewMutated: Bool
    ) -> TimelineHomeCollectionViewRestoredRowDisplaySideEffects {
        TimelineHomeCollectionViewRestoredRowDisplaySideEffects(
            networkStarted: decision.networkStarted,
            networkWaitedBeforeInteractiveScrollMS: decision.networkWaitedBeforeInteractiveScrollMS,
            requiresNetworkWork: decision.requiresNetworkWork,
            dbWriteAttempted: decision.dbWriteAttempted,
            requiresDBWrite: decision.requiresDBWrite,
            readMarkerChanged: decision.readMarkerChanged,
            readMarkerAdvanced: decision.readMarkerAdvanced,
            pendingNewMutated: pendingNewMutated,
            dataSourceApplyFromRootCalled: decision.dataSourceApplyFromRootCalled,
            extraNostrHomeTimelineStoreConstructed: !decision.noExtraNostrHomeTimelineStore
        )
    }

    private static func hasExplicitCollectionViewLaunchFlag(_ arguments: [String]) -> Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: arguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }
}
