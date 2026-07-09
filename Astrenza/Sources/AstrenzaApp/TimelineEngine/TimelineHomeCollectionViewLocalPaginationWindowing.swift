import Foundation

struct TimelineHomeCollectionViewLocalPaginationWindowingInput: Sendable {
    var launchArguments: [String]
    var routeRestoreDecision: TimelineHomeCollectionViewRouteRestoreDecision
    var visibleAnchorItemKey: String?
    var pages: [TimelineHomeCollectionViewLocalPaginationPage]
}

enum TimelineHomeCollectionViewLocalPaginationPath: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView
}

enum TimelineHomeCollectionViewLocalPaginationDirection: String, Codable, Equatable, Sendable {
    case older
    case newer
}

struct TimelineHomeCollectionViewLocalPaginationRow: Codable, Equatable, Sendable {
    var itemKey: String
    var sortAt: Int64
    var tieBreakID: String
    var pendingNew: Bool
    var hidden: Bool

    init(
        itemKey: String,
        sortAt: Int64,
        tieBreakID: String,
        pendingNew: Bool = false,
        hidden: Bool = false
    ) {
        self.itemKey = itemKey
        self.sortAt = sortAt
        self.tieBreakID = tieBreakID
        self.pendingNew = pendingNew
        self.hidden = hidden
    }
}

struct TimelineHomeCollectionViewLocalPaginationPage: Codable, Equatable, Sendable {
    var direction: TimelineHomeCollectionViewLocalPaginationDirection
    var rows: [TimelineHomeCollectionViewLocalPaginationRow]
}

struct TimelineHomeCollectionViewLocalPaginationSideEffects: Codable, Equatable, Sendable {
    var networkStarted: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var requiresNetworkWork: Bool
    var dbWriteAttempted: Bool
    var requiresDBWrite: Bool
    var readMarkerChanged: Bool
    var readMarkerAdvanced: Bool
    var pendingNewMutated: Bool
    var dataSourceApplyFromRootCalled: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
}

struct TimelineHomeCollectionViewLocalPaginationWindowingResult: Codable, Equatable, Sendable {
    var paginationPath: TimelineHomeCollectionViewLocalPaginationPath
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var usedCollectionViewFlag: Bool
    var localWindowingAllowed: Bool
    var visibleItemKeys: [String]
    var restoredAnchorItemKey: String?
    var visibleAnchorItemKey: String?
    var appendedOlderItemKeys: [String]
    var prependedNewerItemKeys: [String]
    var duplicateItemKeysDeduped: [String]
    var sameSortStableOrderItemKeys: [String]
    var pendingItemKeysExcluded: [String]
    var hiddenItemKeysExcluded: [String]
    var anchorPreservedAfterAppend: Bool
    var anchorPreservedAfterPrepend: Bool
    var emptyPagePreservedVisibleAnchor: Bool
    var restoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var sideEffects: TimelineHomeCollectionViewLocalPaginationSideEffects

    var networkStarted: Bool { sideEffects.networkStarted }
    var networkWaitedBeforeInteractiveScrollMS: Double { sideEffects.networkWaitedBeforeInteractiveScrollMS }
    var requiresNetworkWork: Bool { sideEffects.requiresNetworkWork }
    var dbWriteAttempted: Bool { sideEffects.dbWriteAttempted }
    var requiresDBWrite: Bool { sideEffects.requiresDBWrite }
    var readMarkerChanged: Bool { sideEffects.readMarkerChanged }
    var readMarkerAdvanced: Bool { sideEffects.readMarkerAdvanced }
    var pendingNewMutated: Bool { sideEffects.pendingNewMutated }
    var dataSourceApplyFromRootCalled: Bool { sideEffects.dataSourceApplyFromRootCalled }
    var coordinatorOwnedDataSourceApplyAllowed: Bool { sideEffects.coordinatorOwnedDataSourceApplyAllowed }
}

