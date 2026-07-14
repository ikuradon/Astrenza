import Testing
@testable import Astrenza

@Suite("Home timeline lifecycle coordinator")
struct HomeTimelineLifecycleCoordinatorTests {
    @Test("Beginning a lifecycle invalidates the previous token and resets bootstrap state")
    @MainActor
    func beginInvalidatesPreviousToken() {
        let coordinator = HomeTimelineLifecycleCoordinator()
        let first = coordinator.begin(accountID: "alice")

        #expect(coordinator.setRuntimeBootstrapCompleted(true, for: first))
        #expect(coordinator.hasCompletedRuntimeBootstrap)

        let second = coordinator.begin(accountID: "bob")

        #expect(!coordinator.isCurrent(first))
        #expect(coordinator.isCurrent(second))
        #expect(coordinator.token(for: "alice") == nil)
        #expect(coordinator.token(for: "bob") == second)
        #expect(!coordinator.hasCompletedRuntimeBootstrap)
        #expect(!coordinator.setRuntimeBootstrapCompleted(true, for: first))
        #expect(!coordinator.hasCompletedRuntimeBootstrap)
    }

    @Test("Replacing pagination cancels the previous operation without losing the latest task")
    @MainActor
    func replacingPaginationPreservesLatestTaskOwnership() async throws {
        let coordinator = HomeTimelineLifecycleCoordinator()
        let recorder = HomeTimelineLifecycleRecorder()
        let token = coordinator.begin(accountID: "alice")
        defer { coordinator.cancel() }

        coordinator.startPagination(for: token) {
            await recorder.append("first-started")
            while !Task.isCancelled {
                await Task.yield()
            }
            await recorder.append("first-cancelled")
        }
        try #require(await waitUntil {
            await recorder.contains("first-started")
        })

        coordinator.startPagination(for: token) {
            await recorder.append("second-started")
            while !Task.isCancelled {
                await Task.yield()
            }
            await recorder.append("second-cancelled")
        }
        try #require(await waitUntil {
            await recorder.containsAll(["first-cancelled", "second-started"])
        })

        coordinator.cancel()
        try #require(await waitUntil {
            await recorder.contains("second-cancelled")
        })

        #expect(coordinator.currentToken == nil)
    }

    @Test("Cancelling a lifecycle cancels load and pagination and rejects their token")
    @MainActor
    func cancelStopsOwnedOperations() async throws {
        let coordinator = HomeTimelineLifecycleCoordinator()
        let recorder = HomeTimelineLifecycleRecorder()
        let token = coordinator.begin(accountID: "alice")
        defer { coordinator.cancel() }

        coordinator.startLoad(for: token) {
            await recorder.append("load-started")
            while !Task.isCancelled {
                await Task.yield()
            }
            await recorder.append("load-cancelled")
        }
        coordinator.startPagination(for: token) {
            await recorder.append("pagination-started")
            while !Task.isCancelled {
                await Task.yield()
            }
            await recorder.append("pagination-cancelled")
        }
        try #require(await waitUntil {
            await recorder.containsAll(["load-started", "pagination-started"])
        })

        coordinator.cancel()
        try #require(await waitUntil {
            await recorder.containsAll(["load-cancelled", "pagination-cancelled"])
        })

        #expect(!coordinator.isCurrent(token))
        #expect(coordinator.token(for: "alice") == nil)
        #expect(!coordinator.hasCompletedRuntimeBootstrap)
    }

    @Test("Releasing the coordinator cancels its owned operations")
    @MainActor
    func deinitCancelsOwnedOperations() async throws {
        let recorder = HomeTimelineLifecycleRecorder()
        var coordinator: HomeTimelineLifecycleCoordinator? = HomeTimelineLifecycleCoordinator()
        let token = try #require(coordinator?.begin(accountID: "alice"))

        coordinator?.startLoad(for: token) {
            await recorder.append("load-started")
            while !Task.isCancelled {
                await Task.yield()
            }
            await recorder.append("load-cancelled")
        }
        try #require(await waitUntil {
            await recorder.contains("load-started")
        })

        coordinator = nil

        try #require(await waitUntil {
            await recorder.contains("load-cancelled")
        })
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if await predicate() { return true }
            await Task.yield()
        }
        return false
    }
}

private actor HomeTimelineLifecycleRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func contains(_ value: String) -> Bool {
        values.contains(value)
    }

    func containsAll(_ expectedValues: [String]) -> Bool {
        expectedValues.allSatisfy(values.contains)
    }
}
