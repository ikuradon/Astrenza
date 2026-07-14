import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline outbox coordinator")
struct HomeTimelineOutboxCoordinatorTests {
    @Test("A completed drain reports relay results and schedules its retry")
    @MainActor
    func reportsRelayResultsAndSchedulesRetry() async throws {
        let drainer = OutboxDrainerStub(steps: [
            OutboxDrainStep(
                result: HomeTimelineOutboxDrainResult(
                    nextRetryAt: 101,
                    didRecordRelayResults: true
                )
            ),
            OutboxDrainStep(
                result: HomeTimelineOutboxDrainResult(
                    nextRetryAt: nil,
                    didRecordRelayResults: false
                )
            )
        ])
        let recorder = OutboxRelayResultsRecorder()
        let coordinator = makeCoordinator(drainer: drainer)
        defer { coordinator.cancel() }

        coordinator.activate(accountID: "account-a") {
            recorder.count += 1
        }

        try await waitUntil {
            let completedCount = await drainer.completedCount()
            return completedCount == 2 && !coordinator.hasScheduledDrain
        }
        let accountIDs = await drainer.recordedAccountIDs()
        #expect(accountIDs == ["account-a", "account-a"])
        #expect(recorder.count == 1)
        #expect(!coordinator.hasScheduledDrain)
    }

    @Test("An immediate request replaces a scheduled retry")
    @MainActor
    func immediateRequestReplacesRetry() async throws {
        let drainer = OutboxDrainerStub(steps: [
            OutboxDrainStep(
                result: HomeTimelineOutboxDrainResult(
                    nextRetryAt: 200,
                    didRecordRelayResults: false
                )
            ),
            OutboxDrainStep(
                result: HomeTimelineOutboxDrainResult(
                    nextRetryAt: nil,
                    didRecordRelayResults: false
                )
            )
        ])
        let coordinator = makeCoordinator(drainer: drainer)
        defer { coordinator.cancel() }

        coordinator.activate(accountID: "account-a", onRelayResultsRecorded: {})
        try await waitUntil {
            await drainer.completedCount() == 1
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let callCountBeforeImmediateRequest = await drainer.callCount()
        #expect(callCountBeforeImmediateRequest == 1)
        #expect(coordinator.hasScheduledDrain)

        coordinator.requestImmediateDrain()

        try await waitUntil {
            let completedCount = await drainer.completedCount()
            return completedCount == 2 && !coordinator.hasScheduledDrain
        }
        let accountIDs = await drainer.recordedAccountIDs()
        #expect(accountIDs == ["account-a", "account-a"])
        #expect(!coordinator.hasScheduledDrain)
    }

    @Test("Changing accounts invalidates an in-flight drain result")
    @MainActor
    func changingAccountsInvalidatesInFlightResult() async throws {
        let drainer = OutboxDrainerStub(steps: [
            OutboxDrainStep(
                result: HomeTimelineOutboxDrainResult(
                    nextRetryAt: 101,
                    didRecordRelayResults: true
                ),
                delayNanoseconds: 5_000_000_000
            ),
            OutboxDrainStep(
                result: HomeTimelineOutboxDrainResult(
                    nextRetryAt: nil,
                    didRecordRelayResults: false
                )
            )
        ])
        let recorder = OutboxRelayResultsRecorder()
        let coordinator = makeCoordinator(drainer: drainer)
        defer { coordinator.cancel() }

        coordinator.activate(accountID: "account-a") {
            recorder.count += 1
        }
        try await waitUntil {
            await drainer.callCount() == 1
        }

        coordinator.activate(accountID: "account-b") {
            recorder.count += 1
        }

        try await waitUntil {
            let completedCount = await drainer.completedCount()
            return completedCount == 2 && !coordinator.hasScheduledDrain
        }
        let accountIDs = await drainer.recordedAccountIDs()
        #expect(accountIDs == ["account-a", "account-b"])
        #expect(recorder.count == 0)
        #expect(coordinator.activeAccountID == "account-b")
        #expect(!coordinator.hasScheduledDrain)
    }

    @MainActor
    private func makeCoordinator(
        drainer: OutboxDrainerStub
    ) -> HomeTimelineOutboxCoordinator {
        HomeTimelineOutboxCoordinator(
            drainer: drainer,
            now: { 100 },
            retryNanosecondsPerSecond: 10_000_000
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
        throw HomeTimelineOutboxCoordinatorTestError.timeout
    }
}

private struct OutboxDrainStep: Sendable {
    let result: HomeTimelineOutboxDrainResult
    var delayNanoseconds: UInt64 = 0
}

private actor OutboxDrainerStub: HomeTimelineOutboxDraining {
    private let steps: [OutboxDrainStep]
    private var accountIDs: [String] = []
    private var completed = 0

    init(steps: [OutboxDrainStep]) {
        self.steps = steps
    }

    func drain(accountID: String, now: Int) async -> HomeTimelineOutboxDrainResult {
        let stepIndex = accountIDs.count
        accountIDs.append(accountID)
        let step = steps[stepIndex]
        if step.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: step.delayNanoseconds)
        }
        completed += 1
        return step.result
    }

    func callCount() -> Int {
        accountIDs.count
    }

    func completedCount() -> Int {
        completed
    }

    func recordedAccountIDs() -> [String] {
        accountIDs
    }
}

@MainActor
private final class OutboxRelayResultsRecorder {
    var count = 0
}

private enum HomeTimelineOutboxCoordinatorTestError: Error {
    case timeout
}
