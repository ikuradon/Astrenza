import AstrenzaCore
import Foundation

private struct HomeTimelineProfilePostSource {
    let posts: [TimelinePost]
    let count: Int
}

private struct HomeTimelineProfileSummaryInput {
    let pubkey: String
    let isCurrentUser: Bool
    let metadataEvent: NostrEvent?
    let postCount: Int
}

extension HomeTimelineRepository {
    func profile(
        pubkey: String,
        isCurrentUser: Bool,
        context: HomeTimelineReadContext
    ) -> UserProfile {
        profileProjection(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            postsLimit: 0,
            context: context
        ).profile
    }

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool,
        postsLimit: Int,
        context: HomeTimelineReadContext
    ) -> HomeTimelineProfileProjection {
        let metadata = try? eventStore?.latestReplaceableEvent(
            pubkey: pubkey,
            kind: 0
        )
        let source = profilePostSource(
            pubkey: pubkey,
            limit: postsLimit,
            context: context
        )
        let profile = profileSummary(
            HomeTimelineProfileSummaryInput(
                pubkey: pubkey,
                isCurrentUser: isCurrentUser,
                metadataEvent: metadata,
                postCount: source.count
            ),
            context: context
        )
        return HomeTimelineProfileProjection(
            profile: profile,
            posts: source.posts
        )
    }

    func profilePosts(
        pubkey: String,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        guard let events = try? eventStore?.events(
            kind: 1,
            authors: [pubkey],
            limit: limit
        ) else {
            return fallbackPosts(pubkey: pubkey, context: context)
        }
        return materializedPosts(from: events, context: context)
    }

    private func profilePostSource(
        pubkey: String,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> HomeTimelineProfilePostSource {
        guard let eventStore else {
            let posts = fallbackPosts(pubkey: pubkey, context: context)
            return HomeTimelineProfilePostSource(
                posts: Array(posts.prefix(max(0, limit))),
                count: min(posts.count, 1_000)
            )
        }
        let now = Int(Date().timeIntervalSince1970)
        let count = (try? eventStore.eventCount(
            kind: 1,
            authors: [pubkey],
            now: now
        )) ?? 0
        let events = limit > 0
            ? (try? eventStore.events(
                kind: 1,
                authors: [pubkey],
                limit: limit,
                now: now
            )) ?? []
            : []
        let posts = materializedPosts(from: events, context: context)
        return HomeTimelineProfilePostSource(
            posts: posts,
            count: min(max(count, posts.count), 1_000)
        )
    }

    private func fallbackPosts(
        pubkey: String,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        context.fallbackEntries.compactMap(\.post).filter {
            $0.author.pubkey == pubkey
        }
    }

    private func profileSummary(
        _ input: HomeTimelineProfileSummaryInput,
        context: HomeTimelineReadContext
    ) -> UserProfile {
        let pubkey = input.pubkey
        let metadata = input.metadataEvent.flatMap(Self.profileMetadata)
        let contactListEvent = try? eventStore?.latestReplaceableEvent(
            pubkey: pubkey,
            kind: 3
        )
        let followingCount = contactListEvent.map {
            NostrContactList.pubkeys(from: $0).count
        } ?? context.followedPubkeys.subtracting([pubkey]).count
        let followerPubkeys = ((try? eventStore?.followerPubkeys(
            of: pubkey,
            limit: 9
        )) ?? []).filter { $0 != pubkey }
        let followerCount = (try? eventStore?.followerCount(of: pubkey)) ?? 0
        let relayCount = input.isCurrentUser
            ? context.resolvedRelayCount
            : max(1, context.resolvedRelayCount)
        return UserProfile(
            id: pubkey,
            author: materializedAuthor(
                pubkey: pubkey,
                metadataEvent: input.metadataEvent,
                context: context
            ),
            avatar: avatar(
                for: pubkey,
                metadataEvent: input.metadataEvent,
                context: context
            ),
            banner: banner(for: pubkey, metadata: metadata),
            bio: metadata?.aboutText ?? "",
            isCurrentUser: input.isCurrentUser,
            isFollowed: context.followedPubkeys.contains(pubkey) ||
                input.isCurrentUser,
            followerCount: followerCount,
            followingCount: followingCount,
            postCount: input.postCount,
            relayCount: relayCount,
            latestFollowers: followerAvatars(
                pubkeys: followerPubkeys,
                context: context
            ),
            featuredHashtags: []
        )
    }

    private func materializedAuthor(
        pubkey: String,
        metadataEvent: NostrEvent?,
        context: HomeTimelineReadContext
    ) -> TimelineAuthor {
        let metadata = metadataEvent.flatMap(Self.profileMetadata)
        guard metadataEvent != nil else {
            return .unresolved(
                pubkey: pubkey,
                state: context.profileResolutionStates[pubkey] ?? .unknown
            )
        }
        return .metadataResolved(
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            nip05Status: NIP05Status(
                context.nip05Resolutions[pubkey]?.status ?? .unchecked
            ),
            pubkey: pubkey,
            isFollowed: context.followedPubkeys.contains(pubkey)
        )
    }

    private func avatar(
        for pubkey: String,
        metadataEvent: NostrEvent?,
        context: HomeTimelineReadContext
    ) -> AvatarStyle {
        let metadata = metadataEvent.flatMap(Self.profileMetadata)
        let item = NostrHomeTimelineItem(
            id: pubkey,
            pubkey: pubkey,
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            nip05Status: nip05Status(
                metadata: metadata,
                resolution: context.nip05Resolutions[pubkey]
            ),
            isFollowed: context.followedPubkeys.contains(pubkey),
            body: "",
            createdAt: Int(Date().timeIntervalSince1970),
            avatarPictureState: avatarPictureState(metadata: metadata),
            avatarImageURL: metadata?.pictureURL,
            profileResolutionState: metadataEvent == nil
                ? context.profileResolutionStates[pubkey] ?? .unknown
                : .resolved
        )
        return NostrTimelineAuthorProjection.avatar(for: item)
    }

    private func nip05Status(
        metadata: NostrProfileMetadata?,
        resolution: NostrNIP05Resolution?
    ) -> NostrNIP05Status {
        guard let identifier = metadata?.nip05, !identifier.isEmpty else {
            return .absent
        }
        guard let resolution, resolution.identifier == identifier else {
            return .unchecked
        }
        return resolution.status
    }

    private func avatarPictureState(
        metadata: NostrProfileMetadata?
    ) -> NostrAvatarPictureState {
        guard let metadata else { return .metadataPending }
        return metadata.pictureURL == nil ? .missing : .resolved
    }

    private func banner(
        for pubkey: String,
        metadata: NostrProfileMetadata?
    ) -> ProfileBannerStyle {
        let palette = NostrTimelineAuthorProjection.avatarPalette(for: pubkey)
        return ProfileBannerStyle(
            colors: [palette.secondary, palette.primary],
            symbolName: "sparkles",
            imageURL: metadata?.bannerURL
        )
    }

    private func followerAvatars(
        pubkeys: [String],
        context: HomeTimelineReadContext
    ) -> [AvatarStyle] {
        guard !pubkeys.isEmpty else { return [] }
        let metadataEvents = ((try? eventStore?.latestReplaceableEvents(
            pubkeys: Set(pubkeys),
            kind: 0
        )) ?? []).reduce(into: [String: NostrEvent]()) { result, event in
            result[event.pubkey] = event
        }
        return pubkeys.map { pubkey in
            avatar(
                for: pubkey,
                metadataEvent: metadataEvents[pubkey],
                context: context
            )
        }
    }

    private static func profileMetadata(
        from event: NostrEvent
    ) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
    }
}
