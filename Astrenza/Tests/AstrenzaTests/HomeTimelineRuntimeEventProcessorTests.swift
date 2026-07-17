import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline runtime event processor")
@MainActor
struct HomeTimelineRuntimeEventProcessorTests {
    @Test("Forward events persist provenance and produce the presentation plan")
    func forwardEventsPersistAndProducePlan() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let fixture = try makeFixture(eventStore: eventStore)
        let packet = NostrREQPacket.forward(
            subscriptionID: "astrenza-home-forward-processor",
            filters: [[
                "authors": .strings(Array(fixture.context.allowedAuthors)),
                "kinds": .ints([1, 6])
            ]]
        )
        fixture.feedSyncCoordinator.registerForwardContext(
            fixture.context,
            groupID: packet.groupID
        )
        let attempt = NostrRelayRequestAttempt(
            requestID: "forward-request",
            relayURL: relayURL,
            packet: packet,
            startedAt: 100
        )
        let start = fixture.feedSyncCoordinator.startRequest(
            attempt,
            isCurrentFeedContext: { $0 == fixture.context }
        )
        let note = event(idCharacter: "1", pubkey: followedPubkey, createdAt: 200)
        var ensureCount = 0

        let outcome = await fixture.processor.process(
            relayURL: relayURL,
            subscriptionID: packet.subscriptionID,
            event: note,
            forwardPresentationState: { presentationState },
            ensureFeedDefinition: { ensureCount += 1 },
            activeFeedContext: { fixture.context }
        )

        #expect(start.failureMessage == nil)
        #expect(ensureCount == 1)
        guard case .processed(let result) = outcome else {
            Issue.record("Forward event should produce an application plan")
            return
        }
        var expectedPlan = HomeTimelineRuntimeEventApplicationPlan()
        expectedPlan.invalidatesListEntries = true
        expectedPlan.dependencyEvent = note
        expectedPlan.projectionUpdate = .reloadNewestAndSchedule(
            allowsRealtimeFollow: true
        )
        #expect(result.applicationPlan == expectedPlan)
        #expect(result.backwardRequestKey == nil)
        #expect(try eventStore.event(id: note.id) == note)

