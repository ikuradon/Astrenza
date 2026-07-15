import AstrenzaCore

@MainActor
protocol HomeTimelinePublishing: Sendable {
    func preparePublish(
        _ input: NostrPublishInput,
        accountID: String,
        accountWriteRelays: [String],
        fallbackRelays: [String],
        signer: any NostrEventSigning
    ) async throws -> HomeTimelinePreparedPublish

    func persistPublish(
        _ publish: HomeTimelinePreparedPublish,
        feedDefinition: NostrFeedDefinitionRecord?
    ) throws -> NostrEvent
}

extension HomeTimelinePublishCoordinator: HomeTimelinePublishing {
    func preparePublish(
        _ input: NostrPublishInput,
        accountID: String,
        accountWriteRelays: [String],
        fallbackRelays: [String],
        signer: any NostrEventSigning
    ) async throws -> HomeTimelinePreparedPublish {
        try await prepare(
            input,
            accountID: accountID,
            accountWriteRelays: accountWriteRelays,
            fallbackRelays: fallbackRelays,
            signer: signer
        )
    }

    func persistPublish(
        _ publish: HomeTimelinePreparedPublish,
        feedDefinition: NostrFeedDefinitionRecord?
    ) throws -> NostrEvent {
        try persist(publish, feedDefinition: feedDefinition)
    }
}

@MainActor
protocol HomeTimelinePublishContentManaging: AnyObject {
    var snapshot: HomeTimelineContentSnapshot { get }

    func insertOutboxEvent(
        _ event: NostrEvent,
        accountID: String
    ) -> HomeTimelineContentSnapshot
}

extension HomeTimelineContentCoordinator: HomeTimelinePublishContentManaging {}

@MainActor
protocol HomeTimelinePublishProjectionManaging: AnyObject {
    var definition: NostrFeedDefinitionRecord? { get }

    func ensurePublishDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    )
}

extension HomeFeedProjectionController: HomeTimelinePublishProjectionManaging {
    func ensurePublishDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    ) {
        ensureDefinition(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents
        )
    }
}

struct HomeTimelinePublishRequest: Equatable, Sendable {
    let input: NostrPublishInput
    let account: NostrAccount
    let accountWriteRelays: [String]
    let fallbackRelays: [String]
}

struct HomeTimelinePublishEffects: Sendable {
    typealias AccountIDProvider = @MainActor @Sendable () -> String?
    typealias ContentEffect = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias AccountEffect = @MainActor @Sendable (_ account: NostrAccount) -> Void
    typealias VoidEffect = @MainActor @Sendable () -> Void
    typealias PhaseEffect = @MainActor @Sendable (
        _ phase: NostrHomeTimelinePhase
    ) -> Void
    typealias PersistenceEffect = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void

    let currentAccountID: AccountIDProvider
    let applyContentSnapshot: ContentEffect
    let reloadNewestProjectionWindow: AccountEffect
    let materializeEntries: VoidEffect
    let persistDatabase: PersistenceEffect
    let setPhase: PhaseEffect
    let requestImmediateOutboxDrain: VoidEffect
}

@MainActor
final class HomeTimelinePublishWorkflow {
    private let publisher: any HomeTimelinePublishing
    private let contentManager: any HomeTimelinePublishContentManaging
    private let projectionManager: any HomeTimelinePublishProjectionManaging

    init(
        publisher: any HomeTimelinePublishing,
        contentManager: any HomeTimelinePublishContentManaging,
        projectionManager: any HomeTimelinePublishProjectionManaging
    ) {
        self.publisher = publisher
        self.contentManager = contentManager
        self.projectionManager = projectionManager
    }

    @discardableResult
    func enqueue(
        _ request: HomeTimelinePublishRequest,
        signer: any NostrEventSigning,
        effects: HomeTimelinePublishEffects
    ) async throws -> Bool {
        let publish = try await publisher.preparePublish(
            request.input,
            accountID: request.account.pubkey,
            accountWriteRelays: request.accountWriteRelays,
            fallbackRelays: request.fallbackRelays,
            signer: signer
        )
        guard effects.currentAccountID() == publish.accountID else {
            return false
        }

        let content = contentManager.snapshot
        projectionManager.ensurePublishDefinition(
            accountID: request.account.pubkey,
            followedPubkeys: content.followedPubkeys,
            liveEvents: content.noteEvents
        )
        let event = try publisher.persistPublish(
            publish,
            feedDefinition: projectionManager.definition
        )
        effects.applyContentSnapshot(contentManager.insertOutboxEvent(
            event,
            accountID: request.account.pubkey
        ))
        effects.reloadNewestProjectionWindow(request.account)
        effects.materializeEntries()
        await effects.persistDatabase(request.account)
        effects.setPhase(.loaded)
        effects.requestImmediateOutboxDrain()
        return true
    }
}
