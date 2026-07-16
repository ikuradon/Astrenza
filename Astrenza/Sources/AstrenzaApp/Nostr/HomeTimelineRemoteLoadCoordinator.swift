import AstrenzaCore

protocol HomeTimelineStateLoading: Sendable {
    var bootstrapRelays: [String] { get }

    func bootstrapState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?
    ) async throws -> NostrHomeTimelineState

    func initialState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?
    ) async throws -> NostrHomeTimelineState

    func refreshedState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        policy: NostrSyncPolicy
    ) async throws -> NostrHomeTimelineState

    func olderState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]?,
        policy: NostrSyncPolicy
    ) async throws -> NostrHomeTimelineState
}

extension NostrHomeTimelineLoader: HomeTimelineStateLoading {}

@MainActor
protocol HomeTimelineFetchedRelayEventPersisting: Sendable {
    func persistFetchedEvents(_ events: [NostrRelaySyncEventRecord]) async
}

extension HomeTimelineRelayStatusCoordinator:
    HomeTimelineFetchedRelayEventPersisting {}

enum HomeTimelineRemoteLoadRequest: Sendable {
    case initial(account: NostrAccount, policy: NostrSyncPolicy)
    case runtimeBootstrap(account: NostrAccount, policy: NostrSyncPolicy)
    case refresh(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        policy: NostrSyncPolicy
    )
    case older(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]?,
        policy: NostrSyncPolicy
    )
}

extension HomeTimelineRemoteLoadRequest {
    static func initial(account: NostrAccount) -> Self {
        .initial(account: account, policy: .default())
    }

    static func runtimeBootstrap(account: NostrAccount) -> Self {
        .runtimeBootstrap(account: account, policy: .default())
    }

    static func refresh(
        account: NostrAccount,
        current: NostrHomeTimelineState
    ) -> Self {
        .refresh(account: account, current: current, policy: .default())
    }

    static func older(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]?
    ) -> Self {
        .older(
            account: account,
            current: current,
            localBackfillEvents: localBackfillEvents,
            policy: .default()
        )
    }
}

enum HomeTimelineRemoteLoadOutcome: Equatable, Sendable {
    case loaded(NostrHomeTimelineState)
    case cancelled
    case failed(String)
}

@MainActor
final class HomeTimelineRemoteLoadCoordinator {
    typealias IsCurrent = @MainActor @Sendable () -> Bool
    typealias StageHandler = @MainActor @Sendable (NostrHomeTimelineLoadStage) -> Void
    typealias FetchHandler = @MainActor @Sendable () -> Void

    private let loader: any HomeTimelineStateLoading
    private let relayEventPersistence: any HomeTimelineFetchedRelayEventPersisting

    init(
        loader: any HomeTimelineStateLoading,
        relayEventPersistence: any HomeTimelineFetchedRelayEventPersisting
    ) {
        self.loader = loader
        self.relayEventPersistence = relayEventPersistence
    }

    var bootstrapRelays: [String] {
        loader.bootstrapRelays
    }

    func load(
        _ request: HomeTimelineRemoteLoadRequest,
        isCurrent: @escaping IsCurrent,
        didReceiveStage: StageHandler? = nil,
        didFetch: FetchHandler? = nil
    ) async -> HomeTimelineRemoteLoadOutcome {
        guard !Task.isCancelled, isCurrent() else { return .cancelled }

        do {
            let state = try await loadState(
                request,
                onStage: { stage in
                    guard !Task.isCancelled, await isCurrent() else { return }
                    await didReceiveStage?(stage)
                }
            )
            guard !Task.isCancelled, isCurrent() else { return .cancelled }
            didFetch?()
            await relayEventPersistence.persistFetchedEvents(state.relaySyncEvents)
            guard !Task.isCancelled, isCurrent() else { return .cancelled }
            return .loaded(state)
        } catch {
            guard !Task.isCancelled, isCurrent() else { return .cancelled }
            return .failed(error.localizedDescription)
        }
    }

    private func loadState(
        _ request: HomeTimelineRemoteLoadRequest,
        onStage: @escaping @Sendable (NostrHomeTimelineLoadStage) async -> Void
    ) async throws -> NostrHomeTimelineState {
        switch request {
        case .initial(let account, let policy):
            try await loader.initialState(
                account: account,
                policy: policy,
                onStage: onStage
            )
        case .runtimeBootstrap(let account, let policy):
            try await loader.bootstrapState(
                account: account,
                policy: policy,
                onStage: onStage
            )
        case .refresh(let account, let current, let policy):
            try await loader.refreshedState(
                account: account,
                current: current,
                policy: policy
            )
        case .older(let account, let current, let localBackfillEvents, let policy):
            try await loader.olderState(
                account: account,
                current: current,
                localBackfillEvents: localBackfillEvents,
                policy: policy
            )
        }
    }
}