enum TimelineHomeCollectionViewLocalPaginationWindowingEvaluator {
    static func evaluate(
        _ input: TimelineHomeCollectionViewLocalPaginationWindowingInput
    ) -> TimelineHomeCollectionViewLocalPaginationWindowingResult {
        let decision = input.routeRestoreDecision
        let usedCollectionViewFlag = hasExplicitCollectionViewLaunchFlag(input.launchArguments)
        let routeReady = usedCollectionViewFlag
            && decision.selectedRoute == .collectionView
            && decision.collectionViewRestorePlanBuilt
            && decision.restorePlan != nil

        guard routeReady, let restorePlan = decision.restorePlan else {
            return TimelineHomeCollectionViewLocalPaginationWindowingResult(
                paginationPath: .legacy,
                selectedRoute: decision.selectedRoute,
                usedCollectionViewFlag: usedCollectionViewFlag,
                localWindowingAllowed: false,
                visibleItemKeys: [],
                restoredAnchorItemKey: nil,
                visibleAnchorItemKey: nil,
                appendedOlderItemKeys: [],
                prependedNewerItemKeys: [],
                duplicateItemKeysDeduped: [],
                sameSortStableOrderItemKeys: [],
                pendingItemKeysExcluded: [],
                hiddenItemKeysExcluded: [],
                anchorPreservedAfterAppend: false,
                anchorPreservedAfterPrepend: false,
                emptyPagePreservedVisibleAnchor: false,
                restoreGateScope: nil,
                timelineGateCoversRootShell: false,
                timelineGateCoversTabBar: false,
                timelineGateContinuesGlobalSplash: false,
                sideEffects: sideEffects(from: decision, restorePlan: nil)
            )
        }

        var visibleItemKeys = uniquePreservingOrder(restorePlan.snapshotItemKeys)
        let restoredAnchorItemKey = preservedAnchorItemKey(
            preferredAnchorItemKey: input.visibleAnchorItemKey ?? restorePlan.restoreCandidateItemKey,
            visibleItemKeys: visibleItemKeys
        )
        var visibleAnchorItemKey = restoredAnchorItemKey
        var appendedOlderItemKeys: [String] = []
        var prependedNewerItemKeys: [String] = []
        var duplicateItemKeysDeduped: [String] = []
        var sameSortStableOrderItemKeys: [String] = []
        var pendingItemKeysExcluded: [String] = []
        var hiddenItemKeysExcluded: [String] = []
        var anchorPreservedAfterAppend = false
        var anchorPreservedAfterPrepend = false
        var emptyPagePreservedVisibleAnchor = false
        var seenItemKeys = Set(visibleItemKeys)

        for page in input.pages {
            let previousAnchor = visibleAnchorItemKey
            let previousVisibleItemKeys = visibleItemKeys
            let sortedRows = page.rows.sorted(by: rowSort)
            var acceptedRows: [TimelineHomeCollectionViewLocalPaginationRow] = []

            for row in sortedRows {
                if row.pendingNew {
                    pendingItemKeysExcluded.append(row.itemKey)
                    continue
                }
                if row.hidden {
                    hiddenItemKeysExcluded.append(row.itemKey)
                    continue
                }
                guard seenItemKeys.insert(row.itemKey).inserted else {
                    duplicateItemKeysDeduped.append(row.itemKey)
                    continue
                }
                acceptedRows.append(row)
            }

            let acceptedItemKeys = acceptedRows.map(\.itemKey)
            switch page.direction {
            case .older:
                visibleItemKeys.append(contentsOf: acceptedItemKeys)
                appendedOlderItemKeys.append(contentsOf: acceptedItemKeys)
                anchorPreservedAfterAppend = previousAnchor != nil
                    && previousAnchor == preservedAnchorItemKey(
                        preferredAnchorItemKey: previousAnchor,
                        visibleItemKeys: visibleItemKeys
                    )

            case .newer:
                visibleItemKeys = acceptedItemKeys + visibleItemKeys
                prependedNewerItemKeys.append(contentsOf: acceptedItemKeys)
                anchorPreservedAfterPrepend = previousAnchor != nil
                    && previousAnchor == preservedAnchorItemKey(
                        preferredAnchorItemKey: previousAnchor,
                        visibleItemKeys: visibleItemKeys
                    )
            }

            visibleAnchorItemKey = preservedAnchorItemKey(
                preferredAnchorItemKey: previousAnchor,
                visibleItemKeys: visibleItemKeys
            )
            emptyPagePreservedVisibleAnchor = emptyPagePreservedVisibleAnchor
                || (page.rows.isEmpty
                    && previousVisibleItemKeys == visibleItemKeys
                    && previousAnchor == visibleAnchorItemKey)

            if let stableOrder = sameSortStableOrder(from: acceptedRows), !stableOrder.isEmpty {
                sameSortStableOrderItemKeys = stableOrder
            }
        }

        return TimelineHomeCollectionViewLocalPaginationWindowingResult(
            paginationPath: .collectionView,
            selectedRoute: decision.selectedRoute,
            usedCollectionViewFlag: usedCollectionViewFlag,
            localWindowingAllowed: true,
            visibleItemKeys: visibleItemKeys,
            restoredAnchorItemKey: restoredAnchorItemKey,
            visibleAnchorItemKey: visibleAnchorItemKey,
            appendedOlderItemKeys: appendedOlderItemKeys,
            prependedNewerItemKeys: prependedNewerItemKeys,
            duplicateItemKeysDeduped: uniquePreservingOrder(duplicateItemKeysDeduped),
            sameSortStableOrderItemKeys: sameSortStableOrderItemKeys,
            pendingItemKeysExcluded: uniquePreservingOrder(pendingItemKeysExcluded),
            hiddenItemKeysExcluded: uniquePreservingOrder(hiddenItemKeysExcluded),
            anchorPreservedAfterAppend: anchorPreservedAfterAppend,
            anchorPreservedAfterPrepend: anchorPreservedAfterPrepend,
            emptyPagePreservedVisibleAnchor: emptyPagePreservedVisibleAnchor,
            restoreGateScope: restorePlan.restoreGateScope,
            timelineGateCoversRootShell: restorePlan.timelineGateCoversRootShell,
            timelineGateCoversTabBar: restorePlan.timelineGateCoversTabBar,
            timelineGateContinuesGlobalSplash: restorePlan.timelineGateContinuesGlobalSplash,
            sideEffects: sideEffects(from: decision, restorePlan: restorePlan)
        )
    }

