import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime application effects")
@MainActor
struct HomeTimelineRuntimeApplicationTests {
    @Test("Scheduled deletion reloads before preserving realtime follow")
    func scheduledDeletionPreservesOrder() {
        let fixture = RuntimeApplicationFixture()

        fixture.effects.reloadProjection(
            "anchor",
            .scheduled(allowsRealtimeFollow: true)
        )

        #expect(fixture.probe.events == [
            .reloadProjection(accountID: fixture.account.pubkey, anchorEventID: "anchor"),
            .scheduleMaterialization(delay: nil, allowsRealtimeFollow: true)
        ])
    }

    @Test("Immediate deletion reloads before synchronous materialization")
    func immediateDeletionPreservesOrder() {
        let fixture = RuntimeApplicationFixture()

        fixture.effects.reloadProjection("anchor", .immediate)

        #expect(fixture.probe.events == [
            .reloadProjection(accountID: fixture.account.pubkey, anchorEventID: "anchor"),
            .materializeEntries
        ])
    }

    @Test("Newest, standard, and dependency schedules retain their distinct policies")
    func materializationPoliciesRemainDistinct() {
        let fixture = RuntimeApplicationFixture(deferredDelay: 240)

        fixture.effects.reloadNewestProjection(false)
        fixture.effects.scheduleMaterialization(.standard)
        fixture.effects.scheduleMaterialization(.deferredDependencies)

        #expect(fixture.probe.events == [
            .requestNewestProjectionReload,
            .scheduleMaterialization(delay: nil, allowsRealtimeFollow: false),
            .scheduleMaterialization(delay: nil, allowsRealtimeFollow: nil),
            .scheduleMaterialization(delay: 240, allowsRealtimeFollow: nil)
        ])
    }

    @Test("Metadata persistence captures current projection state for the supplied account")
    func metadataPersistenceBuildsCurrentSnapshot() async throws {
        let fixture = RuntimeApplicationFixture()
        let persistenceAccount = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "persistence",
            readOnly: true
        )

        await fixture.effects.persistTimelineMetadata(persistenceAccount)

        let snapshot = try #require(fixture.persistence.metadataSnapshots.first)
        #expect(snapshot == RuntimeApplicationMetadataSnapshot(
            accountID: persistenceAccount.pubkey,
            relays: fixture.resolvedRelays,
            followedPubkeys: fixture.followedPubkeys,
            nip05Resolutions: fixture.nip05Resolutions,
            hasMoreOlder: false
        ))
    }

    @Test("Source installation failures use the first relay and the runtime fallback")
    func sourceFailureChoosesDiagnosticRelay() {
        let resolved = RuntimeApplicationFixture(
            resolvedRelays: ["wss://first.example", "wss://second.example"]
        )
        let fallback = RuntimeApplicationFixture(resolvedRelays: [])

        resolved.effects.sourceInstallFailed("relay unavailable")
        fallback.effects.sourceInstallFailed("relay unavailable")

        let message = "backward enqueue failed: relay unavailable"
        #expect(resolved.probe.events == [
            .diagnostic(HomeTimelineRuntimeApplicationDiagnostic(
                relayURL: "wss://first.example",
                message: message
            ))
        ])
        #expect(fallback.probe.events == [
            .diagnostic(HomeTimelineRuntimeApplicationDiagnostic(
                relayURL: "runtime",
                message: message
            ))
        ])
    }

    @Test("Missing application state suppresses state-dependent side effects")
    func missingStateSuppressesDependentEffects() async {
        let fixture = RuntimeApplicationFixture(hasState: false)

        fixture.effects.reloadProjection(nil, .immediate)
        fixture.effects.scheduleMaterialization(.deferredDependencies)
        await fixture.effects.persistTimelineMetadata(fixture.account)
        fixture.effects.sourceInstallFailed("missing")

        #expect(fixture.probe.events.isEmpty)
        #expect(fixture.persistence.metadataSnapshots.isEmpty)
    }

    @Test("List invalidation and pending count changes remain direct state effects")
    func directStateEffectsRemainDirect() {
        let fixture = RuntimeApplicationFixture()

        fixture.effects.applyListProjectionInvalidation(
            HomeTimelineListProjectionInvalidation(revision: 9)
        )
        fixture.effects.applyPendingEventCountPublication(
            HomeTimelinePendingEventCountPublication(count: 4)
        )

        #expect(fixture.probe.events == [
            .listRevision(9),
            .pendingCount(4)
        ])
    }
}

@MainActor
private final class RuntimeApplicationStateApplyingStub: HomeTimelineStateApplying {
    func restoreCachedState(
        accountID: String,
        handlers: HomeTimelineStateApplicationHandlers
    ) async -> Bool {
        _ = accountID
        _ = handlers
        return false
    }

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        handlers: HomeTimelineStateApplicationHandlers
    ) {
        _ = state
        _ = accountID
        _ = handlers
    }
}