        let membership = try #require(try eventStore.feedMemberships(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision,
            limit: 10
        ).first)
        #expect(membership.eventID == note.id)
        #expect(membership.reason == "forward")
        let sources = try eventStore.feedMembershipSources(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision,
            eventID: note.id
        )
        #expect(sources.contains {
            $0.sourceType == "sync-request" && $0.sourceID == attempt.requestID
        })
    }

    @Test("Older events resolve registry context and return progress ownership")
    func olderEventsResolveContextAndProgressOwnership() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let fixture = try makeFixture(eventStore: eventStore)
        let packet = NostrREQPacket.backward(
            purpose: "older-notes",
            filters: [[
                "authors": .strings(Array(fixture.context.allowedAuthors)),
                "kinds": .ints([1, 6])
            ]],
            relayURLs: [relayURL],
            groupID: "older-group",
            subscriptionID: "older-group-req"
        )
        fixture.registry.registerOlderPage(
            groupID: packet.groupID,
            context: fixture.context,
            anchorEventID: "anchor"
        )
        let attempt = NostrRelayRequestAttempt(
            requestID: "older-request",
            relayURL: relayURL,
            packet: packet,
            startedAt: 100
        )
        let start = fixture.feedSyncCoordinator.startRequest(
            attempt,
            isCurrentFeedContext: { $0 == fixture.context }
        )
        let note = event(idCharacter: "2", pubkey: followedPubkey, createdAt: 90)
        var ensureCount = 0

        let outcome = await fixture.processor.process(
            relayURL: relayURL,
            subscriptionID: packet.subscriptionID,
            event: note,
            forwardPresentationState: { presentationState },
            ensureFeedDefinition: { ensureCount += 1 },
            activeFeedContext: { fixture.context }
        )

        #expect(start.failureMessage == nil)
        #expect(ensureCount == 1)
        guard case .processed(let result) = outcome else {
            Issue.record("Older event should produce an application plan")
            return
        }
        var expectedPlan = HomeTimelineRuntimeEventApplicationPlan()
        expectedPlan.invalidatesListEntries = true
        expectedPlan.backwardTimelineEventID = note.id
        expectedPlan.sourceEventIDToFinish = note.id
        expectedPlan.dependencyEvent = note
        #expect(result.applicationPlan == expectedPlan)
        #expect(result.backwardRequestKey == packet.groupID)
        #expect(fixture.registry.request(for: packet.groupID)?.receivedTimelineEventCount == 0)

        let membership = try #require(try eventStore.feedMemberships(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision,
            limit: 10
        ).first)
        #expect(membership.eventID == note.id)
        #expect(membership.reason == "older")
    }

    @Test("Unsupported forward events are ignored without persistence or setup")
    func unsupportedForwardEventsAreIgnored() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let fixture = try makeFixture(eventStore: eventStore)
        let metadata = event(
            idCharacter: "3",
            pubkey: followedPubkey,
            createdAt: 300,
            kind: 0
        )
        var ensureCount = 0

        let outcome = await fixture.processor.process(
            relayURL: relayURL,
            subscriptionID: "astrenza-home-forward-ignored",
            event: metadata,
            forwardPresentationState: { presentationState },
            ensureFeedDefinition: { ensureCount += 1 },
            activeFeedContext: { fixture.context }
        )

        #expect(outcome == .ignored)
        #expect(ensureCount == 0)
        #expect(try eventStore.event(id: metadata.id) == nil)
    }

    @Test("Forward presentation state is sampled after persistence completes")
    func forwardPresentationStateIsSampledAfterPersistence() async {
        let registry = HomeTimelineBackwardRequestRegistry()
        let feedSyncCoordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: nil,
            backwardRequestRegistry: registry
        )
        let ingestor = SuspendedProjectedEventIngestor()
        let processor = HomeTimelineRuntimeEventProcessor(
            eventIngestor: ingestor,
            backwardRequestRegistry: registry,
            feedSyncCoordinator: feedSyncCoordinator
        )
        let note = event(idCharacter: "5", pubkey: followedPubkey, createdAt: 500)
        let state = PresentationStateBox(
            HomeTimelineRuntimeEventPresentationState(
                receivedWhileRealtime: false,
                hasRestoreProjectionAnchor: true,
                isTimelineAtNewestWindow: false,
                hasPendingEvents: true
            )
        )
        let processing = Task { @MainActor in
            await processor.process(
                relayURL: relayURL,
                subscriptionID: "astrenza-home-forward-suspended",
                event: note,
                forwardPresentationState: { state.value },
                ensureFeedDefinition: {},
                activeFeedContext: { nil }
            )
        }
        await ingestor.waitUntilForwardStarted()

        state.value = presentationState
        await ingestor.resumeForward(with: note)
        let outcome = await processing.value

        guard case .processed(let result) = outcome else {
            Issue.record("Forward event should finish with the latest presentation state")
            return
        }
        #expect(result.applicationPlan.projectionUpdate == .reloadNewestAndSchedule(
            allowsRealtimeFollow: true
        ))
    }

    @Test("Persistence failures retain direction-specific diagnostics")
    func persistenceFailuresRetainDirectionDiagnostics() async {
        let registry = HomeTimelineBackwardRequestRegistry()
        let feedSyncCoordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: nil,
            backwardRequestRegistry: registry
        )
        let processor = HomeTimelineRuntimeEventProcessor(
            eventIngestor: FailingProjectedEventIngestor(),
            backwardRequestRegistry: registry,
            feedSyncCoordinator: feedSyncCoordinator,
            persistenceRetryPolicy: .init(
                maxAttempts: 1,
                initialDelayNanoseconds: 0,
                maximumDelayNanoseconds: 0
            )
        )
        let note = event(idCharacter: "4", pubkey: followedPubkey, createdAt: 400)
        var ensureCount = 0

        let forward = await processor.process(
            relayURL: relayURL,
            subscriptionID: "astrenza-home-forward-failure",
            event: note,
            forwardPresentationState: { presentationState },
            ensureFeedDefinition: { ensureCount += 1 },
            activeFeedContext: { nil }
        )
        let backward = await processor.process(
            relayURL: relayURL,
            subscriptionID: "dependency-failure",
            event: note,
            forwardPresentationState: { presentationState },
            ensureFeedDefinition: { ensureCount += 1 },
            activeFeedContext: { nil }
        )

        #expect(forward == .persistenceFailed("event save failed: unavailable"))
        #expect(backward == .persistenceFailed("backward event save failed: unavailable"))
        #expect(ensureCount == 1)
    }

    @Test("A transient persistence failure retries the complete event batch")
    func transientPersistenceFailureRetriesBatch() async {
        let registry = HomeTimelineBackwardRequestRegistry()
        let feedSyncCoordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: nil,
            backwardRequestRegistry: registry
        )
        let ingestor = RetryingProjectedEventIngestor(failuresBeforeSuccess: 2)
        let processor = HomeTimelineRuntimeEventProcessor(
            eventIngestor: ingestor,
            backwardRequestRegistry: registry,
            feedSyncCoordinator: feedSyncCoordinator,
            persistenceRetryPolicy: .init(
                maxAttempts: 3,
                initialDelayNanoseconds: 0,
                maximumDelayNanoseconds: 0
            )
        )
        let note = event(
            idCharacter: "6",
            pubkey: followedPubkey,
            createdAt: 600
        )

        let outcome = await processor.process(
            relayURL: relayURL,
            subscriptionID: "astrenza-home-forward-retry",
            event: note,
            forwardPresentationState: { presentationState },
            ensureFeedDefinition: {},
            activeFeedContext: { nil }
        )

        guard case .processed = outcome else {
            Issue.record("The event batch should succeed on its final retry")
            return
        }
        #expect(await ingestor.requestCount() == 3)
    }

    private func makeFixture(eventStore: NostrEventStore) throws -> Fixture {
        let definition = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: [followedPubkey],
            existingDefinition: nil,
            now: 10
        )?.definition)
        try eventStore.saveFeedDefinition(definition)
        let context = HomeFeedRuntimeContext(definition: definition)
        let registry = HomeTimelineBackwardRequestRegistry()
        let feedSyncCoordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: registry,
            now: { 500 }
        )
        return Fixture(
            definition: definition,
            context: context,
            registry: registry,
            feedSyncCoordinator: feedSyncCoordinator,
            processor: HomeTimelineRuntimeEventProcessor(
                eventIngestor: HomeTimelineEventIngestor(
                    eventStore: eventStore,
                    now: { 200 }
                ),
                backwardRequestRegistry: registry,
                feedSyncCoordinator: feedSyncCoordinator
            )
        )
    }

    private func event(
        idCharacter: String,
        pubkey: String,
        createdAt: Int,
        kind: Int = 1
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: idCharacter, count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: [],
            content: idCharacter,
            sig: String(repeating: "a", count: 128)
        )
    }

    private var presentationState: HomeTimelineRuntimeEventPresentationState {
        HomeTimelineRuntimeEventPresentationState(
            receivedWhileRealtime: true,
            hasRestoreProjectionAnchor: false,
            isTimelineAtNewestWindow: true,
            hasPendingEvents: false
        )
    }

    private var accountID: String { String(repeating: "a", count: 64) }
    private var followedPubkey: String { String(repeating: "b", count: 64) }
    private var relayURL: String { "wss://relay.example" }

    private struct Fixture {
        let definition: NostrFeedDefinitionRecord
        let context: HomeFeedRuntimeContext
        let registry: HomeTimelineBackwardRequestRegistry
        let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
        let processor: HomeTimelineRuntimeEventProcessor
    }
}

