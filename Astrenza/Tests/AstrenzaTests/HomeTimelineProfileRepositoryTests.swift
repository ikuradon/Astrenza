import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline profile repository")
@MainActor
struct HomeTimelineProfileRepositoryTests {
    @Test("Profile projection combines a summary with bounded posts")
    func profileProjectionCombinesCachedState() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let otherFollow = String(repeating: "b", count: 64)
        let metadata = event(
            id: "3",
            pubkey: accountID,
            createdAt: 300,
            kind: 0,
            content: metadataContent
        )
        let newerPost = event(
            id: "4",
            pubkey: accountID,
            createdAt: 200,
            content: "newer"
        )
        let olderPost = event(
            id: "5",
            pubkey: accountID,
            createdAt: 100,
            content: "older"
        )
        let contactList = event(
            id: "6",
            pubkey: accountID,
            createdAt: 310,
            kind: 3,
            tags: [["p", otherFollow]],
            content: ""
        )
        let firstFollower = String(repeating: "c", count: 64)
        let secondFollower = String(repeating: "d", count: 64)
        let firstFollowerContactList = event(
            id: "7",
            pubkey: firstFollower,
            createdAt: 320,
            kind: 3,
            tags: [["p", accountID]],
            content: ""
        )
        let secondFollowerContactList = event(
            id: "8",
            pubkey: secondFollower,
            createdAt: 330,
            kind: 3,
            tags: [["p", accountID]],
            content: ""
        )
        let followerMetadata = event(
            id: "9",
            pubkey: secondFollower,
            createdAt: 340,
            kind: 0,
            content: "{\"picture\":\"https://images.example/follower.jpg\"}"
        )
        try eventStore.save(events: [
            metadata,
            newerPost,
            olderPost,
            contactList,
            firstFollowerContactList,
            secondFollowerContactList,
            followerMetadata
        ])
        let repository = HomeTimelineRepository(eventStore: eventStore)

        let projection = repository.profileProjection(
            pubkey: accountID,
            isCurrentUser: true,
            postsLimit: 1,
            context: readContext(
                accountID: accountID,
                followedPubkeys: [accountID, otherFollow],
                resolvedRelayCount: 3
            )
        )
        let profile = projection.profile

        #expect(profile.author.primaryText == "Alice")
        #expect(profile.author.secondaryText == "alice.example")
        #expect(profile.author.profileResolutionState == .resolved)
        #expect(profile.avatar.imageURL?.absoluteString == pictureURL)
        #expect(profile.banner.imageURL?.absoluteString == bannerURL)
        #expect(profile.bio == "Building a better Nostr client.")
        #expect(profile.isCurrentUser)
        #expect(profile.isFollowed)
        #expect(profile.followerCount == 2)
        #expect(profile.followingCount == 1)
        #expect(profile.latestFollowers.count == 2)
        #expect(profile.latestFollowers.first?.imageURL?.absoluteString ==
            "https://images.example/follower.jpg")
        #expect(profile.postCount == 2)
        #expect(profile.relayCount == 3)
        #expect(projection.posts.map(\.id) == [newerPost.id])
    }

    @Test("Metadata avatar resolution does not require a post")
    func metadataAvatarDoesNotRequirePost() throws {
        let eventStore = try NostrEventStore.inMemory()
        let pubkey = String(repeating: "c", count: 64)
        try eventStore.save(events: [event(
            id: "6",
            pubkey: pubkey,
            createdAt: 300,
            kind: 0,
            content: metadataContent
        )])

        let profile = HomeTimelineRepository(eventStore: eventStore).profile(
            pubkey: pubkey,
            isCurrentUser: false,
            context: readContext(accountID: "account")
        )

        #expect(profile.avatar.imageURL?.absoluteString == pictureURL)
        #expect(profile.avatar.pictureState == .resolved)
        #expect(profile.postCount == 0)
    }

    private var pictureURL: String {
        "https://images.example/alice.jpg"
    }

    private var bannerURL: String {
        "https://images.example/alice-banner.jpg"
    }

    private var metadataContent: String {
        """
        {"name":"Alice","nip05":"_@alice.example","picture":"\(pictureURL)","about":" Building a better Nostr client. ","banner":"\(bannerURL)"}
        """
    }

    private func readContext(
        accountID: String?,
        followedPubkeys: Set<String> = [],
        resolvedRelayCount: Int = 0
    ) -> HomeTimelineReadContext {
        HomeTimelineReadContext(
            accountID: accountID,
            fallbackEntries: [],
            metadataEvents: [],
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            followedPubkeys: followedPubkeys,
            resolvedRelayCount: resolvedRelayCount,
            filterRules: nil,
            syncPolicy: .default()
        )
    }

    private func event(
        id: Character,
        pubkey: String,
        createdAt: Int,
        kind: Int = 1,
        tags: [[String]] = [],
        content: String
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(id), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "0", count: 128)
        )
    }
}
