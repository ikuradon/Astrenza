import Testing
@testable import Astrenza

@Suite("Home Store context coordinator")
@MainActor
struct HomeStoreContextCoordinatorTests {
    @Test("Every context reads a fresh snapshot from its source")
    func contextsReadFreshSnapshots() {
        let fixture = StoreContextCoordinatorFixture()
        fixture.installSnapshots()

        #expect(fixture.source.runtimeApplicationContextCount == 1)
        expectInstalledSnapshots(fixture)

        fixture.clearSnapshots()

        #expect(fixture.coordinator.loadContext().state ==
            HomeTimelineLoadInteractionState(
                hasRelayRuntime: false,
                hasTimelineEvents: false
            ))
        #expect(
            fixture.coordinator.runtimeInteractionState().account == nil
        )
        #expect(
            fixture.coordinator.stateContext().effects.environment.projection()
                == nil
        )
        #expect(
            fixture.coordinator.localMutationContext().state.accountID == nil
        )
        #expect(
            !fixture.coordinator.accountStartContext().state.hasRelayRuntime
        )
        #expect(
            fixture.coordinator.viewportContext().state.presentation.account
                == nil
        )
        #expect(fixture.source.snapshotReads == [
            .load, .runtime, .state, .feature, .account, .viewport,
            .load, .runtime, .state, .feature, .account, .viewport
        ])
    }

    @Test("Live environment dependencies route back to the source")
    func routesEnvironmentDependencies() async {
        let fixture = StoreContextCoordinatorFixture()
        fixture.installSnapshots()
        configureDependencies(fixture)

        let load = fixture.coordinator.loadContext()
        #expect(load.effects.environment.hasResolvedRelays())
        #expect(load.effects.environment.currentState() == fixture.timelineState)
        #expect(load.effects.environment.localBackfillEvents(
            fixture.account,
            fixture.timelineState
        ) == [fixture.event])
        #expect(load.effects.environment.resolvedRelays() == [
            "wss://dependency.example"
        ])

        let runtime = fixture.coordinator.runtimeInteractionContext()
        let packet = runtime.effects.environment.packetContext(nil)
        #expect(packet?.isCurrentFeedContext(fixture.feedContext) == true)

        let backward = fixture.coordinator.backwardContext()
        #expect(await backward.effects.resolveDependencies(
            HomeTimelineBackwardDependencyRequest(
                event: fixture.event,
                account: fixture.account,
                lifecycle: fixture.lifecycle
            )
        ))
        #expect(
            fixture.coordinator.accountResetContext()
                .state.readBoundaryWrite?.scopeID == fixture.account.pubkey
        )

        await invokeAccountDependencies(fixture)
        fixture.coordinator.scheduleReadBoundarySave()

        #expect(fixture.source.dependencyCalls == [
            .hasResolvedRelays,
            .loaderState,
            .localBackfill(fixture.account.pubkey),
            .resolvedRelays,
            .currentFeed(fixture.feedContext.feedID),
            .backward(fixture.event.id),
            .readBoundaryWrite,
            .restoreCachedSnapshot(fixture.account.pubkey),
            .restoredViewport(fixture.account.pubkey),
            .waitForCachedPresentation,
            .restoreCachedReadState(fixture.account.pubkey),
            .load(fixture.account.pubkey),
            .scheduleReadBoundarySave
        ])
    }

    private func expectInstalledSnapshots(
        _ fixture: StoreContextCoordinatorFixture
    ) {
        #expect(fixture.coordinator.loadContext().state ==
            HomeTimelineLoadInteractionState(
                hasRelayRuntime: true,
                hasTimelineEvents: true
            ))
        #expect(
            fixture.coordinator.runtimeInteractionState().account ==
                fixture.account
        )
        #expect(
            fixture.coordinator.stateContext().effects.environment.projection()
                == fixture.stateProjection
        )
        #expect(
            fixture.coordinator.localMutationContext().state.accountID ==
                fixture.account.pubkey
        )
        #expect(
            fixture.coordinator.accountStartContext().state.hasRelayRuntime
        )
        #expect(
            fixture.coordinator.viewportContext().state.presentation.account ==
                fixture.account
        )
    }

    private func configureDependencies(
        _ fixture: StoreContextCoordinatorFixture
    ) {
        fixture.source.hasResolvedRelaysValue = true
        fixture.source.loaderStateValue = fixture.timelineState
        fixture.source.localBackfillEventsValue = [fixture.event]
        fixture.source.resolvedRelaysValue = [
            "wss://dependency.example"
        ]
        fixture.source.currentFeedResult = true
        fixture.source.backwardResolutionResult = true
        fixture.source.readBoundaryWriteValue = HomeTimelineReadBoundaryWrite(
            scopeID: fixture.account.pubkey,
            feedID: "home",
            boundary: nil,
            updatedAt: 100
        )
        fixture.source.restoreCachedSnapshotResult = .restored(
            fixture.timelineState
        )
        fixture.source.restoredViewportValue = HomeTimelineRestoredViewport(
            anchorEventID: "restored"
        )
    }

    private func invokeAccountDependencies(
        _ fixture: StoreContextCoordinatorFixture
    ) async {
        let start = fixture.coordinator.accountStartContext()
        #expect(
            await start.effects.environment.restoreCachedSnapshot(
                fixture.account
            ) == .restored(fixture.timelineState)
        )
        #expect(start.effects.environment.restoredViewport(
            fixture.account.pubkey
        )?.anchorEventID == "restored")
        await start.effects.environment.waitForCachedPresentation()
        await start.effects.environment.restoreCachedReadState(fixture.account)
        await start.effects.load(HomeTimelineAccountStartLoadRequest(
            account: fixture.account,
            lifecycle: fixture.lifecycle
        ))
    }
}
