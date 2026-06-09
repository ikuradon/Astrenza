import Foundation
import Testing
import AstrenzaCore
@testable import Astrenza

@Suite("Nostr timeline projection")
struct NostrTimelineProjectionTests {
    @Test("Projection facade matches materializer entry IDs")
    func projectionFacadeMatchesMaterializerEntryIDs() {
        let author = String(repeating: "a", count: 64)
        let note = projectionEvent(idSeed: "1", pubkey: author, createdAt: 100, content: "projection")
        let materialized = NostrTimelineMaterializer.entries(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author]
        )

        let projected = NostrTimelineProjection.entries(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author]
        )

        #expect(projected.map(\.id) == materialized.map(\.id))
    }

    @Test("Projection refresh coordinator runs a scheduled refresh once")
    @MainActor
    func projectionRefreshCoordinatorRunsScheduledRefresh() async throws {
        let coordinator = NostrProjectionRefreshCoordinator(delayNanoseconds: 50_000_000)
        var refreshCount = 0

        coordinator.schedule {
            refreshCount += 1
        }

        for _ in 0..<25 where refreshCount == 0 {
            try await Task.sleep(nanoseconds: 40_000_000)
            await Task.yield()
        }
        #expect(refreshCount == 1)
    }

    @Test("Projection refresh coordinator coalesces multiple pending refreshes")
    @MainActor
    func projectionRefreshCoordinatorCoalescesPendingRefreshes() async throws {
        let coordinator = NostrProjectionRefreshCoordinator(delayNanoseconds: 50_000_000)
        var refreshCount = 0

        coordinator.schedule {
            refreshCount += 1
        }
        await Task.yield()
        coordinator.schedule {
            refreshCount += 10
        }

        for _ in 0..<25 where refreshCount == 0 {
            try await Task.sleep(nanoseconds: 40_000_000)
            await Task.yield()
        }
        #expect(refreshCount == 1)
    }

    @Test("Projection refresh coordinator supports per-schedule delay")
    @MainActor
    func projectionRefreshCoordinatorSupportsPerScheduleDelay() async throws {
        let coordinator = NostrProjectionRefreshCoordinator(delayNanoseconds: 200_000_000)
        var refreshCount = 0

        coordinator.schedule(delayNanoseconds: 20_000_000) {
            refreshCount += 1
        }

        for _ in 0..<25 where refreshCount == 0 {
            try await Task.sleep(nanoseconds: 40_000_000)
            await Task.yield()
        }
        #expect(refreshCount == 1)
    }

    @Test("Projection refresh coordinator flushes immediately")
    @MainActor
    func projectionRefreshCoordinatorFlushesImmediately() async throws {
        let coordinator = NostrProjectionRefreshCoordinator(delayNanoseconds: 100_000_000)
        var refreshCount = 0

        coordinator.schedule {
            refreshCount += 100
        }
        coordinator.flush {
            refreshCount += 1
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(refreshCount == 1)
    }

    @Test("Projection refresh coordinator cancels pending refreshes")
    @MainActor
    func projectionRefreshCoordinatorCancelsPendingRefresh() async throws {
        let coordinator = NostrProjectionRefreshCoordinator(delayNanoseconds: 20_000_000)
        var refreshCount = 0

        coordinator.schedule {
            refreshCount += 1
        }
        coordinator.cancel()

        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(refreshCount == 0)
    }
}

private func projectionEvent(idSeed: Character, pubkey: String, createdAt: Int, content: String) -> NostrEvent {
    NostrEvent(
        id: String(repeating: String(idSeed), count: 64),
        pubkey: pubkey,
        createdAt: createdAt,
        kind: 1,
        tags: [],
        content: content,
        sig: String(repeating: "5", count: 128)
    )
}
