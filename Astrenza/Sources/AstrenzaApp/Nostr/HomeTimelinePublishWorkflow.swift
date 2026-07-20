import AstrenzaCore

@MainActor
protocol HomeTimelinePublishing: Sendable {
    func preparePublish(
        _ input: NostrPublishInput,
        accountID: String,
        accountWriteRelays: [String],
        taggedUserReadRelays: [String],
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
        taggedUserReadRelays: [String],
        fallbackRelays: [String],
        signer: any NostrEventSigning
    ) async throws -> HomeTimelinePreparedPublish {
        try await prepare(
            input,
            accountID: accountID,
            accountWriteRelays: accountWriteRelays,
            taggedUserReadRelays: taggedUserReadRelays,
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
    ) async
}

extension HomeFeedProjectionController: HomeTimelinePublishProjectionManaging {
    func ensurePublishDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    ) async {
        await ensureDefinition(
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
    var taggedUserReadRelays: [String] = []
    let fallbackRelays: [String]

    init(
        input: NostrPublishInput,
        account: NostrAccount,
        accountWriteRelays: [String],
        taggedUserReadRelays: [String] = [],
        fallbackRelays: [String]
    ) {
        self.input = input
        self.account = account
        self.accountWriteRelays = accountWriteRelays
        self.taggedUserReadRelays = taggedUserReadRelays
        self.fallbackRelays = fallbackRelays
    }
}

enum HomeTimelinePublishStage: Equatable, Sendable {
    case signing
    case savingToOutbox
    case queued(eventID: String)
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
    typealias ProgressEffect = @MainActor @Sendable (
        _ stage: HomeTimelinePublishStage
    ) -> Void

    let currentAccountID: AccountIDProvider
    let applyContentSnapshot: ContentEffect
    let reloadNewestProjectionWindow: AccountEffect
    let materializeEntries: VoidEffect
    let persistDatabase: PersistenceEffect
    let setPhase: PhaseEffect
    var reportProgress: ProgressEffect = { _ in }

    init(
        currentAccountID: @escaping AccountIDProvider,
        applyContentSnapshot: @escaping ContentEffect,
        reloadNewestProjectionWindow: @escaping AccountEffect,
        materializeEntries: @escaping VoidEffect,
        persistDatabase: @escaping PersistenceEffect,
        setPhase: @escaping PhaseEffect,
        reportProgress: @escaping ProgressEffect = { _ in }
    ) {
        self.currentAccountID = currentAccountID
        self.applyContentSnapshot = applyContentSnapshot
        self.reloadNewestProjectionWindow = reloadNewestProjectionWindow
        self.materializeEntries = materializeEntries
        self.persistDatabase = persistDatabase
        self.setPhase = setPhase
        self.reportProgress = reportProgress
    }
}

@MainActor
final class HomeTimelinePublishWorkflow {
    private let publisher: any HomeTimelinePublishing
    private let contentManager: any HomeTimelinePublishContentManaging
    private let projectionManager: any HomeTimelinePublishProjectionManaging
    private let outbox: any HomeTimelineOutboxDrainScheduling

    init(
        publisher: any HomeTimelinePublishing,
        contentManager: any HomeTimelinePublishContentManaging,
        projectionManager: any HomeTimelinePublishProjectionManaging,
        outbox: any HomeTimelineOutboxDrainScheduling
    ) {
        self.publisher = publisher
        self.contentManager = contentManager
        self.projectionManager = projectionManager
        self.outbox = outbox
    }

    @discardableResult
    func enqueue(
        _ request: HomeTimelinePublishRequest,
        signer: any NostrEventSigning,
        effects: HomeTimelinePublishEffects
    ) async throws -> Bool {
        effects.reportProgress(.signing)
        let publish = try await publisher.preparePublish(
            request.input,
            accountID: request.account.pubkey,
            accountWriteRelays: request.accountWriteRelays,
            taggedUserReadRelays: request.taggedUserReadRelays,
            fallbackRelays: request.fallbackRelays,
            signer: signer
        )
        guard effects.currentAccountID() == publish.accountID else {
            return false
        }

        let content = contentManager.snapshot
        await projectionManager.ensurePublishDefinition(
            accountID: request.account.pubkey,
            followedPubkeys: content.followedPubkeys,
            liveEvents: content.noteEvents
        )
        guard effects.currentAccountID() == publish.accountID else {
            return false
        }
        effects.reportProgress(.savingToOutbox)
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
        outbox.requestImmediateDrain()
        effects.reportProgress(.queued(eventID: event.id))
        return true
    }
}
