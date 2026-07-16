import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home Store state coordinator")
@MainActor
struct HomeStoreStateCoordinatorTests {
    @Test("content操作とqueryはdata境界を保持する")
    func routesContentOperations() {
        let fixture = StoreStateCoordinatorFixture()

        let preferredEvents = fixture.coordinator.preferredEvents
        let provisional = fixture.coordinator.installProvisionalRelays(
            ["wss://requested.example"]
        )
        let followed = fixture.coordinator.replaceFollowedPubkeys(
            ["requested-follow"]
        )

        #expect(preferredEvents == [StoreStateCoordinatorFixture.preferredEvent])
        #expect(provisional == StoreStateCoordinatorFixture.provisionalSnapshot)
        #expect(followed == StoreStateCoordinatorFixture.followedSnapshot)
        #expect(fixture.data.calls == [
            .contentState,
            .perform(.installProvisionalRelays([
                "wss://requested.example"
            ])),
            .perform(.replaceFollowedPubkeys(["requested-follow"]))
        ])
        #expect(fixture.state.calls.isEmpty)
        #expect(fixture.accountSource.readCount == 0)
        #expect(fixture.contexts.contextIDs.isEmpty)
    }

    @Test("bootstrap変換とstate置換は順序とfresh contextを保持する")
    func routesStateReplacement() {
        let fixture = StoreStateCoordinatorFixture()

        fixture.accountSource.accountID = "bootstrap-account"
        fixture.coordinator.replaceRuntimeBootstrapState(
            fixture.bootstrapInput
        )
        fixture.accountSource.accountID = nil
        fixture.coordinator.replaceTimelineState(fixture.replacementState)

        #expect(fixture.data.calls == [
            .runtimeBootstrapState(fixture.bootstrapInput.relays)
        ])
        #expect(fixture.state.calls == [
            .replace(
                relays: StoreStateCoordinatorFixture.bootstrapResult.relays,
                accountID: "bootstrap-account"
            ),
            .replace(
                relays: fixture.replacementState.relays,
                accountID: nil
            )
        ])
        #expect(fixture.order.steps == [
            .runtimeBootstrapState,
            .readAccount,
            .replaceState,
            .readAccount,
            .replaceState
        ])
        #expect(fixture.accountSource.readCount == 2)
        #expect(fixture.contexts.contextIDs == [1, 2])
        #expect(fixture.contexts.applications == [
            .requestNewestProjectionReload(contextID: 1),
            .requestNewestProjectionReload(contextID: 2)
        ])
    }

    @Test("persistはdata snapshotとfresh contextをstateへ渡す")
    func routesPersistence() async {
        let fixture = StoreStateCoordinatorFixture()
        fixture.accountSource.accountID = "replacement-account"
        fixture.coordinator.replaceTimelineState(
            fixture.replacementState
        )

        let didPersist = await fixture.coordinator.persistDatabase(
            accountID: "requested-account"
        )

        #expect(!didPersist)
        #expect(fixture.data.calls == [
            .persistenceSnapshotInput(accountID: "requested-account")
        ])
        #expect(fixture.state.calls == [
            .replace(
                relays: fixture.replacementState.relays,
                accountID: "replacement-account"
            ),
            .persist(accountID: "persisted-account")
        ])
        #expect(fixture.accountSource.readCount == 1)
        #expect(fixture.contexts.contextIDs == [1, 2])
        #expect(fixture.contexts.applications == [
            .requestNewestProjectionReload(contextID: 1),
            .materializeEntries(contextID: 2)
        ])
    }

    @Test("dependency操作とmetricsはstate境界内に留める")
    func routesDependencyOperations() {
        let fixture = StoreStateCoordinatorFixture()
        let dependencies = NostrEventDependencies(
            sourceEventIDs: ["source"]
        )
        let failure = StoreStateFailureProbe()

        let didEnqueue = fixture.coordinator.enqueueSourceDependencies(
            dependencies,
            availableRelayURLs: ["wss://dependency.example"],
            now: 100
        )
        let didFlush = fixture.coordinator.flushSourcePacketInstall(
            onFailure: { [failure] message in
                failure.record(message)
            }
        )

        #expect(didEnqueue)
        #expect(!didFlush)
        #expect(failure.messages == ["dependency install failed"])
        #expect(fixture.coordinator.pendingDependencyRequestCount == 5)
        #expect(fixture.coordinator.hasPendingDependencyWork)
        #expect(fixture.data.calls == [
            .enqueueDependencies(
                dependencies,
                relayURLs: ["wss://dependency.example"],
                now: 100
            ),
            .flushSourcePacketInstall
        ])
    }
}
