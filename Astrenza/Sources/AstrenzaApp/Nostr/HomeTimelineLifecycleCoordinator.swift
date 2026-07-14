import Foundation

struct HomeTimelineLifecycleToken: Equatable, Sendable {
    let accountID: String
    let generation: UInt64
}

@MainActor
final class HomeTimelineLifecycleCoordinator {
    typealias Operation = @MainActor @Sendable () async -> Void

    private(set) var currentToken: HomeTimelineLifecycleToken?
    private(set) var hasCompletedRuntimeBootstrap = false

    private var generation: UInt64 = 0
    private var loadSequence: UInt64 = 0
    private var paginationSequence: UInt64 = 0
    private var loadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?

    deinit {
        loadTask?.cancel()
        paginationTask?.cancel()
    }

    @discardableResult
    func begin(accountID: String) -> HomeTimelineLifecycleToken {
        generation &+= 1
        cancelTasks()
        hasCompletedRuntimeBootstrap = false

        let token = HomeTimelineLifecycleToken(
            accountID: accountID,
            generation: generation
        )
        currentToken = token
        return token
    }

    @discardableResult
    func cancel() -> UInt64 {
        generation &+= 1
        currentToken = nil
        hasCompletedRuntimeBootstrap = false
        cancelTasks()
        return generation
    }

    func token(for accountID: String) -> HomeTimelineLifecycleToken? {
        guard let currentToken,
              currentToken.accountID == accountID
        else { return nil }
        return currentToken
    }

    func isCurrent(_ token: HomeTimelineLifecycleToken) -> Bool {
        currentToken == token
    }

    @discardableResult
    func setRuntimeBootstrapCompleted(
        _ isCompleted: Bool,
        for token: HomeTimelineLifecycleToken
    ) -> Bool {
        guard isCurrent(token) else { return false }
        hasCompletedRuntimeBootstrap = isCompleted
        return true
    }

    func startLoad(
        for token: HomeTimelineLifecycleToken,
        operation: @escaping Operation
    ) {
        guard isCurrent(token) else { return }

        loadSequence &+= 1
        let expectedSequence = loadSequence
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await operation()
            guard let self,
                  isCurrent(token),
                  loadSequence == expectedSequence
            else { return }
            loadTask = nil
        }
    }

    func startPagination(
        for token: HomeTimelineLifecycleToken,
        operation: @escaping Operation
    ) {
        guard isCurrent(token) else { return }

        paginationSequence &+= 1
        let expectedSequence = paginationSequence
        paginationTask?.cancel()
        paginationTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await operation()
            guard let self,
                  isCurrent(token),
                  paginationSequence == expectedSequence
            else { return }
            paginationTask = nil
        }
    }

    private func cancelTasks() {
        loadSequence &+= 1
        paginationSequence &+= 1
        loadTask?.cancel()
        paginationTask?.cancel()
        loadTask = nil
        paginationTask = nil
    }
}
