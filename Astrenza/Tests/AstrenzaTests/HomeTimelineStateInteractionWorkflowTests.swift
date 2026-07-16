import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline state interaction workflow")
@MainActor
struct HomeTimelineStateInteractionTests {
    @Test("State entry points preserve requests and coordinator results")
    func routesStateOperations() async {
        let fixture = StateInteractionFixture()

        let didRestore = await fixture.workflow.restoreCachedState(
            accountID: fixture.account.pubkey,
            context: fixture.context
        )
        fixture.workflow.replace(
            fixture.timelineState,
            accountID: "replacement",
            context: fixture.context
        )
        let didPersist = await fixture.workflow.persistSnapshot(
            fixture.snapshotInput,
            context: fixture.context
        )

        #expect(didRestore)
        #expect(!didPersist)
        #expect(fixture.router.restoredAccountID == fixture.account.pubkey)
        #expect(fixture.router.replacementAccountID == "replacement")
        #expect(fixture.router.replacementRelays == fixture.timelineState.relays)
        #expect(fixture.router.persistedAccountID == fixture.account.pubkey)
    }

    @Test("State projection remains dynamic behind the interaction boundary")
    func forwardsDynamicStateProjection() async {
        let fixture = StateInteractionFixture()
        let context = fixture.context
        fixture.router.readsEnvironment = true
        fixture.probe.persistenceState = HomeTimelinePersistenceState(
            accountID: "updated",
            followedPubkeys: ["dynamic-follow"]
        )
        fixture.probe.hasPendingEvents = false

        _ = await fixture.workflow.restoreCachedState(
            accountID: fixture.account.pubkey,
            context: context
        )
        _ = fixture.workflow.runtimeApplicationEffects(context: context)

        #expect(fixture.router.persistenceState == fixture.probe.persistenceState)
        #expect(fixture.router.hasPendingEvents == false)
        #expect(fixture.router.runtimeState?.account == fixture.account)
        #expect(fixture.probe.projectionReads == 3)

        fixture.probe.providesProjection = false
        _ = await fixture.workflow.restoreCachedState(
            accountID: fixture.account.pubkey,
            context: context
        )
        _ = fixture.workflow.runtimeApplicationEffects(context: context)

        #expect(fixture.router.persistenceState == HomeTimelinePersistenceState(
            accountID: nil,
            followedPubkeys: []
        ))
        #expect(fixture.router.hasPendingEvents == false)
        #expect(fixture.router.runtimeState == nil)
        #expect(fixture.probe.projectionReads == 6)
    }

    @Test("State and runtime applications share one typed application boundary")
    func routesApplications() async {
        let fixture = StateInteractionFixture()
        fixture.router.appliesEffects = true

        _ = await fixture.workflow.restoreCachedState(
            accountID: fixture.account.pubkey,
            context: fixture.context
        )
        _ = fixture.workflow.runtimeApplicationEffects(
            context: fixture.context
        )

        #expect(fixture.probe.applicationFixture.probe.events == [
            .presentation(changes: 0),
            .contentRelays(["wss://content.example"]),
            .relaySnapshot(plannedCount: 2),
            .listRevision(4),
            .pendingCount(3),
            .materializeEntries,
            .reloadProjection(
                accountID: fixture.router.applicationAccount.pubkey,
                anchorEventID: "anchor",
                mergingWithCurrentWindow: false
            ),
            .requestNewestProjectionReload,
            .scheduleMaterialization(
                delayNanoseconds: 120,
                allowsRealtimeFollow: true
            ),
            .materializeEntries,
            .relayTransition(fixture.relayStatus.transition)
        ])
        #expect(fixture.relayStatus.records == [
            HomeTimelineRelayStatusRecord(
                accountID: fixture.account.pubkey,
                resolvedRelays: ["wss://relay.example"],
                relayURL: fixture.router.diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: nil,
                eventCount: 0,
                newestCreatedAt: nil,
                oldestCreatedAt: nil,
                message: fixture.router.diagnostic.message
            )
        ])
    }
}

@MainActor
private final class StateInteractionRouterSpy: HomeTimelineStateRouting {
    let applicationAccount = NostrAccount(
        pubkey: String(repeating: "b", count: 64),
        displayIdentifier: "application",
        readOnly: true
    )
    let diagnostic = HomeTimelineRuntimeApplicationDiagnostic(
        relayURL: "wss://relay.example",
        message: "install failed"
    )
    var readsEnvironment = false
    var appliesEffects = false
    var restoredAccountID: String?
    var replacementAccountID: String?
    var replacementRelays: [String] = []
    var persistedAccountID: String?
    var persistenceState: HomeTimelinePersistenceState?
    var hasPendingEvents: Bool?
    var runtimeState: HomeTimelineRuntimeApplicationState?

