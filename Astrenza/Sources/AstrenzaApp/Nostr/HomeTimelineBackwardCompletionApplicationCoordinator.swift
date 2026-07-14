import AstrenzaCore

@MainActor
protocol HomeTimelineBackwardCompletionPersisting: Sendable {
    func markOlderPageBoundaryGap(
        request: PendingBackwardRequest,
        definition: NostrFeedDefinitionRecord
    ) throws -> Bool

    func markGapUnresolved(
        _ gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    )
}

extension HomeTimelineBackfillPersistence: HomeTimelineBackwardCompletionPersisting {}

struct HomeTimelineBackwardCompletionDiagnostic: Equatable, Sendable {
    let relayURL: String
    let message: String
}

enum HomeTimelineBackwardCompletionCommand: Equatable, Sendable {
    case applyContentSnapshot(HomeTimelineContentSnapshot)
    case recordDiagnostic(HomeTimelineBackwardCompletionDiagnostic)
    case reloadProjection(
        anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    )
    case reconcileGap(
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    )
    case incrementRelayStatusRevision
}

@MainActor
final class HomeTimelineBackwardCompletionApplicationCoordinator {
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let projectionController: HomeFeedProjectionController
    private let persistence: any HomeTimelineBackwardCompletionPersisting
    private let planner: HomeTimelineBackwardCompletionPlanner

    init(
        backwardRequestRegistry: HomeTimelineBackwardRequestRegistry,
        dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator,
        contentCoordinator: HomeTimelineContentCoordinator,
        projectionController: HomeFeedProjectionController,
        persistence: any HomeTimelineBackwardCompletionPersisting,
        planner: HomeTimelineBackwardCompletionPlanner = .init()
    ) {
        self.backwardRequestRegistry = backwardRequestRegistry
        self.dependencyCoordinator = dependencyCoordinator
        self.contentCoordinator = contentCoordinator
        self.projectionController = projectionController
        self.persistence = persistence
        self.planner = planner
    }

    func handle(
        _ completion: NostrBackwardREQCompletion,
        accountID: String?
    ) -> [HomeTimelineBackwardCompletionCommand] {
        guard let request = backwardRequestRegistry.remove(groupID: completion.groupID) else {
            return dependencyCoordinator.completeSourceRequest(completion)
                ? [.incrementRelayStatusRevision]
                : []
        }

        let content = contentCoordinator.snapshot
        let plan = planner.plan(.init(
            request: request,
            completion: completion,
            fallbackBottomEventID: content.noteEvents.last?.id,
            isCurrentFeedContext: projectionController.isCurrent(
                request.feedContext,
                accountID: accountID
            )
        ))
        guard plan.acceptsTimelineRequest else {
            return [.incrementRelayStatusRevision]
        }

        var commands: [HomeTimelineBackwardCompletionCommand] = []
        if plan.marksOlderEnd {
            commands.append(.applyContentSnapshot(contentCoordinator.markOlderEnd()))
        }
        if let update = plan.olderPageUpdate, accountID != nil {
            if update.marksBoundaryGap,
               let definition = projectionController.definition {
                do {
                    _ = try persistence.markOlderPageBoundaryGap(
                        request: update.request,
                        definition: definition
                    )
                } catch {
                    commands.append(.recordDiagnostic(
                        HomeTimelineBackwardCompletionDiagnostic(
                            relayURL: content.resolvedRelays.first ?? "runtime",
                            message: "older gap mark failed: \(error.localizedDescription)"
                        )
                    ))
                }
            }
            commands.append(.reloadProjection(
                anchorEventID: update.anchorEventID,
                mergingWithCurrentWindow: true
            ))
        }

        if let gapUpdate = plan.gapUpdate, accountID != nil {
            switch gapUpdate {
            case .reconcile(let gap, let context):
                commands.append(.reconcileGap(gap: gap, context: context))
            case .restore(let gap, let context, let marksUnresolved):
                if marksUnresolved {
                    persistence.markGapUnresolved(gap, context: context)
                }
                // eventなしのtimeout/CLOSEDでも永続化済みgapを再投影する。
                // bootstrap保存と競合するとeventだけのwindowが残る場合があるため。
                commands.append(.reloadProjection(
                    anchorEventID: gap.stableAnchorPostID,
                    mergingWithCurrentWindow: false
                ))
            }
        }
        commands.append(.incrementRelayStatusRevision)
        return commands
    }
}
