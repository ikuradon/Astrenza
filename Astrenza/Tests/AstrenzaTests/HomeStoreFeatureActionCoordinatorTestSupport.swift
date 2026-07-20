import AstrenzaCore
@testable import Astrenza

@MainActor
final class StoreFeatureActionAccountSourceSpy:
    HomeStoreFeatureActionAccountSourcing {
    var accountValue: NostrAccount?
    private(set) var readCount = 0

    init(account: NostrAccount?) {
        accountValue = account
    }

    func currentAccount() -> NostrAccount? {
        readCount += 1
        return accountValue
    }
}

@MainActor
final class StoreFeatureActionGapBackfillSpy: HomeStoreGapBackfilling {
    struct Call: Equatable {
        let gapID: String
        let direction: TimelineGapFillDirection
        let accountID: String?
        let hasRelayRuntime: Bool
        let resolvedRelays: [String]
    }

    var result = true
    private(set) var calls: [Call] = []

    func backfill(
        gap: TimelineGap,
        direction: TimelineGapFillDirection,
        context: HomeGapBackfillInteractionContext
    ) async -> Bool {
        calls.append(Call(
            gapID: gap.id,
            direction: direction,
            accountID: context.state.account?.pubkey,
            hasRelayRuntime: context.state.hasRelayRuntime,
            resolvedRelays: context.state.resolvedRelays
        ))
        return result
    }
}

@MainActor
final class StoreFeatureActionPublishSpy: HomeStorePublishing {
    enum Failure: Error, Equatable {
        case publish
    }

    struct Call: Equatable {
        let input: NostrPublishInput
        let state: HomeTimelinePublishInteractionState
        let receivedExpectedSigner: Bool
    }

    var failure: Failure?
    private(set) var calls: [Call] = []

    @discardableResult
    func enqueue(
        input: NostrPublishInput,
        taggedUserReadRelays: [String],
        signer: any NostrEventSigning,
        context: HomeTimelinePublishInteractionContext,
        reportProgress: @escaping @MainActor @Sendable (
            HomeTimelinePublishStage
        ) -> Void
    ) async throws -> Bool {
        _ = (taggedUserReadRelays, reportProgress)
        calls.append(Call(
            input: input,
            state: context.state,
            receivedExpectedSigner:
                signer is StoreFeatureActionSigner
        ))
        if let failure {
            throw failure
        }
        return true
    }
}

actor StoreFeatureActionSigner: NostrEventSigning {
    func sign(_ unsignedEvent: NostrUnsignedEvent) async throws -> NostrEvent {
        NostrEvent(
            id: unsignedEvent.eventID,
            pubkey: unsignedEvent.pubkey,
            createdAt: unsignedEvent.createdAt,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            content: unsignedEvent.content,
            sig: String(repeating: "1", count: 128)
        )
    }
}

@MainActor
final class StoreFeatureActionLocalMutationSpy: HomeStoreLocalMutating {
    struct Call: Equatable {
        let intent: HomeTimelineLocalMutationIntent
        let accountID: String?
    }

    private(set) var calls: [Call] = []

    func perform(
        _ intent: HomeTimelineLocalMutationIntent,
        context: HomeLocalMutationInteractionContext
    ) {
        calls.append(Call(
            intent: intent,
            accountID: context.state.accountID
        ))
    }
}

@MainActor
final class StoreFeatureActionFilterSpy: HomeStoreFiltering {
    private(set) var intents: [HomeTimelineFilterIntent] = []

    @discardableResult
    func perform(
        _ intent: HomeTimelineFilterIntent,
        context _: HomeFilterInteractionContext
    ) -> Bool {
        intents.append(intent)
        return true
    }
}

@MainActor
final class StoreFeatureActionContextProviderSpy:
    HomeStoreFeatureActionContextProviding {
    enum Read: Equatable {
        case gapBackfill
        case publish(accountID: String)
        case localMutation
        case filter
    }

    private let coordinator: HomeStoreContextCoordinator
    private(set) var reads: [Read] = []

    init(coordinator: HomeStoreContextCoordinator) {
        self.coordinator = coordinator
    }

    func gapBackfillContext() -> HomeGapBackfillInteractionContext {
        reads.append(.gapBackfill)
        return coordinator.gapBackfillContext()
    }

    func publishContext(
        account: NostrAccount
    ) -> HomeTimelinePublishInteractionContext {
        reads.append(.publish(accountID: account.pubkey))
        return coordinator.publishContext(account: account)
    }

    func localMutationContext() -> HomeLocalMutationInteractionContext {
        reads.append(.localMutation)
        return coordinator.localMutationContext()
    }

    func filterContext() -> HomeFilterInteractionContext {
        reads.append(.filter)
        return coordinator.filterContext()
    }
}

@MainActor
struct StoreFeatureActionCoordinatorFixture {
    let contextFixture: StoreContextCoordinatorFixture
    let accountSource: StoreFeatureActionAccountSourceSpy
    let gapBackfill = StoreFeatureActionGapBackfillSpy()
    let publish = StoreFeatureActionPublishSpy()
    let localMutation = StoreFeatureActionLocalMutationSpy()
    let filter = StoreFeatureActionFilterSpy()
    let contexts: StoreFeatureActionContextProviderSpy
    let coordinator: HomeStoreFeatureActionCoordinator

    init(
        hasPublish: Bool = true,
        hasLocalMutation: Bool = true
    ) {
        let contextFixture = StoreContextCoordinatorFixture()
        contextFixture.installSnapshots()
        let accountSource = StoreFeatureActionAccountSourceSpy(
            account: contextFixture.account
        )
        let contexts = StoreFeatureActionContextProviderSpy(
            coordinator: contextFixture.coordinator
        )
        let publishBoundary: (any HomeStorePublishing)? =
            hasPublish ? publish : nil
        let localMutationBoundary: (any HomeStoreLocalMutating)? =
            hasLocalMutation ? localMutation : nil

        self.contextFixture = contextFixture
        self.accountSource = accountSource
        self.contexts = contexts
        coordinator = HomeStoreFeatureActionCoordinator(
            accountSource: accountSource,
            gapBackfill: gapBackfill,
            publish: publishBoundary,
            localMutation: localMutationBoundary,
            filter: filter,
            contexts: contexts
        )
    }

    var gap: TimelineGap {
        TimelineGap(
            id: "feature-action-gap",
            newerPostID: "newer",
            olderPostID: "older",
            missingEstimate: 4,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )
    }

    var publishInput: NostrPublishInput {
        .post(content: "feature action")
    }
}
