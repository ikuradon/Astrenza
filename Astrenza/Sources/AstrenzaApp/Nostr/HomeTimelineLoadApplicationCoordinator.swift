import AstrenzaCore

enum HomeTimelineLoadOperation: Equatable, Sendable {
    case initial
    case runtimeBootstrap(hadCachedBootstrap: Bool)
    case refresh
    case older
}

enum HomeTimelineLoadStateReplacement: Equatable, Sendable {
    case complete
    case runtimeBootstrap
}

struct HomeTimelineLoadApplicationContext: Equatable, Sendable {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
    let operation: HomeTimelineLoadOperation
    let resolvedRelays: [String]
}

struct HomeTimelineLoadDiagnostic: Equatable, Sendable {
    let relayURL: String
    let kind: NostrRelaySyncEventKind
    let subscriptionID: String?
    let message: String
}

enum HomeTimelineLoadApplicationCommand: Equatable, Sendable {
    case replaceState(
        NostrHomeTimelineState,
        replacement: HomeTimelineLoadStateReplacement
    )
    case replaceFollowedPubkeys([String])
    case materializeEntries
    case recordDiagnostic(HomeTimelineLoadDiagnostic)
    case setPhase(NostrHomeTimelinePhase)
}

struct HomeTimelineLoadApplicationHandlers: Sendable {
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineLoadApplicationCommand
    ) -> Void
    typealias AccountHandler = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void

    let perform: CommandHandler
    let persistDatabase: AccountHandler
    let configureRelayRuntime: AccountHandler
}

@MainActor
final class HomeTimelineLoadApplicationCoordinator {
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator

    init(lifecycleCoordinator: HomeTimelineLifecycleCoordinator) {
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    func apply(
        _ outcome: HomeTimelineRemoteLoadOutcome,
        context: HomeTimelineLoadApplicationContext,
        handlers: HomeTimelineLoadApplicationHandlers
    ) async {
        guard isActive(context) else { return }

        switch outcome {
        case .loaded(let state):
            await applyLoadedState(state, context: context, handlers: handlers)
        case .cancelled:
            return
        case .failed(let message):
            await applyFailure(message, context: context, handlers: handlers)
        }
    }

    private func applyLoadedState(
        _ state: NostrHomeTimelineState,
        context: HomeTimelineLoadApplicationContext,
        handlers: HomeTimelineLoadApplicationHandlers
    ) async {
        let replacement: HomeTimelineLoadStateReplacement
        switch context.operation {
        case .runtimeBootstrap:
            replacement = .runtimeBootstrap
        case .initial, .refresh, .older:
            replacement = .complete
        }
        handlers.perform(.replaceState(state, replacement: replacement))

        if case .runtimeBootstrap = context.operation {
            lifecycleCoordinator.setRuntimeBootstrapCompleted(
                true,
                for: context.lifecycle
            )
        }
        handlers.perform(.materializeEntries)
        await handlers.persistDatabase(context.account)
        guard isActive(context) else { return }

        await handlers.configureRelayRuntime(context.account)
        guard isActive(context) else { return }
        handlers.perform(.setPhase(.loaded))
    }

    private func applyFailure(
        _ message: String,
        context: HomeTimelineLoadApplicationContext,
        handlers: HomeTimelineLoadApplicationHandlers
    ) async {
        switch context.operation {
        case .initial:
            handlers.perform(.setPhase(.failed("Home timeline failed: \(message)")))
        case .refresh:
            handlers.perform(.setPhase(.failed("Refresh failed: \(message)")))
        case .older:
            handlers.perform(.setPhase(.failed("Older notes failed: \(message)")))
        case .runtimeBootstrap(let hadCachedBootstrap):
            await applyBootstrapFailure(
                message,
                hadCachedBootstrap: hadCachedBootstrap,
                context: context,
                handlers: handlers
            )
        }
    }

    private func applyBootstrapFailure(
        _ message: String,
        hadCachedBootstrap: Bool,
        context: HomeTimelineLoadApplicationContext,
        handlers: HomeTimelineLoadApplicationHandlers
    ) async {
        handlers.perform(.recordDiagnostic(HomeTimelineLoadDiagnostic(
            relayURL: context.resolvedRelays.first ?? "runtime",
            kind: .partialFailure,
            subscriptionID: "astrenza-bootstrap",
            message: "bootstrap refresh failed: \(message)"
        )))

        if hadCachedBootstrap {
            handlers.perform(.setPhase(.loaded))
            return
        }
        guard !context.resolvedRelays.isEmpty else {
            handlers.perform(.setPhase(.failed("Home timeline failed: \(message)")))
            return
        }

        handlers.perform(.replaceFollowedPubkeys([context.account.pubkey]))
        lifecycleCoordinator.setRuntimeBootstrapCompleted(
            true,
            for: context.lifecycle
        )
        await handlers.configureRelayRuntime(context.account)
        guard isActive(context) else { return }
        handlers.perform(.setPhase(.loaded))
    }

    private func isActive(
        _ context: HomeTimelineLoadApplicationContext
    ) -> Bool {
        !Task.isCancelled &&
            lifecycleCoordinator.isCurrent(context.lifecycle) &&
            context.lifecycle.accountID == context.account.pubkey
    }
}
