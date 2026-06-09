import Foundation
import AstrenzaCore

struct HomeTimelineMaterializedSnapshot {
    var entries: [TimelineFeedEntry]
    var filterStatus: TimelineFilterStatus
    var renderFingerprint: [String]
}

struct HomeTimelineRepository {
    let eventStore: NostrEventStore?

    func materialize(
        account: NostrAccount?,
        noteEvents: [NostrEvent],
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        followedPubkeys: [String],
        resolvedRelays: [String],
        filterRules: NostrFilterRuleSet?,
        filterStatus: TimelineFilterStatus,
        timelineKey: String = "home",
        timeline: NostrFilterTimelineScope = .home,
        policy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> HomeTimelineMaterializedSnapshot {
        let materialReferenceEvents = noteEvents + contextEvents
        let deletedEntries = account.flatMap { account in
            try? eventStore?.deletedTimelineEntries(
                accountID: account.pubkey,
                timelineKey: timelineKey,
                limit: 250
            )
        } ?? []
        let timelineEntries = account.flatMap { account in
            try? eventStore?.timelineEntries(
                accountID: account.pubkey,
                timelineKey: timelineKey,
                limit: 500
            )
        } ?? []
        let entries = NostrTimelineMaterializer.entries(
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: materialReferenceEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: materialReferenceEvents),
            filterRules: filterRules,
            deletedEntries: deletedEntries,
            timelineEntries: timelineEntries,
            relayCount: max(1, resolvedRelays.count),
            timeline: timeline,
            policy: policy
        )

        return HomeTimelineMaterializedSnapshot(
            entries: entries,
            filterStatus: filterStatus,
            renderFingerprint: entriesRenderFingerprint(for: entries)
        )
    }

    private func mediaAssetsByEventID(for events: [NostrEvent]) -> [String: [NostrMediaAssetRecord]] {
        guard let eventStore else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: events.map { event in
                (event.id, (try? eventStore.mediaAssets(eventID: event.id)) ?? [])
            }
        )
    }

    private func linkPreviewsByNormalizedURL(for events: [NostrEvent]) -> [String: NostrLinkPreviewRecord] {
        guard let eventStore else { return [:] }
        let urls = events.flatMap { NostrLinkParser.webURLs(in: $0.content) }
        return (try? eventStore.linkPreviews(urls: urls)) ?? [:]
    }

    private func entriesRenderFingerprint(for entries: [TimelineFeedEntry]) -> [String] {
        entries.map(entryRenderFingerprint)
    }

    private func entryRenderFingerprint(_ entry: TimelineFeedEntry) -> String {
        switch entry {
        case .post(let post):
            return [
                "post",
                post.id,
                post.author.primaryText,
                post.author.secondaryText,
                "\(post.author.nip05Status)",
                "\(post.author.isMetadataResolved)",
                "\(post.author.isFollowed)",
                post.avatar.imageURL?.absoluteString ?? "",
                "\(post.avatar.pictureState)",
                post.body,
                post.repostedBy?.author.primaryText ?? "",
                post.replyContext?.author.primaryText ?? "",
                post.replyContext?.bodyPreview ?? "",
                post.quotedPost?.body ?? "",
                post.contentWarning?.displayReason ?? "",
                mediaRenderFingerprint(post.media),
                post.linkSummary?.compactText ?? "",
                "\(post.actionState.didReply)",
                "\(post.actionState.didRepost)",
                "\(post.actionState.didFavorite)",
                "\(post.actionState.didZap)"
            ].joined(separator: "\u{1f}")
        case .gap(let gap):
            return [
                "gap",
                gap.id,
                gap.newerPostID,
                gap.olderPostID,
                "\(gap.missingEstimate)",
                "\(gap.relayCount)",
                "\(gap.state)",
                gap.backfilledPosts.map(\.id).joined(separator: ",")
            ].joined(separator: "\u{1f}")
        case .deleted(let entry):
            return "deleted\u{1f}\(entry.id)"
        }
    }

    private func mediaRenderFingerprint(_ media: TimelineMedia?) -> String {
        guard let media else { return "" }
        switch media {
        case .gallery(let tiles):
            return tiles.map { tile in
                [
                    tile.id,
                    tile.title,
                    tile.symbolName,
                    tile.url?.absoluteString ?? "",
                    tile.altText ?? ""
                ].joined(separator: "\u{1e}")
            }.joined(separator: "\u{1d}")
        case .linkPreview(let preview):
            return [
                "link",
                preview.title,
                preview.subtitle,
                preview.host,
                preview.url,
                preview.imageURL?.absoluteString ?? "",
                String(describing: preview.style)
            ].joined(separator: "\u{1e}")
        case .unresolvedLink(let preview):
            return ["unresolved", preview.host, preview.url].joined(separator: "\u{1e}")
        }
    }
}
