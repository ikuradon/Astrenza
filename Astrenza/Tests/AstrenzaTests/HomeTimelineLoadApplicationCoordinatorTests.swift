import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline remote load application coordinator")
@MainActor
struct HomeTimelineLoadApplicationTests {
    @Test(
        "Loaded standard requests share the complete application sequence",
        arguments: StandardLoadedCase.all
    )
    func loadedStandardRequest(_ testCase: StandardLoadedCase) async {
        let system = RemoteLoadApplicationTestSystem()

        await system.application.apply(
            .loaded(system.state),
            context: system.context(operation: testCase.operation),
            handlers: system.handlers()
        )

        #expect(system.probe.steps == [
            .command(.replaceState(system.state, replacement: .complete)),
            .command(.materializeEntries),
            .persist(system.account.pubkey),
            .configure(system.account.pubkey),
            .command(.setPhase(.loaded))
        ])
        #expect(!system.lifecycle.hasCompletedRuntimeBootstrap)
    }

    @Test("Loaded bootstrap uses its state replacement and marks bootstrap complete")
    func loadedBootstrapMarksCompletion() async {
        let system = RemoteLoadApplicationTestSystem()

        await system.application.apply(
            .loaded(system.state),
            context: system.context(
                operation: .runtimeBootstrap(hadCachedBootstrap: false)
            ),
            handlers: system.handlers()
        )

        #expect(system.probe.steps == [
            .command(.replaceState(system.state, replacement: .runtimeBootstrap)),
            .command(.materializeEntries),
            .persist(system.account.pubkey),
            .configure(system.account.pubkey),
            .command(.setPhase(.loaded))
        ])
        #expect(system.lifecycle.hasCompletedRuntimeBootstrap)
    }

    @Test("An exhausted older page only replaces state")
    func exhaustedOlderPageStopsBeforePersistence() async {
        let system = RemoteLoadApplicationTestSystem(hasMoreOlder: false)

        await system.application.apply(
            .loaded(system.state),
            context: system.context(operation: .older),
            handlers: system.handlers()
        )

        #expect(system.probe.steps == [
            .command(.replaceState(system.state, replacement: .complete))
        ])
    }

    @Test(
        "Standard failures use operation-specific messages",
        arguments: StandardFailureCase.all
    )
    func standardFailure(_ testCase: StandardFailureCase) async {
        let system = RemoteLoadApplicationTestSystem()

        await system.application.apply(
            .failed("unavailable"),
            context: system.context(operation: testCase.operation),
            handlers: system.handlers()
        )

        #expect(system.probe.steps == [
            .command(.setPhase(.failed(testCase.expectedMessage)))
        ])
    }

    @Test("A cached bootstrap failure records a diagnostic and keeps loaded state")
    func cachedBootstrapFailureKeepsLoadedState() async {
        let system = RemoteLoadApplicationTestSystem()
        system.lifecycle.setRuntimeBootstrapCompleted(true, for: system.lifecycleToken)

        await system.application.apply(
            .failed("unavailable"),
            context: system.context(
                operation: .runtimeBootstrap(hadCachedBootstrap: true)
            ),
            handlers: system.handlers()
        )

        #expect(system.probe.steps == [
            .command(.recordDiagnostic(system.bootstrapDiagnostic)),
            .command(.setPhase(.loaded))
        ])
        #expect(system.lifecycle.hasCompletedRuntimeBootstrap)
    }

    @Test("An uncached bootstrap failure uses the provisional relay fallback")
    func uncachedBootstrapFailureUsesRelayFallback() async {
        let system = RemoteLoadApplicationTestSystem()

        await system.application.apply(
            .failed("unavailable"),
            context: system.context(
                operation: .runtimeBootstrap(hadCachedBootstrap: false)
            ),
            handlers: system.handlers()
        )

        #expect(system.probe.steps == [
            .command(.recordDiagnostic(system.bootstrapDiagnostic)),
            .command(.replaceFollowedPubkeys([system.account.pubkey])),
            .configure(system.account.pubkey),
            .command(.setPhase(.loaded))
        ])
        #expect(system.lifecycle.hasCompletedRuntimeBootstrap)
    }

    @Test("A bootstrap failure without any relay becomes a terminal failure")
    func bootstrapFailureWithoutRelayFails() async {
        let system = RemoteLoadApplicationTestSystem(resolvedRelays: [])

        await system.application.apply(
            .failed("unavailable"),
            context: system.context(
                operation: .runtimeBootstrap(hadCachedBootstrap: false)
            ),
            handlers: system.handlers()
        )

        #expect(system.probe.steps == [
            .command(.recordDiagnostic(HomeTimelineLoadDiagnostic(
                relayURL: "runtime",
                kind: .partialFailure,
                subscriptionID: "astrenza-bootstrap",
                message: "bootstrap refresh failed: unavailable"
            ))),
            .command(.setPhase(.failed("Home timeline failed: unavailable")))
        ])
        #expect(!system.lifecycle.hasCompletedRuntimeBootstrap)
    }

    @Test("Lifecycle invalidation during persistence suppresses runtime configuration")
    func invalidationDuringPersistenceStopsApplication() async {
        let system = RemoteLoadApplicationTestSystem()

        await system.application.apply(
            .loaded(system.state),
            context: system.context(operation: .refresh),
            handlers: system.handlers(didPersist: {
                system.lifecycle.cancel()
            })
        )

        #expect(system.probe.steps == [
            .command(.replaceState(system.state, replacement: .complete)),
            .command(.materializeEntries),
            .persist(system.account.pubkey)
        ])
    }

    @Test("Lifecycle invalidation during runtime configuration suppresses loaded phase")
    func invalidationDuringConfigurationStopsApplication() async {
        let system = RemoteLoadApplicationTestSystem()

        await system.application.apply(
            .loaded(system.state),
            context: system.context(operation: .initial),
            handlers: system.handlers(didConfigure: {
                system.lifecycle.cancel()
            })
        )

        #expect(system.probe.steps == [
            .command(.replaceState(system.state, replacement: .complete)),
            .command(.materializeEntries),
            .persist(system.account.pubkey),
            .configure(system.account.pubkey)
        ])
    }

    @Test("Cancelled outcomes perform no application work")
    func cancelledOutcomePerformsNoWork() async {
        let system = RemoteLoadApplicationTestSystem()

        await system.application.apply(
            .cancelled,
            context: system.context(operation: .initial),
            handlers: system.handlers()
        )

        #expect(system.probe.steps.isEmpty)
    }

    @Test("An outcome for a stale lifecycle performs no application work")
    func staleLifecyclePerformsNoWork() async {
        let system = RemoteLoadApplicationTestSystem()
        system.lifecycle.cancel()

        await system.application.apply(
            .loaded(system.state),
            context: system.context(operation: .initial),
            handlers: system.handlers()
        )

        #expect(system.probe.steps.isEmpty)
    }

    @Test("An already cancelled task performs no application work")
    func cancelledTaskPerformsNoWork() async {
        let system = RemoteLoadApplicationTestSystem()

        await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            await system.application.apply(
                .loaded(system.state),
                context: system.context(operation: .initial),
                handlers: system.handlers()
            )
        }.value

        #expect(system.probe.steps.isEmpty)
    }
}

