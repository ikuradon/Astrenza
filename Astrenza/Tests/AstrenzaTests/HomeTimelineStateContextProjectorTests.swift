import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline state context projector")
struct HomeTimelineStateContextProjectorTests {
    @Test("Snapshot projects persistence runtime and pending state together")
    func snapshotProjectsStateContext() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "state-projector",
            readOnly: true
        )
        let followedPubkeys = [String(repeating: "b", count: 64)]
        let nip05Resolutions = [
            account.pubkey: NostrNIP05Resolution(
                identifier: "state@example.com",
                pubkey: account.pubkey,
                relays: ["wss://profile.example"],
                status: .verified
            )
        ]
        let projection = HomeTimelineStateContextProjector().projection(
            from: HomeTimelineStateStoreSnapshot(
                account: account,
                resolvedRelays: ["wss://relay.example"],
                followedPubkeys: followedPubkeys,
                nip05Resolutions: nip05Resolutions,
                hasMoreOlder: false,
                hasPendingEvents: true,
                defaultMaterializationDelayNanoseconds: 120
            )
        )

        #expect(projection.persistenceState == HomeTimelinePersistenceState(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys
        ))
        #expect(projection.runtimeApplicationState ==
            HomeTimelineRuntimeApplicationState(
                account: account,
                resolvedRelays: ["wss://relay.example"],
                followedPubkeys: followedPubkeys,
                nip05Resolutions: nip05Resolutions,
                hasMoreOlder: false,
                deferredMaterializationDelayNanoseconds: 240
            ))
        #expect(projection.hasPendingEvents)
    }
}
