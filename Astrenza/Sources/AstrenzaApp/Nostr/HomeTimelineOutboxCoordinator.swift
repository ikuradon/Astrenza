import Foundation

protocol HomeTimelineOutboxDraining: Sendable {
    func drain(accountID: String, now: Int) async -> HomeTimelineOutboxDrainResult
}

@MainActor
protocol HomeTimelineOutboxActivating: AnyObject {
    func activate(
        accountID: String,
        onRelayResultsRecorded: @escaping @MainActor @Sendable () -> Void
    )
}

@MainActor
protocol HomeTimelineOutboxDrainScheduling: AnyObject {
    func requestImmediateDrain()
}

@MainActor
final class HomeTimelineOutboxCoordinator {
    typealias RelayResultsHandler = @MainActor @Sendable () -> Void
    typealias NowProvider = @MainActor @Sendable () -> Int

    private let drainer: any HomeTimelineOutboxDraining
    private let now: NowProvider
    private let retryNanosecondsPerSecond: UInt64

    private var drainTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var accountID: String?
    private var relayResultsHandler: RelayResultsHandler?

    var activeAccountID: String? {
        accountID
    }

    var hasScheduledDrain: Bool {
        drainTask != nil
    }

    init(
        drainer: any HomeTimelineOutboxDraining,
        now: @escaping NowProvider = { Int(Date().timeIntervalSince1970) },
        retryNanosecondsPerSecond: UInt64 = 1_000_000_000
    ) {
        self.drainer = drainer
        self.now = now
        self.retryNanosecondsPerSecond = retryNanosecondsPerSecond
    }

    func activate(
        accountID: String,
        onRelayResultsRecorded: @escaping RelayResultsHandler
    ) {
        if self.accountID != accountID {
            cancel()
            self.accountID = accountID
        }
        relayResultsHandler = onRelayResultsRecorded
        scheduleDrain()
    }

    func requestImmediateDrain() {
        guard accountID != nil else { return }
        scheduleDrain()
    }

    func cancel() {
        generation &+= 1
        drainTask?.cancel()
        drainTask = nil
        accountID = nil
        relayResultsHandler = nil
    }

    private func scheduleDrain(delayNanoseconds: UInt64 = 0) {
        if drainTask != nil {
            guard delayNanoseconds == 0 else { return }
            generation &+= 1
            drainTask?.cancel()
            drainTask = nil
        }
        guard let accountID else { return }

        generation &+= 1
        let taskGeneration = generation
        drainTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
            }
            guard let self else { return }

            let drainNow = now()
            let result = await drainer.drain(accountID: accountID, now: drainNow)
            guard generation == taskGeneration,
                  self.accountID == accountID
            else { return }

            drainTask = nil
            if result.didRecordRelayResults {
                relayResultsHandler?()
            }
            guard !Task.isCancelled,
                  let nextRetryAt = result.nextRetryAt
            else { return }

            let delaySeconds = max(1, nextRetryAt - now())
            scheduleDrain(
                delayNanoseconds: UInt64(delaySeconds) * retryNanosecondsPerSecond
            )
        }
    }
}

extension HomeTimelineOutboxCoordinator:
    HomeTimelineOutboxActivating,
    HomeTimelineOutboxDrainScheduling {}
