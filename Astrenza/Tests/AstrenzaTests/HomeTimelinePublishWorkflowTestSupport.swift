import AstrenzaCore
@testable import Astrenza

enum PublishWorkflowTestError: Error, Equatable {
    case prepare
    case persist
}

@MainActor
final class PublishWorkflowProbe:
    HomeTimelinePublishing,
    HomeTimelinePublishContentManaging,
    HomeTimelinePublishProjectionManaging,
    HomeTimelineOutboxDrainScheduling {
    enum Event: Equatable {
        case prepare(
            input: NostrPublishInput,
            accountID: String,
            writeRelays: [String],
            fallbackRelays: [String]
        )
        case currentAccountID
        case readContent
        case ensureDefinition(
            accountID: String,
            followedPubkeys: [String],
            liveEventIDs: [String]
        )
        case readDefinition
        case persistPublish(eventID: String, feedID: String?)
        case insertOutboxEvent(eventID: String, accountID: String)
        case applyContentSnapshot(HomeTimelineContentSnapshot)
        case reloadNewestProjectionWindow(NostrAccount)
        case materializeEntries
        case persistDatabase(String)
        case setPhase(NostrHomeTimelinePhase)
        case requestImmediateOutboxDrain
    }

    var currentAccountID: String?
    var prepareError: PublishWorkflowTestError?
    var persistError: PublishWorkflowTestError?
    var ensureDefinitionOperation: (@MainActor @Sendable () async -> Void)?
    private let preparedPublish: HomeTimelinePreparedPublish
    private let persistedEvent: NostrEvent
    private let content: HomeTimelineContentSnapshot
    private let insertedContent: HomeTimelineContentSnapshot
    private let feedDefinition: NostrFeedDefinitionRecord?
    private(set) var events: [Event] = []

    init(
        currentAccountID: String?,
        preparedPublish: HomeTimelinePreparedPublish,
        persistedEvent: NostrEvent,
        content: HomeTimelineContentSnapshot,
        insertedContent: HomeTimelineContentSnapshot,
        definition: NostrFeedDefinitionRecord?
    ) {
        self.currentAccountID = currentAccountID
        self.preparedPublish = preparedPublish
        self.persistedEvent = persistedEvent
        self.content = content
        self.insertedContent = insertedContent
        feedDefinition = definition
    }

    var snapshot: HomeTimelineContentSnapshot {
        events.append(.readContent)
        return content
    }

    var definition: NostrFeedDefinitionRecord? {
        events.append(.readDefinition)
        return feedDefinition
    }

    func preparePublish(
        _ input: NostrPublishInput,
        accountID: String,
        accountWriteRelays: [String],
        fallbackRelays: [String],
        signer: any NostrEventSigning
    ) async throws -> HomeTimelinePreparedPublish {
        _ = signer
        events.append(.prepare(
            input: input,
            accountID: accountID,
            writeRelays: accountWriteRelays,
            fallbackRelays: fallbackRelays
        ))
        if let prepareError {
            throw prepareError
        }
        return preparedPublish
    }

    func persistPublish(
        _ publish: HomeTimelinePreparedPublish,
        feedDefinition: NostrFeedDefinitionRecord?
    ) throws -> NostrEvent {
        events.append(.persistPublish(
            eventID: publish.event.id,
            feedID: feedDefinition?.feedID
        ))
        if let persistError {
            throw persistError
        }
        return persistedEvent
    }

    func ensurePublishDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    ) async {
        events.append(.ensureDefinition(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEventIDs: liveEvents.map(\.id)
        ))
        await ensureDefinitionOperation?()
    }

    func insertOutboxEvent(
        _ event: NostrEvent,
        accountID: String
    ) -> HomeTimelineContentSnapshot {
        events.append(.insertOutboxEvent(
            eventID: event.id,
            accountID: accountID
        ))
        return insertedContent
    }

    func requestImmediateDrain() {
        events.append(.requestImmediateOutboxDrain)
    }

    func effects() -> HomeTimelinePublishEffects {
        HomeTimelinePublishEffects(
            currentAccountID: { [self] in
                events.append(.currentAccountID)
                return currentAccountID
            },
            applyContentSnapshot: { [self] snapshot in
                events.append(.applyContentSnapshot(snapshot))
            },
            reloadNewestProjectionWindow: { [self] account in
                events.append(.reloadNewestProjectionWindow(account))
            },
            materializeEntries: { [self] in
                events.append(.materializeEntries)
            },
            persistDatabase: { [self] account in
                events.append(.persistDatabase(account.pubkey))
            },
            setPhase: { [self] phase in
                events.append(.setPhase(phase))
            }
        )
    }
}

actor PublishWorkflowSigner: NostrEventSigning {
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

actor PublishDefinitionPreparationGate {
    private var isSuspended = false
    private var suspension: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        isSuspended = true
        let pendingObservers = observers
        observers.removeAll()
        pendingObservers.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            suspension = continuation
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            observers.append(continuation)
        }
    }

    func resume() {
        suspension?.resume()
        suspension = nil
        isSuspended = false
    }
}
