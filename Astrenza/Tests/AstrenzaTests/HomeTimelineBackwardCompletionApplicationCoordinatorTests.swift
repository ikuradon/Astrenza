import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline backward completion application coordinator")
struct HomeTimelineBackwardCompletionApplicationCoordinatorTests {
    @Test("A source dependency completion is consumed without timeline work")
    @MainActor
    func completesSourceDependencyRequest() throws {
        let system = try BackwardCompletionTestSystem()
        let eventID = String(repeating: "c", count: 64)
        #expect(system.dependencies.enqueueSourceDependencies(
            NostrEventDependencies(sourceEventIDs: [eventID]),
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: [system.relayURL],
            now: 100
        ))
        let packet = try #require(
            system.dependencies
                .drainSourcePacketPlan(requestID: "source")
                .sourcePackets.first
        )

        let commands = system.application.handle(
            completion(groupID: packet.groupID),
            accountID: system.accountID
        )

        #expect(commands == [.incrementRelayStatusRevision])
        #expect(system.dependencies.pendingSourceRequestCount == 0)
        #expect(!system.dependencies.hasPendingWork)
        #expect(system.application.handle(
            completion(groupID: packet.groupID),
            accountID: system.accountID
        ).isEmpty)
    }

    @Test("A completed empty older page updates content without projection reload")
    @MainActor
    func marksOlderEnd() throws {
        let system = try BackwardCompletionTestSystem()
        system.registry.registerOlderPage(
            groupID: "older",
            context: system.requestContext,
            anchorEventID: "anchor"
        )

        let commands = system.application.handle(
            completion(groupID: "older"),
            accountID: system.accountID
        )

        #expect(!system.content.snapshot.hasMoreOlder)
        #expect(commands == [
            .applyContentSnapshot(system.content.snapshot),
            .incrementRelayStatusRevision
        ])
        #expect(system.persistence.boundaryRequests.isEmpty)
    }

    @Test("A partial older page persists its boundary before requesting a merged reload")
    @MainActor
    func persistsPartialOlderBoundary() throws {
        let system = try BackwardCompletionTestSystem()
        system.registry.registerOlderPage(
            groupID: "older",
            context: system.requestContext,
            anchorEventID: "anchor"
        )
        system.registry.recordTimelineEvent("received", for: "older")

        let commands = system.application.handle(
            completion(groupID: "older", eoseCount: 1, closedCount: 1),
            accountID: system.accountID
        )

        let boundary = try #require(system.persistence.boundaryRequests.first)
        #expect(boundary.request.receivedTimelineEventIDs == ["received"])
        #expect(boundary.definition == system.activeDefinition)
        #expect(commands == [
            .reloadProjection(
                anchorEventID: "anchor",
                mergingWithCurrentWindow: true
            ),
            .incrementRelayStatusRevision
        ])
    }

    @Test("A boundary persistence failure becomes a diagnostic command")
    @MainActor
    func reportsBoundaryPersistenceFailure() throws {
        let persistence = BackwardCompletionPersistenceSpy(failsBoundaryPersistence: true)
        let system = try BackwardCompletionTestSystem(persistence: persistence)
        system.registry.registerOlderPage(
            groupID: "older",
            context: system.requestContext,
            anchorEventID: "anchor"
        )
        system.registry.recordTimelineEvent("received", for: "older")

        let commands = system.application.handle(
            completion(groupID: "older", eoseCount: 1, closedCount: 1),
            accountID: system.accountID
        )

        #expect(commands == [
            .recordDiagnostic(HomeTimelineBackwardCompletionDiagnostic(
                relayURL: system.relayURL,
                message: "older gap mark failed: disk full"
            )),
            .reloadProjection(
                anchorEventID: "anchor",
                mergingWithCurrentWindow: true
            ),
            .incrementRelayStatusRevision
        ])
    }

    @Test("A stale feed completion performs no persistence or projection work")
    @MainActor
    func rejectsStaleFeedContext() throws {
        let system = try BackwardCompletionTestSystem(
            activeRevision: 4,
            requestRevision: 3
        )
        system.registry.registerOlderPage(
            groupID: "older",
            context: system.requestContext,
            anchorEventID: "anchor"
        )
        system.registry.recordTimelineEvent("received", for: "older")

        let commands = system.application.handle(
            completion(groupID: "older", eoseCount: 1, closedCount: 1),
            accountID: system.accountID
        )

        #expect(commands == [.incrementRelayStatusRevision])
        #expect(system.persistence.boundaryRequests.isEmpty)
        #expect(system.content.snapshot.hasMoreOlder)
    }

    @Test("A partial gap is marked unresolved and restores its stable projection anchor")
    @MainActor
    func restoresPartialGap() throws {
        let system = try BackwardCompletionTestSystem()
        system.registry.registerGap(
            groupID: "gap",
            context: system.requestContext,
            newerEventID: "newer",
            olderEventID: "older",
            direction: .older
        )
        system.registry.recordTimelineEvent("received", for: "gap")

        let commands = system.application.handle(
            completion(groupID: "gap", eoseCount: 1, closedCount: 1),
            accountID: system.accountID
        )

        let unresolved = try #require(system.persistence.unresolvedGaps.first)
        #expect(unresolved.gap == PendingGapBackfill(
            newerPostID: "newer",
            olderPostID: "older",
            direction: .older
        ))
        #expect(unresolved.context == system.requestContext)
        #expect(commands == [
            .reloadProjection(
                anchorEventID: "newer",
                mergingWithCurrentWindow: false
            ),
            .incrementRelayStatusRevision
        ])
    }

    @Test("A completed gap delegates reconciliation without restoring the projection")
    @MainActor
    func delegatesCompletedGapReconciliation() throws {
        let system = try BackwardCompletionTestSystem()
        let gap = PendingGapBackfill(
            newerPostID: "newer",
            olderPostID: "older",
            direction: .newer
        )
        system.registry.registerGap(
            groupID: "gap",
            context: system.requestContext,
            newerEventID: gap.newerPostID,
            olderEventID: gap.olderPostID,
            direction: gap.direction
        )

        let commands = system.application.handle(
            completion(groupID: "gap"),
            accountID: system.accountID
        )

        #expect(commands == [
            .reconcileGap(gap: gap, context: system.requestContext),
            .incrementRelayStatusRevision
        ])
        #expect(system.persistence.unresolvedGaps.isEmpty)
    }

    private func completion(
        groupID: String,
        eventCount: Int = 0,
        eoseCount: Int = 1,
        closedCount: Int = 0,
        timeoutCount: Int = 0
    ) -> NostrBackwardREQCompletion {
        NostrBackwardREQCompletion(
            groupID: groupID,
            relayURLs: ["wss://relay.example"],
            subscriptionIDs: ["\(groupID)-relay"],
            eventCount: eventCount,
            eoseCount: eoseCount,
            closedCount: closedCount,
            timeoutCount: timeoutCount
        )
    }
}

