import Foundation

struct TimelineHomeCollectionViewScrollInteractionInput: Sendable {
    var launchArguments: [String]
    var routeRestoreDecision: TimelineHomeCollectionViewRouteRestoreDecision
    var events: [TimelineHomeCollectionViewScrollInteractionEvent]
}

enum TimelineHomeCollectionViewScrollInteractionPath: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView
}

enum TimelineHomeCollectionViewScrollInteractionEvent: Equatable, Sendable {
    case userScroll(topVisibleItemKey: String)
    case localRefresh(itemKeys: [String])
    case prependLocalRows(itemKeys: [String])
    case appendLocalRows(itemKeys: [String])
    case reconfigureVisibleRows(itemKeys: [String])
    case emptyRefresh
}

struct TimelineHomeCollectionViewScrollInteractionSideEffects: Codable, Equatable, Sendable {
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

struct TimelineHomeCollectionViewScrollInteractionResult: Codable, Equatable, Sendable {
    var scrollInteractionPath: TimelineHomeCollectionViewScrollInteractionPath
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var usedCollectionViewFlag: Bool
    var collectionViewRestorePlanBuilt: Bool
    var interactiveScrollAllowed: Bool
    var restoredTopVisibleItemKey: String?
    var topVisibleItemKey: String?
    var visibleItemKeys: [String]
    var userScrollUpdatedTopVisibleIdentity: Bool
    var localRefreshPreservedUserScrollAnchor: Bool
    var prependPreservedVisibleAnchor: Bool
    var appendDidNotJumpTopVisibleRow: Bool
    var reconfigureDidNotChangeAnchor: Bool
    var emptyRefreshPreservedEmptyStateWithoutJump: Bool
    var reconfiguredItemKeys: [String]
    var restoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var sideEffects: TimelineHomeCollectionViewScrollInteractionSideEffects
}

enum TimelineHomeCollectionViewScrollInteractionEvaluator {
    static func evaluate(
        _ input: TimelineHomeCollectionViewScrollInteractionInput
    ) -> TimelineHomeCollectionViewScrollInteractionResult {
        let decision = input.routeRestoreDecision
        let usedCollectionViewFlag = hasExplicitCollectionViewLaunchFlag(input.launchArguments)
        let routeReady = usedCollectionViewFlag
            && decision.selectedRoute == .collectionView
            && decision.collectionViewRestorePlanBuilt
            && decision.restorePlan != nil
        guard routeReady, let restorePlan = decision.restorePlan else {
            return TimelineHomeCollectionViewScrollInteractionResult(
                scrollInteractionPath: .legacy,
                selectedRoute: decision.selectedRoute,
                usedCollectionViewFlag: usedCollectionViewFlag,
                collectionViewRestorePlanBuilt: false,
                interactiveScrollAllowed: false,
                restoredTopVisibleItemKey: nil,
                topVisibleItemKey: nil,
                visibleItemKeys: [],
                userScrollUpdatedTopVisibleIdentity: false,
                localRefreshPreservedUserScrollAnchor: false,
                prependPreservedVisibleAnchor: false,
                appendDidNotJumpTopVisibleRow: false,
                reconfigureDidNotChangeAnchor: false,
                emptyRefreshPreservedEmptyStateWithoutJump: false,
                reconfiguredItemKeys: [],
                restoreGateScope: nil,
                timelineGateCoversRootShell: false,
                timelineGateCoversTabBar: false,
                timelineGateContinuesGlobalSplash: false,
                sideEffects: sideEffects(from: decision, restorePlan: nil)
            )
        }

        var visibleItemKeys = uniquePreservingOrder(restorePlan.snapshotItemKeys)
        let restoredTopVisibleItemKey = topVisibleItemKey(
            in: visibleItemKeys,
            preferredItemKey: restorePlan.restoreCandidateItemKey
        )
        var topVisibleItemKey = restoredTopVisibleItemKey
        var userScrollUpdatedTopVisibleIdentity = false
        var localRefreshPreservedUserScrollAnchor = false
        var prependPreservedVisibleAnchor = false
        var appendDidNotJumpTopVisibleRow = false
        var reconfigureDidNotChangeAnchor = false
        var emptyRefreshPreservedEmptyStateWithoutJump = false
        var reconfiguredItemKeys: [String] = []

        for event in input.events {
            switch event {
            case .userScroll(let itemKey):
                let previousTop = topVisibleItemKey
                guard visibleItemKeys.contains(itemKey) else {
                    continue
                }
                topVisibleItemKey = itemKey
                userScrollUpdatedTopVisibleIdentity = previousTop != topVisibleItemKey

            case .localRefresh(let itemKeys):
                let previousTop = topVisibleItemKey
                visibleItemKeys = uniquePreservingOrder(itemKeys)
                topVisibleItemKey = preservedTopVisibleItemKey(previousTop, in: visibleItemKeys)
                localRefreshPreservedUserScrollAnchor = previousTop != nil && topVisibleItemKey == previousTop

            case .prependLocalRows(let itemKeys):
                let previousTop = topVisibleItemKey
                visibleItemKeys = uniquePreservingOrder(itemKeys + visibleItemKeys)
                topVisibleItemKey = preservedTopVisibleItemKey(previousTop, in: visibleItemKeys)
                prependPreservedVisibleAnchor = previousTop != nil && topVisibleItemKey == previousTop

            case .appendLocalRows(let itemKeys):
                let previousTop = topVisibleItemKey
                visibleItemKeys = uniquePreservingOrder(visibleItemKeys + itemKeys)
                topVisibleItemKey = preservedTopVisibleItemKey(previousTop, in: visibleItemKeys)
                appendDidNotJumpTopVisibleRow = previousTop != nil && topVisibleItemKey == previousTop

            case .reconfigureVisibleRows(let itemKeys):
                let previousTop = topVisibleItemKey
                reconfiguredItemKeys = uniquePreservingOrder(itemKeys).filter { visibleItemKeys.contains($0) }
                topVisibleItemKey = preservedTopVisibleItemKey(previousTop, in: visibleItemKeys)
                reconfigureDidNotChangeAnchor = topVisibleItemKey == previousTop

            case .emptyRefresh:
                let wasEmpty = visibleItemKeys.isEmpty && topVisibleItemKey == nil
                visibleItemKeys = []
                topVisibleItemKey = nil
                emptyRefreshPreservedEmptyStateWithoutJump = wasEmpty
            }
        }

        return TimelineHomeCollectionViewScrollInteractionResult(
            scrollInteractionPath: .collectionView,
            selectedRoute: decision.selectedRoute,
            usedCollectionViewFlag: usedCollectionViewFlag,
            collectionViewRestorePlanBuilt: decision.collectionViewRestorePlanBuilt,
            interactiveScrollAllowed: true,
            restoredTopVisibleItemKey: restoredTopVisibleItemKey,
            topVisibleItemKey: topVisibleItemKey,
            visibleItemKeys: visibleItemKeys,
            userScrollUpdatedTopVisibleIdentity: userScrollUpdatedTopVisibleIdentity,
            localRefreshPreservedUserScrollAnchor: localRefreshPreservedUserScrollAnchor,
            prependPreservedVisibleAnchor: prependPreservedVisibleAnchor,
            appendDidNotJumpTopVisibleRow: appendDidNotJumpTopVisibleRow,
            reconfigureDidNotChangeAnchor: reconfigureDidNotChangeAnchor,
            emptyRefreshPreservedEmptyStateWithoutJump: emptyRefreshPreservedEmptyStateWithoutJump,
            reconfiguredItemKeys: reconfiguredItemKeys,
            restoreGateScope: restorePlan.restoreGateScope,
            timelineGateCoversRootShell: restorePlan.timelineGateCoversRootShell,
            timelineGateCoversTabBar: restorePlan.timelineGateCoversTabBar,
            timelineGateContinuesGlobalSplash: restorePlan.timelineGateContinuesGlobalSplash,
            sideEffects: sideEffects(from: decision, restorePlan: restorePlan)
        )
    }

    private static func topVisibleItemKey(
        in itemKeys: [String],
        preferredItemKey: String?
    ) -> String? {
        if let preferredItemKey, itemKeys.contains(preferredItemKey) {
            return preferredItemKey
        }
        return itemKeys.first
    }

    private static func preservedTopVisibleItemKey(
        _ previousTopVisibleItemKey: String?,
        in itemKeys: [String]
    ) -> String? {
        if let previousTopVisibleItemKey, itemKeys.contains(previousTopVisibleItemKey) {
            return previousTopVisibleItemKey
        }
        return itemKeys.first
    }

    private static func sideEffects(
        from decision: TimelineHomeCollectionViewRouteRestoreDecision,
        restorePlan: TimelineHomeCollectionViewRouteRestorePlan?
    ) -> TimelineHomeCollectionViewScrollInteractionSideEffects {
        TimelineHomeCollectionViewScrollInteractionSideEffects(
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