private struct RuntimeApplicationMetadataSnapshot: Equatable {
    let accountID: String
    let relays: [String]
    let followedPubkeys: [String]
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let hasMoreOlder: Bool
}

@MainActor
private final class RuntimeApplicationPersistenceSpy: HomeTimelineStatePersisting {
    var metadataSnapshots: [RuntimeApplicationMetadataSnapshot] = []

    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool {
        _ = input
        _ = handlers
        return false
    }

    func persistMetadata(
        _ snapshot: HomeTimelineMetadataSnapshot,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool {
        _ = handlers
        metadataSnapshots.append(RuntimeApplicationMetadataSnapshot(
            accountID: snapshot.accountID,
            relays: snapshot.relays,
            followedPubkeys: snapshot.followedPubkeys,
            nip05Resolutions: snapshot.nip05Resolutions,
            hasMoreOlder: snapshot.hasMoreOlder
        ))
        return true
    }
}

@MainActor
private final class RuntimeApplicationProbe {
    enum Event: Equatable {
        case reloadProjection(accountID: String, anchorEventID: String?)
        case requestNewestProjectionReload
        case scheduleMaterialization(delay: UInt64?, allowsRealtimeFollow: Bool?)
        case materializeEntries
        case diagnostic(HomeTimelineRuntimeApplicationDiagnostic)
        case listRevision(Int)
        case pendingCount(Int)
    }

    var events: [Event] = []
}

@MainActor
private struct RuntimeApplicationFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "runtime",
        readOnly: true
    )
    let resolvedRelays: [String]
    let followedPubkeys = [
        String(repeating: "c", count: 64),
        String(repeating: "d", count: 64)
    ]
    let nip05Resolutions = [
        "runtime@example.com": NostrNIP05Resolution(
            identifier: "runtime@example.com",
            pubkey: String(repeating: "e", count: 64),
            relays: ["wss://profile.example"],
            status: .verified
        )
    ]
    let hasState: Bool
    let deferredDelay: UInt64
    let persistence = RuntimeApplicationPersistenceSpy()
    let probe = RuntimeApplicationProbe()
    let workflow: HomeTimelineStateWorkflow

    init(
        resolvedRelays: [String] = ["wss://relay.example"],
        hasState: Bool = true,
        deferredDelay: UInt64 = 200
    ) {
        self.resolvedRelays = resolvedRelays
        self.hasState = hasState
        self.deferredDelay = deferredDelay
        self.workflow = HomeTimelineStateWorkflow(
            stateApplication: RuntimeApplicationStateApplyingStub(),
            persistence: persistence
        )
    }

    var effects: HomeTimelineRuntimeApplicationEffects {
        workflow.runtimeApplicationEffects(
            state: { [applicationState] in applicationState },
            actions: actions,
            effects: stateEffects
        )
    }

    private var applicationState: HomeTimelineRuntimeApplicationState? {
        guard hasState else { return nil }
        return HomeTimelineRuntimeApplicationState(
            account: account,
            resolvedRelays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: false,
            deferredMaterializationDelayNanoseconds: deferredDelay
        )
    }

    private var actions: HomeTimelineRuntimeApplicationActions {
        HomeTimelineRuntimeApplicationActions(
            reloadProjection: { [probe] account, anchorEventID in
                probe.events.append(.reloadProjection(
                    accountID: account.pubkey,
                    anchorEventID: anchorEventID
                ))
            },
            requestNewestProjectionReload: { [probe] in
                probe.events.append(.requestNewestProjectionReload)
            },
            scheduleMaterialization: { [probe] delay, allowsRealtimeFollow in
                probe.events.append(.scheduleMaterialization(
                    delay: delay,
                    allowsRealtimeFollow: allowsRealtimeFollow
                ))
            },
            materializeEntries: { [probe] in
                probe.events.append(.materializeEntries)
            },
            recordDiagnostic: { [probe] diagnostic in
                probe.events.append(.diagnostic(diagnostic))
            }
        )
    }

    private var stateEffects: HomeTimelineStateWorkflowEffects {
        HomeTimelineStateWorkflowEffects(
            applyPresentationTransition: { _ in },
            applyContentSnapshot: { _ in },
            applyRelayStatusSnapshot: { _ in },
            applyListProjectionInvalidation: { [probe] invalidation in
                probe.events.append(.listRevision(invalidation.revision))
            },
            applyPendingEventCountPublication: { [probe] publication in
                probe.events.append(.pendingCount(publication.count))
            },
            persistenceState: {
                HomeTimelinePersistenceState(
                    accountID: "account",
                    followedPubkeys: []
                )
            },
            hasPendingEvents: { false },
            materializeEntries: { [probe] in
                probe.events.append(.materializeEntries)
            }
        )
    }
}
