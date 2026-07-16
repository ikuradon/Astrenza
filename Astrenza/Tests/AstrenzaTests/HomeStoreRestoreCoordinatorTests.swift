import Testing
@testable import Astrenza

@Suite("Home Store restore coordinator")
@MainActor
struct HomeStoreRestoreCoordinatorTests {
    @Test("anchorがなければ復元を開始しない")
    func ignoresMissingAnchor() {
        let fixture = StoreRestoreCoordinatorFixture(anchorEventID: nil)

        fixture.coordinator.restoreIfPossible(account: fixture.account)

        #expect(fixture.events.events.isEmpty)
    }

    @Test("projection reload失敗後はmaterializeしない")
    func stopsAfterFailedReload() {
        let fixture = StoreRestoreCoordinatorFixture()

        fixture.coordinator.restoreIfPossible(account: fixture.account)
        fixture.projection.complete(didReload: false)

        #expect(fixture.events.events == [
            .reloadProjection(
                accountID: fixture.account.pubkey,
                anchorEventID: fixture.anchorEventID,
                mergesCurrentWindow: false
            )
        ])
    }

    @Test("reload中のaccount変更は古い復元を無効化する")
    func rejectsReloadForStaleAccount() {
        let fixture = StoreRestoreCoordinatorFixture()

        fixture.coordinator.restoreIfPossible(account: fixture.account)
        fixture.source.identity = HomeStoreRestoreIdentity(
            accountID: fixture.replacementAccount.pubkey,
            anchorEventID: fixture.anchorEventID
        )
        fixture.projection.complete(didReload: true)

        #expect(fixture.events.events.count == 1)
    }

    @Test("reload中のanchor変更は古い復元を無効化する")
    func rejectsReloadForStaleAnchor() {
        let fixture = StoreRestoreCoordinatorFixture()

        fixture.coordinator.restoreIfPossible(account: fixture.account)
        fixture.source.identity = HomeStoreRestoreIdentity(
            accountID: fixture.account.pubkey,
            anchorEventID: "replacement-anchor"
        )
        fixture.projection.complete(didReload: true)

        #expect(fixture.events.events.count == 1)
    }

    @Test("非empty復元はrealtime追従せずpreview解決後にloadedを通知する")
    func completesNonemptyRestoration() {
        let fixture = StoreRestoreCoordinatorFixture()

        fixture.coordinator.restoreIfPossible(account: fixture.account)
        fixture.projection.complete(didReload: true)
        fixture.presentation.complete(hasEntries: true)

        #expect(fixture.events.events == [
            .reloadProjection(
                accountID: fixture.account.pubkey,
                anchorEventID: fixture.anchorEventID,
                mergesCurrentWindow: false
            ),
            .materialize(allowsRealtimeFollow: false),
            .scheduleLinkPreviewResolution,
            .applyActivityIntent(.setPhase(.loaded))
        ])
    }

    @Test("empty復元はpreviewだけ解決しloadedを通知しない")
    func keepsLoadingForEmptyRestoration() {
        let fixture = StoreRestoreCoordinatorFixture()

        fixture.coordinator.restoreIfPossible(account: fixture.account)
        fixture.projection.complete(didReload: true)
        fixture.presentation.complete(hasEntries: false)

        #expect(fixture.events.events == [
            .reloadProjection(
                accountID: fixture.account.pubkey,
                anchorEventID: fixture.anchorEventID,
                mergesCurrentWindow: false
            ),
            .materialize(allowsRealtimeFollow: false),
            .scheduleLinkPreviewResolution
        ])
    }

    @Test("保留中のreload callbackはcoordinatorを保持しない")
    func reloadCallbackDoesNotRetainCoordinator() {
        let account = StoreRestoreCoordinatorFixture.makeAccount(
            pubkeyCharacter: "a"
        )
        let events = StoreRestoreEventRecorder()
        let source = StoreRestoreSourceSpy(
            identity: HomeStoreRestoreIdentity(
                accountID: account.pubkey,
                anchorEventID: "anchor"
            )
        )
        let projection = StoreRestoreProjectionSpy(events: events)
        var coordinator: HomeStoreRestoreCoordinator? =
            HomeStoreRestoreCoordinator(
                source: source,
                projection: projection,
                presentation: StoreRestorePresentationSpy(events: events),
                linkPreview: StoreRestoreLinkPreviewSpy(events: events),
                activity: StoreRestoreActivitySpy(events: events)
            )
        weak let weakCoordinator = coordinator

        coordinator?.restoreIfPossible(account: account)
        coordinator = nil

        #expect(weakCoordinator == nil)
        projection.complete(didReload: true)
        #expect(events.events.count == 1)
    }
}