    func restoreCachedState(
        accountID: String,
        effects: HomeTimelineStateWorkflowEffects
    ) async -> Bool {
        restoredAccountID = accountID
        if readsEnvironment {
            persistenceState = effects.persistenceState()
            hasPendingEvents = effects.hasPendingEvents()
        }
        if appliesEffects {
            applyStateEffects(effects)
        }
        return true
    }

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        effects _: HomeTimelineStateWorkflowEffects
    ) {
        replacementAccountID = accountID
        replacementRelays = state.relays
    }

    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        effects _: HomeTimelineStateWorkflowEffects
    ) async -> Bool {
        persistedAccountID = input.accountID
        return false
    }

    func runtimeApplicationEffects(
        state: @escaping HomeTimelineRuntimeApplicationState.Provider,
        actions: HomeTimelineRuntimeApplicationActions,
        effects _: HomeTimelineStateWorkflowEffects
    ) -> HomeTimelineRuntimeApplicationEffects {
        if readsEnvironment {
            runtimeState = state()
        }
        if appliesEffects {
            applyRuntimeActions(actions)
        }
        return emptyRuntimeEffects
    }

    private func applyStateEffects(
        _ effects: HomeTimelineStateWorkflowEffects
    ) {
        effects.applyPresentationTransition(presentationTransition)
        effects.applyContentSnapshot(contentSnapshot)
        effects.applyRelayStatusSnapshot(relayStatusSnapshot)
        effects.applyListProjectionInvalidation(
            HomeTimelineListProjectionInvalidation(revision: 4)
        )
        effects.applyPendingEventCountPublication(
            HomeTimelinePendingEventCountPublication(count: 3)
        )
        effects.materializeEntries()
    }

    private func applyRuntimeActions(
        _ actions: HomeTimelineRuntimeApplicationActions
    ) {
        actions.reloadProjection(applicationAccount, "anchor")
        actions.requestNewestProjectionReload()
        actions.scheduleMaterialization(120, true)
        actions.materializeEntries()
        actions.recordDiagnostic(diagnostic)
    }

    private var presentationTransition: HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 0,
                realtimeFollowSourceRevision: nil
            ),
            changes: [],
            didChangeReadState: false
        )
    }

    private var contentSnapshot: HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot(
            resolvedRelays: ["wss://content.example"],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        )
    }

    private var relayStatusSnapshot: HomeTimelineRelayStatusSnapshot {
        HomeTimelineRelayStatusSnapshot(
            runtimeStates: [:],
            connectedRelayCount: 1,
            plannedRelayCount: 2
        )
    }

    private var emptyRuntimeEffects: HomeTimelineRuntimeApplicationEffects {
        HomeTimelineRuntimeApplicationEffects(
            applyListProjectionInvalidation: { _ in },
            applyPendingEventCountPublication: { _ in },
            reloadProjection: { _, _ in },
            reloadNewestProjection: { _ in },
            scheduleMaterialization: { _ in },
            persistTimelineMetadata: { _ in },
            sourceInstallFailed: { _ in }
        )
    }
}

@MainActor
private final class StateInteractionProbe {
    var persistenceState = HomeTimelinePersistenceState(
        accountID: "initial",
        followedPubkeys: []
    )
    var hasPendingEvents = true
    var providesProjection = true
    var projectionReads = 0
    let applicationFixture = StoreApplicationDispatcherFixture()
}

@MainActor
private struct StateInteractionFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "state-interaction",
        readOnly: true
    )
    let router = StateInteractionRouterSpy()
    let probe = StateInteractionProbe()
    let relayStatus = RelayStatusRecordingSpy()
    let workflow: HomeTimelineStateInteractionWorkflow

    init() {
        workflow = HomeTimelineStateInteractionWorkflow(
            stateWorkflow: router,
            relayStatus: relayStatus
        )
    }

    var context: HomeTimelineStateInteractionContext {
        HomeStateContextFactory(
            environment: HomeStateContextEnvironment(
                projection: { [probe, runtimeState] in
                    probe.projectionReads += 1
                    guard probe.providesProjection else { return nil }
                    return HomeTimelineStateContextProjection(
                        persistenceState: probe.persistenceState,
                        runtimeApplicationState: runtimeState,
                        hasPendingEvents: probe.hasPendingEvents
                    )
                },
                applications: probe.applicationFixture.effects
            )
        )
        .context()
    }

    var timelineState: NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: ["wss://state.example"],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: []
        )
    }

    var snapshotInput: HomeTimelineSnapshotInput {
        HomeTimelineSnapshotInput(
            accountID: account.pubkey,
            relays: [],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            nip05Resolutions: [:],
            hasMoreOlder: true
        )
    }

    private var runtimeState: HomeTimelineRuntimeApplicationState {
        HomeTimelineRuntimeApplicationState(
            account: account,
            resolvedRelays: ["wss://relay.example"],
            followedPubkeys: [],
            nip05Resolutions: [:],
            hasMoreOlder: true,
            deferredMaterializationDelayNanoseconds: 240
        )
    }
}