    private static func preservedAnchorItemKey(
        preferredAnchorItemKey: String?,
        visibleItemKeys: [String]
    ) -> String? {
        if let preferredAnchorItemKey, visibleItemKeys.contains(preferredAnchorItemKey) {
            return preferredAnchorItemKey
        }
        return visibleItemKeys.first
    }

    private static func sideEffects(
        from decision: TimelineHomeCollectionViewRouteRestoreDecision,
        restorePlan: TimelineHomeCollectionViewRouteRestorePlan?
    ) -> TimelineHomeCollectionViewLocalPaginationSideEffects {
        TimelineHomeCollectionViewLocalPaginationSideEffects(
            networkStarted: decision.networkStarted,
            networkWaitedBeforeInteractiveScrollMS: decision.networkWaitedBeforeInteractiveScrollMS,
            requiresNetworkWork: decision.requiresNetworkWork,
            dbWriteAttempted: decision.dbWriteAttempted,
            requiresDBWrite: decision.requiresDBWrite,
            readMarkerChanged: decision.readMarkerChanged,
            readMarkerAdvanced: decision.readMarkerAdvanced,
            pendingNewMutated: false,
            dataSourceApplyFromRootCalled: decision.dataSourceApplyFromRootCalled,
            coordinatorOwnedDataSourceApplyAllowed: restorePlan?.coordinatorOwnedDataSourceApplyAllowed ?? false
        )
    }

    private static func rowSort(
        lhs: TimelineHomeCollectionViewLocalPaginationRow,
        rhs: TimelineHomeCollectionViewLocalPaginationRow
    ) -> Bool {
        if lhs.sortAt != rhs.sortAt {
            return lhs.sortAt > rhs.sortAt
        }
        return lhs.tieBreakID < rhs.tieBreakID
    }

    private static func sameSortStableOrder(
        from rows: [TimelineHomeCollectionViewLocalPaginationRow]
    ) -> [String]? {
        let groupedRows = Dictionary(grouping: rows, by: \.sortAt)
        return groupedRows
            .values
            .filter { $0.count > 1 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return (lhs.first?.sortAt ?? .min) > (rhs.first?.sortAt ?? .min)
            }
            .first?
            .sorted(by: rowSort)
            .map(\.itemKey)
    }

    private static func hasExplicitCollectionViewLaunchFlag(_ arguments: [String]) -> Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: arguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func uniquePreservingOrder(_ itemKeys: [String]) -> [String] {
        var seen = Set<String>()
        return itemKeys.filter { seen.insert($0).inserted }
    }
}