struct StandardLoadedCase: Sendable, CustomTestStringConvertible {
    let operation: HomeTimelineLoadOperation
    let testDescription: String

    static let all = [
        StandardLoadedCase(operation: .initial, testDescription: "initial"),
        StandardLoadedCase(operation: .refresh, testDescription: "refresh"),
        StandardLoadedCase(operation: .older, testDescription: "older")
    ]
}

struct StandardFailureCase: Sendable, CustomTestStringConvertible {
    let operation: HomeTimelineLoadOperation
    let expectedMessage: String
    let testDescription: String

    static let all = [
        StandardFailureCase(
            operation: .initial,
            expectedMessage: "Home timeline failed: unavailable",
            testDescription: "initial"
        ),
        StandardFailureCase(
            operation: .refresh,
            expectedMessage: "Refresh failed: unavailable",
            testDescription: "refresh"
        ),
        StandardFailureCase(
            operation: .older,
            expectedMessage: "Older notes failed: unavailable",
            testDescription: "older"
        )
    ]
}

private enum RemoteLoadApplicationStep: Equatable {
    case command(HomeTimelineLoadApplicationCommand)
    case persist(String)
    case configure(String)
}

@MainActor
private final class RemoteLoadApplicationProbe {
    var steps: [RemoteLoadApplicationStep] = []
}

@MainActor
private struct RemoteLoadApplicationTestSystem {
    typealias Callback = @MainActor @Sendable () -> Void

    let account: NostrAccount
    let state: NostrHomeTimelineState
    let resolvedRelays: [String]
    let lifecycle: HomeTimelineLifecycleCoordinator
    let lifecycleToken: HomeTimelineLifecycleToken
    let application: HomeTimelineLoadApplicationCoordinator
    let probe = RemoteLoadApplicationProbe()

    var bootstrapDiagnostic: HomeTimelineLoadDiagnostic {
        HomeTimelineLoadDiagnostic(
            relayURL: resolvedRelays.first ?? "runtime",
            kind: .partialFailure,
            subscriptionID: "astrenza-bootstrap",
            message: "bootstrap refresh failed: unavailable"
        )
    }

    init(
        hasMoreOlder: Bool = true,
        resolvedRelays: [String] = ["wss://relay.example"]
    ) {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let lifecycle = HomeTimelineLifecycleCoordinator()
        self.account = account
        self.state = NostrHomeTimelineState(
            relays: resolvedRelays,
            followedPubkeys: [account.pubkey],
            noteEvents: [],
            metadataEvents: [],
            hasMoreOlder: hasMoreOlder
        )
        self.resolvedRelays = resolvedRelays
        self.lifecycle = lifecycle
        self.lifecycleToken = lifecycle.begin(accountID: account.pubkey)
        self.application = HomeTimelineLoadApplicationCoordinator(
            lifecycleCoordinator: lifecycle
        )
    }

    func context(
        operation: HomeTimelineLoadOperation
    ) -> HomeTimelineLoadApplicationContext {
        HomeTimelineLoadApplicationContext(
            account: account,
            lifecycle: lifecycleToken,
            operation: operation,
            resolvedRelays: resolvedRelays
        )
    }

    func handlers(
        didPersist: Callback? = nil,
        didConfigure: Callback? = nil
    ) -> HomeTimelineLoadApplicationHandlers {
        HomeTimelineLoadApplicationHandlers(
            perform: { [probe] command in
                probe.steps.append(.command(command))
            },
            persistDatabase: { [probe] account in
                probe.steps.append(.persist(account.pubkey))
                didPersist?()
            },
            configureRelayRuntime: { [probe] account in
                probe.steps.append(.configure(account.pubkey))
                didConfigure?()
            }
        )
    }
}
