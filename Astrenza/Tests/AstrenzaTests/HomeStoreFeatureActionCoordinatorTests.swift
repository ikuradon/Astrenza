import Testing
@testable import Astrenza

@Suite("Home Store feature action coordinator")
@MainActor
struct HomeStoreFeatureActionCoordinatorTests {
    @Test("gap backfillとfilter操作は実行ごとに最新contextを使う")
    func backfillAndFiltersReadFreshContexts() async {
        let fixture = StoreFeatureActionCoordinatorFixture()

        let first = await fixture.coordinator.backfillGap(
            fixture.gap,
            direction: .newer
        )
        fixture.contextFixture.clearSnapshots()
        let second = await fixture.coordinator.backfillGap(
            fixture.gap,
            direction: .older
        )
        fixture.coordinator.suspendFilters()
        fixture.coordinator.resumeFilters()

        #expect(first)
        #expect(second)
        #expect(fixture.contexts.reads == [
            .gapBackfill,
            .gapBackfill,
            .filter,
            .filter
        ])
        #expect(fixture.gapBackfill.calls == [
            StoreFeatureActionGapBackfillSpy.Call(
                gapID: fixture.gap.id,
                direction: .newer,
                accountID: fixture.contextFixture.account.pubkey,
                hasRelayRuntime: true,
                resolvedRelays: ["wss://relay.example"]
            ),
            StoreFeatureActionGapBackfillSpy.Call(
                gapID: fixture.gap.id,
                direction: .older,
                accountID: nil,
                hasRelayRuntime: false,
                resolvedRelays: []
            )
        ])
        #expect(fixture.filter.intents == [.suspend, .resume])
    }

    @Test("publishは現在accountとcapabilityが揃う時だけcontextを作る")
    func publishRequiresAccountAndCapability() async throws {
        let fixture = StoreFeatureActionCoordinatorFixture()
        let signer = StoreFeatureActionSigner()

        try await fixture.coordinator.enqueuePublish(
            fixture.publishInput,
            signer: signer
        )
        fixture.accountSource.accountValue = nil
        try await fixture.coordinator.enqueuePublish(
            fixture.publishInput,
            signer: signer
        )

        #expect(fixture.accountSource.readCount == 2)
        #expect(fixture.contexts.reads == [
            .publish(accountID: fixture.contextFixture.account.pubkey)
        ])
        #expect(fixture.publish.calls == [
            StoreFeatureActionPublishSpy.Call(
                input: fixture.publishInput,
                state: HomeTimelinePublishInteractionState(
                    account: fixture.contextFixture.account,
                    accountWriteRelays: [],
                    fallbackRelays: ["wss://relay.example"]
                ),
                receivedExpectedSigner: true
            )
        ])

        let unavailable = StoreFeatureActionCoordinatorFixture(
            hasPublish: false
        )
        try await unavailable.coordinator.enqueuePublish(
            unavailable.publishInput,
            signer: signer
        )
        #expect(unavailable.accountSource.readCount == 1)
        #expect(unavailable.contexts.reads.isEmpty)
        #expect(unavailable.publish.calls.isEmpty)
    }

    @Test("publish errorは呼び出し元へ保持する")
    func publishPropagatesError() async {
        let fixture = StoreFeatureActionCoordinatorFixture()
        fixture.publish.failure = .publish

        await #expect(throws: StoreFeatureActionPublishSpy.Failure.publish) {
            try await fixture.coordinator.enqueuePublish(
                fixture.publishInput,
                signer: StoreFeatureActionSigner()
            )
        }
    }

    @Test("local mutationはintentと最新accountを渡しcapability不在なら何もしない")
    func localMutationsPreserveOptionalBehavior() {
        let fixture = StoreFeatureActionCoordinatorFixture()

        fixture.coordinator.muteAuthor(authorPubkey: "muted")
        fixture.contextFixture.clearSnapshots()
        fixture.coordinator.bookmark(eventID: "bookmarked")

        #expect(fixture.contexts.reads == [
            .localMutation,
            .localMutation
        ])
        #expect(fixture.localMutation.calls == [
            StoreFeatureActionLocalMutationSpy.Call(
                intent: .muteAuthor(authorPubkey: "muted"),
                accountID: fixture.contextFixture.account.pubkey
            ),
            StoreFeatureActionLocalMutationSpy.Call(
                intent: .bookmark(eventID: "bookmarked"),
                accountID: nil
            )
        ])

        let unavailable = StoreFeatureActionCoordinatorFixture(
            hasLocalMutation: false
        )
        unavailable.coordinator.muteAuthor(authorPubkey: "muted")
        unavailable.coordinator.bookmark(eventID: "bookmarked")
        #expect(unavailable.contexts.reads.isEmpty)
        #expect(unavailable.localMutation.calls.isEmpty)
    }
}
