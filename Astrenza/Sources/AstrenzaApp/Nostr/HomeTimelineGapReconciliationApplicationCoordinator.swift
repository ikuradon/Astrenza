import AstrenzaCore

protocol HomeTimelineGapReconciliationExecuting: Sendable {
    func reconcile(
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext,
        relays: [String],
        inMemoryEvents: [NostrEvent]
    ) async -> HomeTimelineGapReconciliationExecution
}

extension HomeTimelineGapReconciliationCoordinator: HomeTimelineGapReconciliationExecuting {}

struct HomeTimelineGapReconciliationApplicationContext: Sendable {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
    let feedContext: HomeFeedRuntimeContext
}

enum HomeTimelineGapReconciliationApplicationCommand: Equatable, Sendable {
    case incrementRelayStatusRevision
    case recordDiagnostic(HomeTimelineGapReconciliationDiagnostic)
    case reloadProjection(anchorEventID: String)
}

struct HomeTimelineGapReconciliationApplicationHandlers: Sendable {
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineGapReconciliationApplicationCommand
    ) -> Void
    typealias DependencyHandler = @MainActor @Sendable (
        _ event: NostrEvent,
        _ context: HomeTimelineGapReconciliationApplicationContext
    ) async -> Bool

    let perform: CommandHandler
    let resolveDependencies: DependencyHandler
}

@MainActor
final class HomeTimelineGapReconciliationApplicationCoordinator {
    private let reconciliationCoordinator: any HomeTimelineGapReconciliationExecuting
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let timelineRepository: HomeTimelineRepository
    private let projectionController: HomeFeedProjectionController
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator

    private var tasksByReconciliationID: [String: Task<Void, Never>] = [:]

    init(
        reconciliationCoordinator: any HomeTimelineGapReconciliationExecuting,
        contentCoordinator: HomeTimelineContentCoordinator,
        timelineRepository: HomeTimelineRepository,
        projectionController: HomeFeedProjectionController,
        backwardRequestRegistry: HomeTimelineBackwardRequestRegistry,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    ) {
        self.reconciliationCoordinator = reconciliationCoordinator
        self.contentCoordinator = contentCoordinator
        self.timelineRepository = timelineRepository
        self.projectionController = projectionController
        self.backwardRequestRegistry = backwardRequestRegistry
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    var activeTaskCount: Int {
        tasksByReconciliationID.count
    }

    @discardableResult
    func start(
        _ gap: PendingGapBackfill,
        feedContext: HomeFeedRuntimeContext,
        account: NostrAccount,
        handlers: HomeTimelineGapReconciliationApplicationHandlers
    ) -> Bool {
        guard account.pubkey == feedContext.accountID,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey),
              projectionController.isCurrent(
                feedContext,
                accountID: account.pubkey
              )
        else { return false }

        let reconciliationID = backwardRequestRegistry.beginGapReconciliation(
            gap: gap,
            context: feedContext
        )
        guard tasksByReconciliationID[reconciliationID] == nil else {
            return false
        }

        let context = HomeTimelineGapReconciliationApplicationContext(
            account: account,
            lifecycle: lifecycle,
            feedContext: feedContext
        )
        tasksByReconciliationID[reconciliationID] = Task { @MainActor [weak self] in
            await self?.run(
                gap,
                reconciliationID: reconciliationID,
                context: context,
                handlers: handlers
            )
        }
        handlers.perform(.incrementRelayStatusRevision)
        return true
    }

    func cancel() {
        let tasks = tasksByReconciliationID
        tasksByReconciliationID.removeAll()
        for (reconciliationID, task) in tasks {
            backwardRequestRegistry.endGapReconciliation(reconciliationID)
            task.cancel()
        }
    }

    func waitUntilIdle() async {
        while let task = tasksByReconciliationID.values.first {
            await task.value
        }
    }

    private func run(
        _ gap: PendingGapBackfill,
        reconciliationID: String,
        context: HomeTimelineGapReconciliationApplicationContext,
        handlers: HomeTimelineGapReconciliationApplicationHandlers
    ) async {
        defer {
            finish(
                reconciliationID: reconciliationID,
                context: context,
                handlers: handlers
            )
        }

        guard !Task.isCancelled, isCurrent(context) else { return }
        let content = contentCoordinator.snapshot
        guard let newerEvent = timelineEvent(
            id: gap.newerPostID,
            inMemoryEvents: content.noteEvents
        ),
        let olderEvent = timelineEvent(
            id: gap.olderPostID,
            inMemoryEvents: content.noteEvents
        ) else { return }

        let execution = await reconciliationCoordinator.reconcile(
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            gap: gap,
            context: context.feedContext,
            relays: content.resolvedRelays,
            inMemoryEvents: content.noteEvents
        )
        guard !Task.isCancelled, isCurrent(context) else { return }

        for diagnostic in execution.diagnostics {
            handlers.perform(.recordDiagnostic(diagnostic))
        }
        for event in execution.recoveredEvents {
            guard await handlers.resolveDependencies(event, context),
                  !Task.isCancelled,
                  isCurrent(context)
            else { return }
        }

        guard execution.reloadsProjection,
              !Task.isCancelled,
              isCurrent(context)
        else { return }
        handlers.perform(.reloadProjection(anchorEventID: gap.stableAnchorPostID))
    }

    private func finish(
        reconciliationID: String,
        context: HomeTimelineGapReconciliationApplicationContext,
        handlers: HomeTimelineGapReconciliationApplicationHandlers
    ) {
        guard tasksByReconciliationID.removeValue(forKey: reconciliationID) != nil else {
            return
        }
        backwardRequestRegistry.endGapReconciliation(reconciliationID)
        if lifecycleCoordinator.isCurrent(context.lifecycle) {
            handlers.perform(.incrementRelayStatusRevision)
        }
    }

    private func isCurrent(
        _ context: HomeTimelineGapReconciliationApplicationContext
    ) -> Bool {
        lifecycleCoordinator.isCurrent(context.lifecycle) &&
            context.lifecycle.accountID == context.account.pubkey &&
            projectionController.isCurrent(
                context.feedContext,
                accountID: context.account.pubkey
            )
    }

    private func timelineEvent(
        id: String,
        inMemoryEvents: [NostrEvent]
    ) -> NostrEvent? {
        inMemoryEvents.first { $0.id == id } ?? timelineRepository.event(id: id)
    }
}
