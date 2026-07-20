import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline query context projector")
struct HomeTimelineQueryContextProjectorTests {
    @Test("Store snapshot projects every read and cache-key input")
    func projectsQueryInputs() throws {
        let snapshot = HomeTimelineQueryStoreSnapshot(
            accountID: "account",
            fallbackEntries: [
                .deleted(TimelineDeletedEntry(id: "fallback"))
            ],
            resolvedRelayCount: 3,
            syncPolicy: .default(
                networkType: .cellular,
                lowPowerMode: true
            ),
            homeContentRevision: 7,
            listContentRevision: 2,
            profileDataRevision: 11
        )
        let projector = HomeTimelineQueryContextProjector()
        let projection = projector.projection(from: snapshot)

        #expect(projection.accountID == "account")
        #expect(projection.homeContentRevision == 7)
        #expect(projection.listContentRevision == 2)
        #expect(projection.profileDataRevision == 11)
        #expect(projection.readContextInput.accountID == "account")
        #expect(projection.readContextInput.fallbackEntries.map(\.id) == [
            "fallback"
        ])
        #expect(projection.readContextInput.resolvedRelayCount == 3)
        #expect(projection.readContextInput.syncPolicy == snapshot.syncPolicy)

        let listQuery = try #require(projector.listProjectionQuery(
            limit: 500,
            from: projection
        ))
        #expect(listQuery.accountID == "account")
        #expect(listQuery.limit == 500)
        #expect(listQuery.homeContentRevision == 7)
        #expect(listQuery.contextInput.accountID == "account")

        let profileQuery = projector.profileProjectionQuery(
            pubkey: "author",
            isCurrentUser: true,
            postsLimit: 80,
            from: projection
        )
        #expect(profileQuery.pubkey == "author")
        #expect(profileQuery.isCurrentUser)
        #expect(profileQuery.postsLimit == 80)
        #expect(profileQuery.homeContentRevision == 7)
        #expect(profileQuery.listContentRevision == 2)
        #expect(profileQuery.profileDataRevision == 11)
        #expect(profileQuery.contextInput.resolvedRelayCount == 3)
    }

    @Test("Signed-out snapshot cannot create an account-scoped list query")
    func signedOutListQueryIsUnavailable() {
        let projector = HomeTimelineQueryContextProjector()
        let projection = projector.projection(
            from: HomeTimelineQueryStoreSnapshot(
                accountID: nil,
                fallbackEntries: [],
                resolvedRelayCount: 0,
                syncPolicy: .default(),
                homeContentRevision: 0,
                listContentRevision: 0,
                profileDataRevision: 0
            )
        )

        #expect(projector.listProjectionQuery(
            limit: 500,
            from: projection
        ) == nil)
        #expect(projection.readContextInput.accountID == nil)
    }
}
