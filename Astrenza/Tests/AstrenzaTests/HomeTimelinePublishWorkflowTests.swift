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

    @Test("Account switch during definition preparation prevents local persistence")
    func accountSwitchDuringDefinitionPreparationStopsPersistence() async throws {
        let fixture = Fixture()
        let gate = PublishDefinitionPreparationGate()
        fixture.probe.ensureDefinitionOperation = {
            await gate.suspend()
        }

        let enqueueTask = Task {
            try await fixture.workflow.enqueue(
                fixture.request,
                signer: fixture.signer,
                effects: fixture.probe.effects()
            )
        }
        await gate.waitUntilSuspended()
        fixture.probe.currentAccountID = "other-account"
        await gate.resume()

        let didEnqueue = try await enqueueTask.value

        #expect(!didEnqueue)
        #expect(fixture.probe.events == fixture.eventsThroughDefinitionPreparation + [
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

    var eventsThroughDefinitionPreparation: [PublishWorkflowProbe.Event] {
        [
            prepareEvent,
            .currentAccountID,
            .readContent,
            .ensureDefinition(
                accountID: account.pubkey,
                followedPubkeys: ["latest-follow"],
                liveEventIDs: [liveEvent.id]
            )
        ]
    }

    var eventsThroughPersistence: [PublishWorkflowProbe.Event] {
        eventsThroughDefinitionPreparation + [
            .currentAccountID,
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
            projectionManager: probe,
            outbox: probe
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