@MainActor
private struct BackwardCompletionTestSystem {
    let accountID = String(repeating: "a", count: 64)
    let relayURL = "wss://relay.example"
    let activeDefinition: NostrFeedDefinitionRecord
    let requestContext: HomeFeedRuntimeContext
    let registry: HomeTimelineBackwardRequestRegistry
    let dependencies: HomeTimelineDependencyResolutionCoordinator
    let content: HomeTimelineContentCoordinator
    let persistence: BackwardCompletionPersistenceSpy
    let application: HomeTimelineBackwardCompletionApplicationCoordinator

    init(
        activeRevision: Int = 3,
        requestRevision: Int? = nil,
        persistence: BackwardCompletionPersistenceSpy = .init()
    ) throws {
        let activeDefinition = try Self.definition(
            accountID: accountID,
            revision: activeRevision
        )
        let requestDefinition = try Self.definition(
            accountID: accountID,
            revision: requestRevision ?? activeRevision
        )
        let registry = HomeTimelineBackwardRequestRegistry()
        let dependencies = HomeTimelineDependencyResolutionCoordinator(
            eventIngestor: HomeTimelineEventIngestor(eventStore: nil),
            profileDirectory: nil,
            nip05Resolver: BackwardCompletionStubNIP05Resolver(),
            syncPlanner: HomeTimelineSyncPlanner()
        )
        let content = HomeTimelineContentCoordinator(eventStore: nil)
        _ = content.replace(
            with: NostrHomeTimelineState(
                relays: [relayURL],
                followedPubkeys: [accountID],
                noteEvents: [],
                metadataEvents: []
            )
        )
        let projection = HomeFeedProjectionController(eventStore: nil)
        projection.activate(
            definition: activeDefinition,
            window: nil,
            sourceAuthors: [accountID]
        )

        self.activeDefinition = activeDefinition
        self.requestContext = HomeFeedRuntimeContext(definition: requestDefinition)
        self.registry = registry
        self.dependencies = dependencies
        self.content = content
        self.persistence = persistence
        self.application = HomeTimelineBackwardCompletionApplicationCoordinator(
            backwardRequestRegistry: registry,
            dependencyCoordinator: dependencies,
            contentCoordinator: content,
            projectionController: projection,
            persistence: persistence
        )
    }

    private static func definition(
        accountID: String,
        revision: Int
    ) throws -> NostrFeedDefinitionRecord {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [accountID], kinds: [1, 6])
        )
        return NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification-\(revision)",
            revision: revision,
            createdAt: 1,
            updatedAt: revision
        )
    }
}

@MainActor
private final class BackwardCompletionPersistenceSpy: HomeTimelineBackwardCompletionPersisting {
    struct BoundaryRequest {
        let request: PendingBackwardRequest
        let definition: NostrFeedDefinitionRecord
    }

    struct UnresolvedGap {
        let gap: PendingGapBackfill
        let context: HomeFeedRuntimeContext
    }

    let failsBoundaryPersistence: Bool
    private(set) var boundaryRequests: [BoundaryRequest] = []
    private(set) var unresolvedGaps: [UnresolvedGap] = []

    init(failsBoundaryPersistence: Bool = false) {
        self.failsBoundaryPersistence = failsBoundaryPersistence
    }

    func markOlderPageBoundaryGap(
        request: PendingBackwardRequest,
        definition: NostrFeedDefinitionRecord
    ) throws -> Bool {
        boundaryRequests.append(BoundaryRequest(
            request: request,
            definition: definition
        ))
        if failsBoundaryPersistence {
            throw BackwardCompletionPersistenceTestError.diskFull
        }
        return true
    }

    func markGapUnresolved(
        _ gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) {
        unresolvedGaps.append(UnresolvedGap(gap: gap, context: context))
    }
}

private enum BackwardCompletionPersistenceTestError: LocalizedError {
    case diskFull

    var errorDescription: String? {
        "disk full"
    }
}

private struct BackwardCompletionStubNIP05Resolver: NostrNIP05Resolving {
    func resolve(
        identifier: String,
        expectedPubkey: String?
    ) async -> NostrNIP05Resolution {
        NostrNIP05Resolution(
            identifier: identifier,
            pubkey: expectedPubkey,
            relays: [],
            status: .absent
        )
    }
}
