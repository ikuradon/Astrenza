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

    @Test("Source packet scheduling coalesces buffered dependencies into one install")
    @MainActor
    func sourcePacketSchedulingCoalescesInstalls() async throws {
        let installer = SourcePacketInstallerStub(outcome: .success)
        let failures = SourceInstallFailureProbe()
        let coordinator = makeCoordinator(
            sourcePacketInstaller: { packets in
                try await installer.install(packets)
            },
            sourceFlushDelayNanoseconds: 20_000_000
        )
        let firstEventID = String(repeating: "d", count: 64)
        let secondEventID = String(repeating: "e", count: 64)
        #expect(enqueue(firstEventID, in: coordinator))
        #expect(enqueue(secondEventID, in: coordinator))

        let didSchedule = coordinator.scheduleSourcePacketInstall { message in
            failures.messages.append(message)
        }
        let didScheduleDuplicate = coordinator.scheduleSourcePacketInstall { message in
            failures.messages.append(message)
        }
        #expect(didSchedule)
        #expect(!didScheduleDuplicate)
        #expect(coordinator.hasScheduledSourceFlush)

        try await waitUntil {
            let callCount = await installer.callCount()
            return callCount == 1 && coordinator.activeSourceInstallCount == 0
        }

        let installations = await installer.installations()
        let packet = try #require(installations.first?.first)
        #expect(installations.count == 1)
        #expect(installations[0].count == 1)
        #expect(failures.messages.isEmpty)
        #expect(coordinator.pendingSourceRequestCount == 1)
        #expect(coordinator.hasPendingWork)

        #expect(coordinator.completeSourceRequest(completion(for: packet)))
        #expect(coordinator.pendingSourceRequestCount == 0)
        #expect(!coordinator.hasPendingWork)
    }

    @Test("A failed source packet install releases dependency work")
    @MainActor
    func failedSourcePacketInstallReleasesWork() async throws {
        let installer = SourcePacketInstallerStub(outcome: .failure)
        let failures = SourceInstallFailureProbe()
        let coordinator = makeCoordinator(sourcePacketInstaller: { packets in
            try await installer.install(packets)
        })
        #expect(enqueue(String(repeating: "f", count: 64), in: coordinator))

        let didFlush = coordinator.flushSourcePacketInstall { message in
            failures.messages.append(message)
        }
        #expect(didFlush)

        try await waitUntil {
            failures.messages.count == 1 && coordinator.activeSourceInstallCount == 0
        }
        #expect(failures.messages == ["stub source install failed"])
        #expect(coordinator.pendingSourceRequestCount == 0)
        #expect(!coordinator.hasPendingWork)
    }

    @Test("Reset cancels source installs and ignores their stale failures")
    @MainActor
    func resetInvalidatesSourceInstallFailure() async throws {
        let installer = SourcePacketInstallerStub(outcome: .delayedFailure(5_000_000_000))
        let failures = SourceInstallFailureProbe()
        let coordinator = makeCoordinator(sourcePacketInstaller: { packets in
            try await installer.install(packets)
        })
        #expect(enqueue(String(repeating: "1", count: 64), in: coordinator))
        let didFlush = coordinator.flushSourcePacketInstall { message in
            failures.messages.append(message)
        }
        #expect(didFlush)
        try await waitUntil {
            await installer.callCount() == 1
        }

        coordinator.reset()

        try await waitUntil {
            await installer.completedCount() == 1
        }
        #expect(failures.messages.isEmpty)
        #expect(!coordinator.hasScheduledSourceFlush)
        #expect(coordinator.activeSourceInstallCount == 0)
        #expect(!coordinator.hasPendingWork)
    }

    @MainActor
    private func makeCoordinator(
        resolver: any NostrNIP05Resolving = StubNIP05Resolver(),
        sourcePacketInstaller: HomeTimelineDependencyResolutionCoordinator.SourcePacketInstaller? = nil,
        sourceFlushDelayNanoseconds: UInt64 = 12_000_000
    ) -> HomeTimelineDependencyResolutionCoordinator {
        HomeTimelineDependencyResolutionCoordinator(
            eventIngestor: HomeTimelineEventIngestor(eventStore: nil),
            profileDirectory: nil,
            nip05Resolver: resolver,
            syncPlanner: HomeTimelineSyncPlanner(),
            sourcePacketInstaller: sourcePacketInstaller,
            sourceFlushDelayNanoseconds: sourceFlushDelayNanoseconds
        )
    }

    @MainActor
    private func enqueue(
        _ eventID: String,
        in coordinator: HomeTimelineDependencyResolutionCoordinator
    ) -> Bool {
        coordinator.enqueueSourceDependencies(
            NostrEventDependencies(sourceEventIDs: [eventID]),
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: ["wss://relay.example"],
            now: 100
        )
    }

    private func completion(for packet: NostrREQPacket) -> NostrBackwardREQCompletion {
        NostrBackwardREQCompletion(
            groupID: packet.groupID,
            relayURLs: packet.relayURLs,
            subscriptionIDs: [packet.subscriptionID],
            eventCount: 2,
            eoseCount: 1,
            closedCount: 0,
            timeoutCount: 0
        )
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw HomeTimelineDependencyResolutionCoordinatorTestError.timeout
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

@MainActor
private final class SourceInstallFailureProbe {
    var messages: [String] = []
}

private actor SourcePacketInstallerStub {
    enum Outcome: Sendable {
        case success
        case failure
        case delayedFailure(UInt64)
    }

    private let outcome: Outcome
    private var installedPackets: [[NostrREQPacket]] = []
    private var completed = 0

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func install(_ packets: [NostrREQPacket]) async throws {
        installedPackets.append(packets)
        switch outcome {
        case .success:
            completed += 1
        case .failure:
            completed += 1
            throw SourcePacketInstallerStubError.failed
        case .delayedFailure(let delayNanoseconds):
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            completed += 1
            throw SourcePacketInstallerStubError.failed
        }
    }

    func callCount() -> Int {
        installedPackets.count
    }

    func completedCount() -> Int {
        completed
    }

    func installations() -> [[NostrREQPacket]] {
        installedPackets
    }
}

private enum SourcePacketInstallerStubError: LocalizedError {
    case failed

    var errorDescription: String? {
        "stub source install failed"
    }
}

private enum HomeTimelineDependencyResolutionCoordinatorTestError: Error {
    case timeout
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