private struct FailingProjectedEventIngestor: HomeTimelineProjectedEventIngesting {
    func ingestForward(
        _ request: HomeTimelineForwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult {
        throw ProjectedEventIngestError.unavailable
    }

    func ingestBackward(
        _ request: HomeTimelineBackwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult {
        throw ProjectedEventIngestError.unavailable
    }
}

private actor RetryingProjectedEventIngestor:
    HomeTimelineProjectedEventIngesting {
    private let failuresBeforeSuccess: Int
    private var requests = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func ingestForward(
        _ request: HomeTimelineForwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult {
        requests += 1
        if requests <= failuresBeforeSuccess {
            throw ProjectedEventIngestError.unavailable
        }
        return HomeTimelineProjectedEventIngestResult(
            eventResult: HomeTimelineEventIngestResult(
                primaryEventID: request.event.id,
                embeddedEvent: nil,
                savedEventIDs: [request.event.id]
            ),
            projectsIntoCurrentFeed: true
        )
    }

    func ingestBackward(
        _ request: HomeTimelineBackwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult {
        throw ProjectedEventIngestError.unavailable
    }

    func requestCount() -> Int { requests }
}

@MainActor
private final class PresentationStateBox {
    var value: HomeTimelineRuntimeEventPresentationState

    init(_ value: HomeTimelineRuntimeEventPresentationState) {
        self.value = value
    }
}

private actor SuspendedProjectedEventIngestor: HomeTimelineProjectedEventIngesting {
    private var forwardContinuation: CheckedContinuation<
        HomeTimelineProjectedEventIngestResult,
        Never
    >?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func ingestForward(
        _ request: HomeTimelineForwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult {
        await withCheckedContinuation { continuation in
            forwardContinuation = continuation
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func ingestBackward(
        _ request: HomeTimelineBackwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult {
        throw ProjectedEventIngestError.unavailable
    }

    func waitUntilForwardStarted() async {
        guard forwardContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeForward(with event: NostrEvent) {
        forwardContinuation?.resume(returning: HomeTimelineProjectedEventIngestResult(
            eventResult: HomeTimelineEventIngestResult(
                primaryEventID: event.id,
                embeddedEvent: nil,
                savedEventIDs: [event.id]
            ),
            projectsIntoCurrentFeed: true
        ))
        forwardContinuation = nil
    }
}

private enum ProjectedEventIngestError: LocalizedError {
    case unavailable

    var errorDescription: String? { "unavailable" }
}
