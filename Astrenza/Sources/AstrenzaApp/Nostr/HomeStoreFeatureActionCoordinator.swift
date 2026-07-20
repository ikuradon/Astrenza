import AstrenzaCore

@MainActor
protocol HomeStoreFeatureActionAccountSourcing: AnyObject {
    func currentAccount() -> NostrAccount?
}

extension HomeTimelinePublishedStateCoordinator:
    HomeStoreFeatureActionAccountSourcing {
    func currentAccount() -> NostrAccount? {
        accountContext.account
    }
}

@MainActor
protocol HomeStoreGapBackfilling: AnyObject {
    func backfill(
        gap: TimelineGap,
        direction: TimelineGapFillDirection,
        context: HomeGapBackfillInteractionContext
    ) async -> Bool
}

extension HomeGapBackfillInteractionWorkflow: HomeStoreGapBackfilling {}

@MainActor
protocol HomeStorePublishing: AnyObject {
    @discardableResult
    func enqueue(
        input: NostrPublishInput,
        taggedUserReadRelays: [String],
        signer: any NostrEventSigning,
        context: HomeTimelinePublishInteractionContext,
        reportProgress: @escaping @MainActor @Sendable (
            HomeTimelinePublishStage
        ) -> Void
    ) async throws -> Bool
}

extension HomeTimelinePublishInteractionWorkflow: HomeStorePublishing {}

@MainActor
protocol HomeStoreLocalMutating: AnyObject {
    func perform(
        _ intent: HomeTimelineLocalMutationIntent,
        context: HomeLocalMutationInteractionContext
    )
}

extension HomeLocalMutationInteractionWorkflow: HomeStoreLocalMutating {}

@MainActor
protocol HomeStoreFiltering: AnyObject {
    @discardableResult
    func perform(
        _ intent: HomeTimelineFilterIntent,
        context: HomeFilterInteractionContext
    ) -> Bool
}

extension HomeTimelineFilterInteractionWorkflow: HomeStoreFiltering {}

@MainActor
protocol HomeStoreFeatureActionContextProviding: AnyObject {
    func gapBackfillContext() -> HomeGapBackfillInteractionContext
    func publishContext(
        account: NostrAccount
    ) -> HomeTimelinePublishInteractionContext
    func localMutationContext() -> HomeLocalMutationInteractionContext
    func filterContext() -> HomeFilterInteractionContext
}

extension HomeStoreContextCoordinator:
    HomeStoreFeatureActionContextProviding {}

@MainActor
final class HomeStoreFeatureActionCoordinator {
    private let accountSource: any HomeStoreFeatureActionAccountSourcing
    private let gapBackfill: any HomeStoreGapBackfilling
    private let publish: (any HomeStorePublishing)?
    private let localMutation: (any HomeStoreLocalMutating)?
    private let filter: any HomeStoreFiltering
    private let contexts: any HomeStoreFeatureActionContextProviding

    init(
        accountSource: any HomeStoreFeatureActionAccountSourcing,
        gapBackfill: any HomeStoreGapBackfilling,
        publish: (any HomeStorePublishing)?,
        localMutation: (any HomeStoreLocalMutating)?,
        filter: any HomeStoreFiltering,
        contexts: any HomeStoreFeatureActionContextProviding
    ) {
        self.accountSource = accountSource
        self.gapBackfill = gapBackfill
        self.publish = publish
        self.localMutation = localMutation
        self.filter = filter
        self.contexts = contexts
    }

    static func live(
        components: HomeTimelineStoreComponents,
        contexts: HomeStoreContextCoordinator
    ) -> HomeStoreFeatureActionCoordinator {
        HomeStoreFeatureActionCoordinator(
            accountSource: components.publishedStateCoordinator,
            gapBackfill: components.gapBackfillInteractionWorkflow,
            publish: components.publishInteractionWorkflow,
            localMutation: components.localMutationInteractionWorkflow,
            filter: components.filterInteractionWorkflow,
            contexts: contexts
        )
    }

    func backfillGap(
        _ gap: TimelineGap,
        direction: TimelineGapFillDirection
    ) async -> Bool {
        await gapBackfill.backfill(
            gap: gap,
            direction: direction,
            context: contexts.gapBackfillContext()
        )
    }

    func enqueuePublish(
        _ input: NostrPublishInput,
        taggedUserReadRelays: [String] = [],
        signer: any NostrEventSigning,
        reportProgress: @escaping @MainActor @Sendable (
            HomeTimelinePublishStage
        ) -> Void = { _ in }
    ) async throws -> Bool {
        guard let account = accountSource.currentAccount(),
              let publish
        else { return false }
        return try await publish.enqueue(
            input: input,
            taggedUserReadRelays: taggedUserReadRelays,
            signer: signer,
            context: contexts.publishContext(account: account),
            reportProgress: reportProgress
        )
    }

    func muteAuthor(authorPubkey: String) {
        guard let localMutation else { return }
        localMutation.perform(
            .muteAuthor(authorPubkey: authorPubkey),
            context: contexts.localMutationContext()
        )
    }

    func bookmark(eventID: String) {
        guard let localMutation else { return }
        localMutation.perform(
            .bookmark(eventID: eventID),
            context: contexts.localMutationContext()
        )
    }

    func suspendFilters() {
        filter.perform(
            .suspend,
            context: contexts.filterContext()
        )
    }

    func resumeFilters() {
        filter.perform(
            .resume,
            context: contexts.filterContext()
        )
    }
}
