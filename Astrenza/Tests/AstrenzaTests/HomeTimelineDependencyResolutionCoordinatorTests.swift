import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline dependency resolution coordinator")
struct HomeTimelineDependencyResolutionCoordinatorTests {
    @Test("Source dependency lifecycle stays inside the coordinator")
    @MainActor
    func sourceDependencyLifecycle() throws {
        let eventID = String(repeating: "a", count: 64)
        let coordinator = makeCoordinator()

        #expect(coordinator.enqueueSourceDependencies(
            NostrEventDependencies(sourceEventIDs: [eventID]),
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: ["wss://relay.example"],
            now: 100
        ))

        let plan = coordinator.drainSourcePacketPlan(requestID: "dependency-test")
        let packet = try #require(plan.sourcePackets.first)
        #expect(coordinator.pendingSourceRequestCount == 1)
        #expect(coordinator.hasPendingWork)

        coordinator.finishSourceEvent(eventID: eventID)
        #expect(coordinator.hasPendingWork)

        #expect(coordinator.completeSourceRequest(NostrBackwardREQCompletion(
            groupID: packet.groupID,
            relayURLs: ["wss://relay.example"],
            subscriptionIDs: [packet.subscriptionID],
            eventCount: 1,
            eoseCount: 1,
            closedCount: 0,
            timeoutCount: 0
        )))
        #expect(coordinator.pendingSourceRequestCount == 0)
        #expect(!coordinator.hasPendingWork)
    }

    @Test("NIP-05 resolution state is published only after the resolver completes")
    @MainActor
    func nip05ResolutionOwnership() async {
        let pubkey = String(repeating: "b", count: 64)
        let identifier = "alice@example.com"
        let resolution = NostrNIP05Resolution(
            identifier: identifier,
            pubkey: pubkey,
            relays: ["wss://relay.example"],
            status: .verified,
            resolvedAt: Date(timeIntervalSince1970: 100)
        )
        let coordinator = makeCoordinator(resolver: StubNIP05Resolver(resolution: resolution))
        let probe = DependencyChangeProbe()

        coordinator.resolveNIP05IfNeeded(
            for: metadataEvent(pubkey: pubkey, nip05: identifier)
        ) {
            probe.count += 1
        }

        for _ in 0..<100 where probe.count == 0 {
            await Task.yield()
        }

        #expect(probe.count == 1)
        #expect(coordinator.nip05Resolutions[pubkey] == resolution)
    }

    @MainActor
    private func makeCoordinator(
        resolver: any NostrNIP05Resolving = StubNIP05Resolver()
    ) -> HomeTimelineDependencyResolutionCoordinator {
        HomeTimelineDependencyResolutionCoordinator(
            eventIngestor: HomeTimelineEventIngestor(eventStore: nil),
            profileDirectory: nil,
            nip05Resolver: resolver,
            syncPlanner: HomeTimelineSyncPlanner()
        )
    }

    private func metadataEvent(pubkey: String, nip05: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: "c", count: 64),
            pubkey: pubkey,
            createdAt: 100,
            kind: 0,
            tags: [],
            content: #"{"nip05":"\#(nip05)"}"#,
            sig: String(repeating: "d", count: 128)
        )
    }
}

@MainActor
private final class DependencyChangeProbe {
    var count = 0
}

private struct StubNIP05Resolver: NostrNIP05Resolving {
    let resolution: NostrNIP05Resolution

    init(
        resolution: NostrNIP05Resolution = NostrNIP05Resolution(
            identifier: "",
            pubkey: nil,
            relays: [],
            status: .absent
        )
    ) {
        self.resolution = resolution
    }

    func resolve(identifier: String, expectedPubkey: String?) async -> NostrNIP05Resolution {
        resolution
    }
}
