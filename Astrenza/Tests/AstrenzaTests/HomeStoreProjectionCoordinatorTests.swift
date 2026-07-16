import Testing
@testable import Astrenza

@Suite("Home Store projection coordinator")
@MainActor
struct HomeStoreProjectionCoordinatorTests {
    @Test("feed定義準備は毎回最新のfollowとevent snapshotを使う")
    func preparationReadsFreshSnapshot() {
        let fixture = StoreProjectionCoordinatorFixture()

        fixture.coordinator.prepareDefinition(account: fixture.account)
        fixture.source.preparation = HomeStoreProjectionPreparation(
            followedPubkeys: ["replacement"],
            liveEvents: [fixture.secondEvent]
        )
        fixture.coordinator.prepareDefinition(account: fixture.account)

        #expect(fixture.source.readCount == 2)
        #expect(fixture.interaction.calls == [
            .prepare(
                accountID: fixture.account.pubkey,
                followedPubkeys: [fixture.account.pubkey],
                eventIDs: [fixture.firstEvent.id]
            ),
            .prepare(
                accountID: fixture.account.pubkey,
                followedPubkeys: ["replacement"],
                eventIDs: [fixture.secondEvent.id]
            )
        ])
    }

    @Test("viewport復元・reload・cancelの引数と結果を保持する")
    func routesProjectionLifecycle() {
        let fixture = StoreProjectionCoordinatorFixture()
        var reloadResults: [Bool] = []

        let restored = fixture.coordinator.restoredViewportState(
            accountID: fixture.account.pubkey,
            timelineKey: "home"
        )
        fixture.coordinator.reloadNewestProjection(
            account: fixture.account
        ) { reloadResults.append($0) }
        fixture.coordinator.reloadProjection(
            account: fixture.account,
            around: "anchor",
            mergingWithCurrentWindow: true
        ) { reloadResults.append($0) }
        fixture.coordinator.cancelMaterialization()

        #expect(restored == fixture.interaction.restoredViewport)
        #expect(reloadResults == [true, false])
        #expect(fixture.source.readCount == 0)
        #expect(fixture.interaction.calls == [
            .restoredViewport(
                accountID: fixture.account.pubkey,
                timelineKey: "home"
            ),
            .reloadNewest(accountID: fixture.account.pubkey),
            .reload(
                accountID: fixture.account.pubkey,
                anchorEventID: "anchor",
                mergesCurrentWindow: true
            ),
            .cancelMaterialization
        ])
    }

    #if DEBUG
    @Test("debug用mergeとprojection activationも同じ境界を通る")
    func routesDebugProjectionOperations() async {
        let fixture = StoreProjectionCoordinatorFixture()

        let merged = fixture.coordinator.mergedWindow(
            fixture.currentWindow,
            with: fixture.loadedWindow,
            centeredOn: "anchor"
        )
        await fixture.coordinator.activateStoredProjection(
            definition: fixture.definition,
            sourceAuthors: [fixture.account.pubkey]
        )

        #expect(merged == fixture.loadedWindow)
        #expect(fixture.interaction.calls == [
            .merge(
                currentEventIDs: [fixture.firstEvent.id],
                loadedEventIDs: [fixture.secondEvent.id],
                anchorEventID: "anchor"
            ),
            .activate(
                feedID: fixture.definition.feedID,
                sourceAuthors: [fixture.account.pubkey]
            )
        ])
    }
    #endif
}
