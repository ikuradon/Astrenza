import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline publish workflow")
@MainActor
struct HomeTimelinePublishWorkflowTests {
    @Test("Prepare failure propagates before reading mutable timeline state")
    func prepareFailureStopsWorkflow() async {
        let fixture = Fixture()
        fixture.probe.prepareError = .prepare

        await #expect(throws: PublishWorkflowTestError.prepare) {
            try await fixture.workflow.enqueue(
                fixture.request,
                signer: fixture.signer,
                effects: fixture.probe.effects()
            )
        }

        #expect(fixture.probe.events == [fixture.prepareEvent])
    }

    @Test("Account switch after signing prevents local publish persistence")
    func accountSwitchStopsBeforePersistence() async throws {
        let fixture = Fixture()
        fixture.probe.currentAccountID = "other-account"

        let didEnqueue = try await fixture.workflow.enqueue(
            fixture.request,
            signer: fixture.signer,
            effects: fixture.probe.effects()
        )

        #expect(!didEnqueue)
        #expect(fixture.probe.events == [
            fixture.prepareEvent,
            .currentAccountID
        ])
    }

    @Test("Local persistence failure stops before content and UI side effects")
    func persistenceFailureStopsApplication() async {
        let fixture = Fixture()
        fixture.probe.persistError = .persist

        await #expect(throws: PublishWorkflowTestError.persist) {
            try await fixture.workflow.enqueue(
                fixture.request,
                signer: fixture.signer,
                effects: fixture.probe.effects()
            )
        }

        #expect(fixture.probe.events == fixture.eventsThroughPersistence)
    }

    @Test("Success applies local state and side effects in the original order")
    func successPreservesApplicationOrder() async throws {
        let fixture = Fixture()

        let didEnqueue = try await fixture.workflow.enqueue(
            fixture.request,
            signer: fixture.signer,
            effects: fixture.probe.effects()
        )

        #expect(didEnqueue)
        #expect(fixture.probe.events == fixture.successEvents)
    }
}

@MainActor
private final class Fixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "account",
        readOnly: true
    )
    let signer = PublishWorkflowSigner()
    let input = NostrPublishInput.post(content: "published")
    let writeRelays = ["wss://write.example"]
    let fallbackRelays = ["wss://fallback.example"]
    let liveEvent: NostrEvent
    let publishedEvent: NostrEvent
    let insertedContent: HomeTimelineContentSnapshot
    let definition: NostrFeedDefinitionRecord
    let probe: PublishWorkflowProbe
    let workflow: HomeTimelinePublishWorkflow

    var request: HomeTimelinePublishRequest {
        HomeTimelinePublishRequest(
            input: input,
            account: account,
            accountWriteRelays: writeRelays,
            fallbackRelays: fallbackRelays
        )
    }

    var prepareEvent: PublishWorkflowProbe.Event {
        .prepare(
            input: input,
            accountID: account.pubkey,
            writeRelays: writeRelays,
            fallbackRelays: fallbackRelays
        )
    }

    var eventsThroughPersistence: [PublishWorkflowProbe.Event] {
        [
            prepareEvent,
            .currentAccountID,
            .readContent,
            .ensureDefinition(
                accountID: account.pubkey,
                followedPubkeys: ["latest-follow"],
                liveEventIDs: [liveEvent.id]
            ),
            .readDefinition,
            .persistPublish(
                eventID: publishedEvent.id,
                feedID: definition.feedID
            )
        ]
    }

    var successEvents: [PublishWorkflowProbe.Event] {
        eventsThroughPersistence + [
            .insertOutboxEvent(
                eventID: publishedEvent.id,
                accountID: account.pubkey
            ),
            .applyContentSnapshot(insertedContent),
            .reloadNewestProjectionWindow(account),
            .materializeEntries,
            .persistDatabase(account.pubkey),
            .setPhase(.loaded),
            .requestImmediateOutboxDrain
        ]
    }

    init() {
        let accountID = String(repeating: "a", count: 64)
        liveEvent = Self.event(
            idSeed: "live",
            pubkey: String(repeating: "b", count: 64),
            content: "latest content"
        )
        publishedEvent = Self.event(
            idSeed: "published",
            pubkey: accountID,
            content: "published"
        )
        definition = Self.definition(accountID: accountID)
        let currentContent = HomeTimelineContentSnapshot(
            resolvedRelays: fallbackRelays,
            followedPubkeys: ["latest-follow"],
            noteEvents: [liveEvent],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        )
        insertedContent = HomeTimelineContentSnapshot(
            resolvedRelays: fallbackRelays,
            followedPubkeys: ["latest-follow", accountID],
            noteEvents: [publishedEvent, liveEvent],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        )
        probe = PublishWorkflowProbe(
            currentAccountID: accountID,
            preparedPublish: HomeTimelinePreparedPublish(
                accountID: accountID,
                event: publishedEvent,
                destinationRelayURLs: writeRelays,
                createdAt: 100
            ),
            persistedEvent: publishedEvent,
            content: currentContent,
            insertedContent: insertedContent,
            definition: definition
        )
        workflow = HomeTimelinePublishWorkflow(
            publisher: probe,
            contentManager: probe,
            projectionManager: probe
        )
    }

    private static func event(
        idSeed: String,
        pubkey: String,
        content: String
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: idSeed.first ?? "0", count: 64),
            pubkey: pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: content,
            sig: String(repeating: "1", count: 128)
        )
    }

    private static func definition(
        accountID: String
    ) -> NostrFeedDefinitionRecord {
        NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(),
            specificationHash: "publish-workflow",
            revision: 1,
            createdAt: 100,
            updatedAt: 100
        )
    }
}

private enum PublishWorkflowTestError: Error, Equatable {
    case prepare
    case persist
}

@MainActor
private final class PublishWorkflowProbe:
    HomeTimelinePublishing,
    HomeTimelinePublishContentManaging,
    HomeTimelinePublishProjectionManaging {
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
    ) {
        events.append(.ensureDefinition(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEventIDs: liveEvents.map(\.id)
        ))
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
            },
            requestImmediateOutboxDrain: { [self] in
                events.append(.requestImmediateOutboxDrain)
            }
        )
    }
}

private actor PublishWorkflowSigner: NostrEventSigning {
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
