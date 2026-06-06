import Foundation
import AstrenzaCore
import SwiftUI

@MainActor
final class NostrHomeTimelineStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case resolvingRelays
        case resolvingContacts
        case loadingHome
        case loaded
        case failed(String)

        var copy: String {
            switch self {
            case .idle:
                "Ready"
            case .resolvingRelays:
                "Resolving NIP-65 relays"
            case .resolvingContacts:
                "Resolving kind:3 contacts"
            case .loadingHome:
                "Loading Home timeline"
            case .loaded:
                "Home timeline loaded"
            case .failed(let message):
                message
            }
        }

        var isProcessing: Bool {
            switch self {
            case .resolvingRelays, .resolvingContacts, .loadingHome:
                true
            case .idle, .loaded, .failed:
                false
            }
        }
    }

    @Published private(set) var account: NostrAccount?
    @Published private(set) var entries: [TimelineFeedEntry] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var resolvedRelays: [String] = []
    @Published private(set) var followedPubkeys: [String] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var hasMoreOlder = true

    private let timelineLoader: NostrHomeTimelineLoader
    private let eventStore: NostrEventStore?
    private var loadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var noteEvents: [NostrEvent] = []
    private var metadataEvents: [NostrEvent] = []
    private var relayListEvent: NostrEvent?
    private var contactListEvent: NostrEvent?
    private var nip05Resolutions: [String: NostrNIP05Resolution] = [:]
    private var relaySyncEvents: [NostrRelaySyncEventRecord] = []

    var relayStatusEventStore: NostrEventStore? {
        eventStore
    }
    init(
        timelineLoader: NostrHomeTimelineLoader = NostrHomeTimelineLoader(),
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(appDirectory: "Astrenza")
    ) {
        self.timelineLoader = timelineLoader
        self.eventStore = eventStore
    }

    func start(account: NostrAccount) {
        self.account = account
        restoreCachedSnapshot(account: account)
        if entries.isEmpty {
            phase = .resolvingRelays
        }
        loadTask?.cancel()
        loadTask = Task {
            await load(account: account)
        }
    }

    func refresh() {
        guard let account else { return }
        paginationTask?.cancel()
        paginationTask = Task {
            await refreshLatest(account: account)
        }
    }

    func refreshLatest() async {
        guard let account else { return }
        await refreshLatest(account: account)
    }

    func loadOlder() {
        guard let account,
              !isLoadingOlder,
              hasMoreOlder,
              !noteEvents.isEmpty,
              !resolvedRelays.isEmpty,
              !followedPubkeys.isEmpty
        else { return }

        paginationTask?.cancel()
        paginationTask = Task {
            await loadOlder(account: account)
        }
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        guard let account, let eventStore else { return }
        let writeRelays = NostrRelayList.parse(from: relayListEvent).writeRelays
        let relayURLs = writeRelays.isEmpty ? resolvedRelays : writeRelays
        let createdAt = Int(Date().timeIntervalSince1970)
        let unsignedEvent = input.unsignedEvent(pubkey: account.pubkey, createdAt: createdAt)
        let signedEvent = try await signer.sign(unsignedEvent)
        let destinationRelays = NostrPublishDestinationResolver.relayDestinations(
            accountWriteRelays: relayURLs,
            taggedUserReadRelays: [],
            fallbackRelays: resolvedRelays
        )
        let record = try eventStore.enqueueOutboxEvent(
            signedEvent,
            accountID: account.pubkey,
            relayURLs: destinationRelays,
            createdAt: createdAt
        )

        try eventStore.save(events: [record.event])
        noteEvents.removeAll { $0.id == record.event.id }
        noteEvents.insert(record.event, at: 0)
        if !followedPubkeys.contains(account.pubkey) {
            followedPubkeys.append(account.pubkey)
        }
        materializeEntries()
        persistDatabase(account: account)
        phase = .loaded
    }

    func cancel() {
        loadTask?.cancel()
        paginationTask?.cancel()
        loadTask = nil
        paginationTask = nil
        phase = .idle
    }

    func post(eventID: String) -> TimelinePost? {
        guard let eventStore,
              let event = try? eventStore.event(id: eventID),
              event.kind == 1
        else {
            return entries.compactMap(\.post).first { $0.id == eventID }
        }

        return materializedPosts(from: [event]).first
    }

    func profile(pubkey: String, isCurrentUser: Bool = false) -> UserProfile {
        let metadata = try? eventStore?.latestReplaceableEvent(pubkey: pubkey, kind: 0)
        let posts = profilePosts(pubkey: pubkey, limit: 1_000)
        let author = materializedAuthor(pubkey: pubkey, metadataEvent: metadata)
        let avatar = posts.first?.avatar ?? avatar(for: pubkey)
        let relayCount = isCurrentUser ? resolvedRelays.count : max(1, resolvedRelays.count)

        return UserProfile(
            id: pubkey,
            author: author,
            avatar: avatar,
            banner: banner(for: pubkey),
            bio: metadata.flatMap(Self.profileMetadata).map { _ in "kind:0 profile metadata is cached." } ?? "kind:0 profile is not cached yet.",
            isCurrentUser: isCurrentUser,
            isFollowed: followedPubkeys.contains(pubkey) || isCurrentUser,
            followerCount: 0,
            followingCount: isCurrentUser ? followedPubkeys.count : 0,
            postCount: posts.count,
            relayCount: relayCount,
            latestFollowers: [],
            featuredHashtags: []
        )
    }

    func profilePosts(pubkey: String, limit: Int = 80) -> [TimelinePost] {
        guard let events = try? eventStore?.events(kind: 1, authors: [pubkey], limit: limit) else {
            return entries.compactMap(\.post).filter { $0.author.pubkey == pubkey }
        }

        return materializedPosts(from: events)
    }

    func replyAncestors(for post: TimelinePost, limit: Int = 8) -> [TimelinePost] {
        guard let eventStore else { return [] }

        var ancestors: [NostrEvent] = []
        var currentID = post.id
        var visited = Set([post.id])

        while ancestors.count < limit {
            guard let tags = try? eventStore.tags(eventID: currentID),
                  let parentID = Self.replyParentID(from: tags),
                  !visited.contains(parentID),
                  let parentEvent = try? eventStore.event(id: parentID),
                  parentEvent.kind == 1
            else {
                break
            }

            ancestors.append(parentEvent)
            visited.insert(parentID)
            currentID = parentID
        }

        return materializedPosts(from: ancestors.reversed())
    }

    func replies(for post: TimelinePost, limit: Int = 24) -> [TimelinePost] {
        guard let events = try? eventStore?.eventsReferencing(eventID: post.id, kind: 1, limit: limit) else {
            return []
        }

        return materializedPosts(from: events.filter { event in
            Self.replyParentID(from: event.tags) == post.id
        })
    }

    private func load(account: NostrAccount) async {
        do {
            let state = try await timelineLoader.initialState(account: account)
            guard Task.isCancelled == false else { return }
            apply(state)
            materializeEntries()
            persistDatabase(account: account)
            phase = .loaded
        } catch {
            guard Task.isCancelled == false else { return }
            phase = .failed("Home timeline failed: \(error.localizedDescription)")
        }
    }

    private func refreshLatest(account: NostrAccount) async {
        guard !isRefreshing else { return }
        guard !noteEvents.isEmpty else {
            start(account: account)
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let state = try await timelineLoader.refreshedState(account: account, current: loaderState())
            guard Task.isCancelled == false else { return }
            apply(state)
            materializeEntries()
            persistDatabase(account: account)
            phase = .loaded
        } catch {
            guard Task.isCancelled == false else { return }
            phase = .failed("Refresh failed: \(error.localizedDescription)")
        }
    }

    private func loadOlder(account: NostrAccount) async {
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let current = loaderState()
            let localBackfillEvents = databaseBackfillEvents(account: account, current: current)
            let state = try await timelineLoader.olderState(
                account: account,
                current: current,
                localBackfillEvents: localBackfillEvents
            )
            guard Task.isCancelled == false else { return }
            apply(state)
            if !state.hasMoreOlder {
                return
            }

            materializeEntries()
            persistDatabase(account: account)
            phase = .loaded
        } catch {
            guard Task.isCancelled == false else { return }
            phase = .failed("Older notes failed: \(error.localizedDescription)")
        }
    }

    private func restoreCachedSnapshot(account: NostrAccount) {
        if let databaseState = try? eventStore?.homeTimelineState(accountID: account.pubkey) {
            apply(databaseState)
            materializeEntries()
            if !entries.isEmpty {
                phase = .loaded
            }
            return
        }

        entries = []
        resolvedRelays = []
        followedPubkeys = []
        noteEvents = []
        metadataEvents = []
        relayListEvent = nil
        contactListEvent = nil
        nip05Resolutions = [:]
        relaySyncEvents = []
        hasMoreOlder = true
    }

    private func persistDatabase(account: NostrAccount) {
        guard let eventStore else { return }
        do {
            try eventStore.saveHomeTimelineState(loaderState(), accountID: account.pubkey)
        } catch {
            // Live networking can still populate the timeline if the database write fails.
        }
    }

    private func databaseBackfillEvents(account: NostrAccount, current: NostrHomeTimelineState) -> [NostrEvent]? {
        guard let eventStore,
              let until = current.noteEvents.map(\.createdAt).min().map({ max(0, $0 - 1) })
        else {
            return nil
        }

        let authors = current.followedPubkeys.isEmpty ? [account.pubkey] : Array(current.followedPubkeys.prefix(128))
        guard let events = try? eventStore.events(kind: 1, authors: authors, until: until, limit: 1_000),
              !events.isEmpty
        else {
            return nil
        }
        return events
    }

    private func materializeEntries() {
        let deletedEntries = account.flatMap { account in
            try? eventStore?.deletedTimelineEntries(accountID: account.pubkey, timelineKey: "home", limit: 250)
        } ?? []
        entries = NostrTimelineMaterializer.entries(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: noteEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: noteEvents),
            filterRules: filterRuleSet(),
            deletedEntries: deletedEntries
        )
    }

    private func materializedPosts(from events: [NostrEvent]) -> [TimelinePost] {
        let pubkeys = Set(events.map(\.pubkey))
        let metadata = (try? eventStore?.latestReplaceableEvents(pubkeys: pubkeys, kind: 0)) ?? metadataEvents.filter { pubkeys.contains($0.pubkey) }

        return NostrTimelineMaterializer.posts(
            noteEvents: events,
            metadataEvents: metadata,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: events),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: events),
            filterRules: filterRuleSet()
        )
    }

    private func filterRuleSet() -> NostrFilterRuleSet? {
        guard let account, let rules = try? eventStore?.filterRules(accountID: account.pubkey), !rules.isEmpty else {
            return nil
        }
        return NostrFilterRuleSet(rules: rules)
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

    private func materializedAuthor(pubkey: String, metadataEvent: NostrEvent?) -> TimelineAuthor {
        let metadata = metadataEvent.flatMap(Self.profileMetadata)
        guard let displayName = metadata?.bestName else {
            return .unresolved(pubkey: pubkey)
        }

        return .resolved(
            displayName: displayName,
            nip05: metadata?.nip05,
            nip05Status: NIP05Status(nip05Resolutions[pubkey]?.status ?? .unchecked),
            pubkey: pubkey,
            isFollowed: followedPubkeys.contains(pubkey)
        )
    }

    private func avatar(for pubkey: String) -> AvatarStyle {
        let item = NostrHomeTimelineItem(
            id: pubkey,
            pubkey: pubkey,
            displayName: nil,
            nip05: nil,
            nip05Status: .absent,
            isFollowed: followedPubkeys.contains(pubkey),
            body: "",
            createdAt: Int(Date().timeIntervalSince1970),
            avatarPictureState: .metadataPending,
            avatarImageURL: nil
        )
        return NostrTimelineMaterializer.avatar(for: item)
    }

    private func banner(for pubkey: String) -> ProfileBannerStyle {
        let palette = NostrTimelineMaterializer.avatarPalette(for: pubkey)
        return ProfileBannerStyle(colors: [palette.secondary, palette.primary], symbolName: "sparkles")
    }

    private static func profileMetadata(from event: NostrEvent) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
    }

    private static func replyParentID(from tags: [NostrStoredEventTag]) -> String? {
        let replyTag = tags.last { $0.name == "e" && $0.marker == "reply" }
        if let replyTag {
            return replyTag.value
        }

        let eTags = tags.filter { $0.name == "e" }
        let hasMarkedThreadTags = eTags.contains { $0.marker != nil }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last?.value
    }

    private static func replyParentID(from tags: [[String]]) -> String? {
        let replyTag = tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        if let replyTag, replyTag.count >= 2 {
            return replyTag[1]
        }

        let eTags = tags.filter { tag in
            tag.count >= 2 && tag[0] == "e"
        }
        let hasMarkedThreadTags = eTags.contains { $0.count >= 4 }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last?[1]
    }

    private func loaderState() -> NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            relayListEvent: relayListEvent,
            contactListEvent: contactListEvent,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            relaySyncEvents: relaySyncEvents
        )
    }

    private func apply(_ state: NostrHomeTimelineState) {
        resolvedRelays = state.relays
        followedPubkeys = state.followedPubkeys
        noteEvents = state.noteEvents
        metadataEvents = state.metadataEvents
        relayListEvent = state.relayListEvent
        contactListEvent = state.contactListEvent
        nip05Resolutions = state.nip05Resolutions
        relaySyncEvents = state.relaySyncEvents
        hasMoreOlder = state.hasMoreOlder
    }
}

enum NostrTimelineMaterializer {
    private struct SortableTimelineEntry {
        let id: String
        let sortTimestamp: Int
        let entry: TimelineFeedEntry
    }

    static func entries(
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        deletedEntries: [NostrDeletedTimelineEntryRecord] = []
    ) -> [TimelineFeedEntry] {
        let deletedTargetIDs = Set(deletedEntries.map(\.targetEventID))
        let postsByID = Dictionary(uniqueKeysWithValues: posts(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
            filterRules: filterRules
        )
        .filter { !deletedTargetIDs.contains($0.id) }
        .map { ($0.id, $0) })

        let postEntries = noteEvents.compactMap { event -> SortableTimelineEntry? in
            guard let post = postsByID[event.id] else { return nil }
            return SortableTimelineEntry(
                id: post.id,
                sortTimestamp: event.createdAt,
                entry: .post(post)
            )
        }
        let deletedRows = deletedEntries.map { deletedEntry in
            SortableTimelineEntry(
                id: deletedEntry.targetEventID,
                sortTimestamp: deletedEntry.sortTimestamp,
                entry: .deleted(TimelineDeletedEntry(id: "deleted-\(deletedEntry.targetEventID)"))
            )
        }

        return (postEntries + deletedRows)
            .sorted { lhs, rhs in
                if lhs.sortTimestamp == rhs.sortTimestamp {
                    return lhs.id < rhs.id
                }
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            .map(\.entry)
    }

    static func posts(
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> [TimelinePost] {
        let eventsByID = Dictionary(uniqueKeysWithValues: noteEvents.map { ($0.id, $0) })
        let directPosts = NostrHomeTimelineMaterializer.items(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions,
            filterRules: filterRules,
            now: now
        )
        .compactMap { item -> SortableTimelinePost? in
            guard let event = eventsByID[item.id] else { return nil }
            return SortableTimelinePost(
                id: event.id,
                sortTimestamp: event.createdAt,
                post: post(
                    for: item,
                    event: event,
                    eventsByID: eventsByID,
                    mediaAssets: mediaAssetsByEventID[event.id] ?? [],
                    linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL
                )
            )
        }
        let reposts = repostPosts(
            from: noteEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys,
            eventsByID: eventsByID,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL
        )

        return (directPosts + reposts)
            .sorted { lhs, rhs in
                if lhs.sortTimestamp == rhs.sortTimestamp {
                    return lhs.id < rhs.id
                }
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            .map(\.post)
    }

    static func post(for item: NostrHomeTimelineItem) -> TimelinePost {
        post(for: item, event: nil, eventsByID: [:])
    }

    private static func post(
        for item: NostrHomeTimelineItem,
        event: NostrEvent?,
        eventsByID: [String: NostrEvent],
        mediaAssets: [NostrMediaAssetRecord] = [],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        idOverride: String? = nil,
        repostedBy: TimelineRepostAttribution? = nil
    ) -> TimelinePost {
        let author: TimelineAuthor
        if let displayName = item.displayName {
            author = .resolved(
                displayName: displayName,
                nip05: item.nip05,
                nip05Status: NIP05Status(item.nip05Status),
                pubkey: item.pubkey,
                isFollowed: item.isFollowed
            )
        } else {
            author = .unresolved(pubkey: item.pubkey)
        }
        let urls = event.map(urls(from:)) ?? []
        let imageURLs = urls.filter(isImageURL)
        let linkURLs = urls.filter { !isImageURL($0) }
        let contentWarning = event.flatMap(contentWarning(from:))

        return TimelinePost(
            id: idOverride ?? item.id,
            author: author,
            avatar: avatar(for: item),
            body: item.body,
            timestamp: relativeTimestamp(from: item.createdAt),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: media(
                assets: mediaAssets,
                imageURLs: imageURLs,
                linkURLs: linkURLs,
                linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
                pubkey: item.pubkey
            ),
            context: nil,
            repostedBy: repostedBy,
            quotedPost: event.flatMap { quotedPost(from: $0, eventsByID: eventsByID) },
            replyContext: event.flatMap { replyContext(from: $0, eventsByID: eventsByID, fallbackAuthor: author) },
            replyMention: event.flatMap { replyMention(from: $0, author: author) },
            contentWarning: contentWarning,
            bodyPresentation: bodyPresentation(
                body: item.body,
                linkURLs: linkURLs,
                isFollowed: item.isFollowed,
                filterMatch: item.filterMatch
            ),
            linkSummary: linkSummary(from: linkURLs),
            actionState: .none
        )
    }

    private struct SortableTimelinePost {
        let id: String
        let sortTimestamp: Int
        let post: TimelinePost
    }

    private static func repostPosts(
        from events: [NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        followedPubkeys: Set<String>,
        eventsByID: [String: NostrEvent],
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord]
    ) -> [SortableTimelinePost] {
        events
            .filter { $0.kind == 6 }
            .compactMap { repostEvent in
                guard let targetID = repostTargetID(from: repostEvent) else { return nil }

                let attribution = repostAttribution(for: repostEvent, followedPubkeys: followedPubkeys)
                guard let targetEvent = eventsByID[targetID],
                      targetEvent.kind == 1
                else {
                    return missingRepostTarget(
                        repostEvent: repostEvent,
                        targetID: targetID,
                        attribution: attribution
                    )
                }

                let targetItem = NostrHomeTimelineMaterializer.items(
                    noteEvents: [targetEvent],
                    metadataEvents: metadataEvents,
                    followedPubkeys: followedPubkeys,
                    nip05Resolutions: nip05Resolutions
                ).first
                guard let targetItem else { return nil }

                return SortableTimelinePost(
                    id: repostEvent.id,
                    sortTimestamp: repostEvent.createdAt,
                    post: post(
                        for: targetItem,
                        event: targetEvent,
                        eventsByID: eventsByID,
                        mediaAssets: mediaAssetsByEventID[targetEvent.id] ?? [],
                        linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
                        idOverride: repostEvent.id,
                        repostedBy: attribution
                    )
                )
            }
    }

    private static func repostAttribution(
        for repostEvent: NostrEvent,
        followedPubkeys: Set<String>
    ) -> TimelineRepostAttribution {
        let repostItem = NostrHomeTimelineItem(
            id: repostEvent.id,
            pubkey: repostEvent.pubkey,
            displayName: nil,
            nip05: nil,
            nip05Status: .absent,
            isFollowed: followedPubkeys.contains(repostEvent.pubkey),
            body: "",
            createdAt: repostEvent.createdAt,
            avatarPictureState: .metadataPending,
            avatarImageURL: nil
        )
        return TimelineRepostAttribution(
            author: .unresolved(pubkey: repostEvent.pubkey),
            avatar: avatar(for: repostItem),
            timestamp: relativeTimestamp(from: repostEvent.createdAt)
        )
    }

    private static func missingRepostTarget(
        repostEvent: NostrEvent,
        targetID: String,
        attribution: TimelineRepostAttribution
    ) -> SortableTimelinePost {
        let targetPubkey = repostEvent.tags.first { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1].count == 64
        }?[1] ?? TimelineAuthor.mockPubkey(for: targetID)
        let author = TimelineAuthor.unresolved(pubkey: targetPubkey)
        let avatar = AvatarStyle(
            primary: .secondary,
            secondary: .gray,
            symbolName: "arrow.triangle.2.circlepath",
            pictureState: .metadataPending,
            placeholderSeed: targetPubkey
        )
        let post = TimelinePost(
            id: repostEvent.id,
            author: author,
            avatar: avatar,
            body: "Reposted post unavailable",
            timestamp: relativeTimestamp(from: repostEvent.createdAt),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil,
            repostedBy: attribution,
            bodyPresentation: .collapsed(lineLimit: 1, reason: .longText),
            actionState: .none
        )
        return SortableTimelinePost(id: repostEvent.id, sortTimestamp: repostEvent.createdAt, post: post)
    }

    static func avatar(for item: NostrHomeTimelineItem) -> AvatarStyle {
        let palette = avatarPalette(for: item.pubkey)
        return AvatarStyle(
            primary: palette.primary,
            secondary: palette.secondary,
            symbolName: "person.fill",
            pictureState: AvatarPictureState(item.avatarPictureState),
            placeholderSeed: item.pubkey,
            imageURL: item.avatarImageURL
        )
    }

    static func avatarPalette(for pubkey: String) -> (primary: Color, secondary: Color) {
        let colors: [Color] = [.purple, .cyan, .mint, .orange, .pink, .blue, .green, .indigo]
        let seed = pubkey.utf8.reduce(0) { Int($0) + Int($1) }
        return (colors[seed % colors.count], colors[(seed / 3 + 2) % colors.count])
    }

    private static func relativeTimestamp(from createdAt: Int) -> String {
        let delta = max(0, Int(Date().timeIntervalSince1970) - createdAt)
        if delta < 60 {
            return "\(delta)s"
        }
        if delta < 3_600 {
            return "\(delta / 60)m"
        }
        if delta < 86_400 {
            return "\(delta / 3_600)h"
        }
        return "\(delta / 86_400)d"
    }

    private static func urls(from event: NostrEvent) -> [URL] {
        let contentURLs = event.content
            .split(whereSeparator: \.isWhitespace)
            .compactMap { token -> URL? in
                let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\n"))
                guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return nil }
                return URL(string: trimmed)
            }
        let imetaURLs = event.tags.compactMap { tag -> URL? in
            guard tag.first == "imeta" else { return nil }
            for item in tag.dropFirst() where item.hasPrefix("url ") {
                return URL(string: String(item.dropFirst(4)))
            }
            return nil
        }
        var seen = Set<String>()
        return (contentURLs + imetaURLs).filter { seen.insert($0.absoluteString).inserted }
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return [".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic"].contains { path.hasSuffix($0) }
    }

    private static func media(
        assets: [NostrMediaAssetRecord],
        imageURLs: [URL],
        linkURLs: [URL],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord],
        pubkey: String
    ) -> TimelineMedia? {
        if !assets.isEmpty {
            let palette = avatarPalette(for: pubkey)
            let tiles = assets.prefix(5).compactMap { asset -> MediaTile? in
                guard let url = URL(string: asset.url) else { return nil }
                return MediaTile(
                    title: asset.alt ?? (url.lastPathComponent.isEmpty ? (url.host ?? "media") : url.lastPathComponent),
                    colors: [palette.primary, palette.secondary],
                    symbolName: asset.mimeType?.hasPrefix("video/") == true ? "play.rectangle" : "photo",
                    url: url,
                    altText: asset.alt
                )
            }
            if !tiles.isEmpty {
                return .gallery(Array(tiles))
            }
        }

        if !imageURLs.isEmpty {
            let palette = avatarPalette(for: pubkey)
            let tiles = imageURLs.prefix(5).map { url in
                MediaTile(
                    title: url.lastPathComponent.isEmpty ? (url.host ?? "media") : url.lastPathComponent,
                    colors: [palette.primary, palette.secondary],
                    symbolName: "photo"
                )
            }
            return .gallery(Array(tiles))
        }

        guard let link = linkURLs.first else { return nil }
        let normalizedURL = NostrLinkParser.normalizedURLString(link)
        if let preview = linkPreviewsByNormalizedURL[normalizedURL],
           preview.status == "resolved",
           let title = preview.title {
            return .linkPreview(LinkPreview(
                title: title,
                subtitle: preview.summary ?? preview.siteName ?? normalizedURL,
                host: preview.siteName ?? link.host ?? link.absoluteString,
                url: preview.url
            ))
        }
        return .unresolvedLink(UnresolvedLinkPreview(host: link.host ?? link.absoluteString, url: link.absoluteString))
    }

    private static func contentWarning(from event: NostrEvent) -> TimelineContentWarning? {
        guard let tag = event.tags.first(where: { $0.first == "content-warning" }) else { return nil }
        return TimelineContentWarning(reason: tag.dropFirst().first)
    }

    private static func replyContext(
        from event: NostrEvent,
        eventsByID: [String: NostrEvent],
        fallbackAuthor: TimelineAuthor
    ) -> TimelineReplyContext? {
        guard let parentID = replyParentID(from: event.tags),
              let parent = eventsByID[parentID]
        else { return nil }

        let parentItem = NostrHomeTimelineItem(
            id: parent.id,
            pubkey: parent.pubkey,
            displayName: nil,
            nip05: nil,
            nip05Status: .absent,
            isFollowed: true,
            body: parent.content,
            createdAt: parent.createdAt,
            avatarPictureState: .metadataPending,
            avatarImageURL: nil
        )
        let parentAuthor = parent.pubkey == event.pubkey ? fallbackAuthor : TimelineAuthor.unresolved(pubkey: parent.pubkey)
        return TimelineReplyContext(
            author: parentAuthor,
            avatar: avatar(for: parentItem),
            timestamp: relativeTimestamp(from: parent.createdAt),
            bodyPreview: parent.content,
            isSelfReply: parent.pubkey == event.pubkey
        )
    }

    private static func replyMention(from event: NostrEvent, author: TimelineAuthor) -> TimelineReplyMention? {
        guard replyParentID(from: event.tags) != nil,
              let pubkey = event.tags.first(where: { $0.first == "p" && $0.count >= 2 })?[1],
              pubkey != event.pubkey
        else { return nil }

        let display = "@\(pubkey.prefix(10))"
        return TimelineReplyMention(text: String(display), isExternal: pubkey != author.pubkey)
    }

    private static func quotedPost(from event: NostrEvent, eventsByID: [String: NostrEvent]) -> QuotedTimelinePost? {
        guard let quotedID = quotedPostID(from: event) else { return nil }
        if let quoted = eventsByID[quotedID] {
            let item = NostrHomeTimelineItem(
                id: quoted.id,
                pubkey: quoted.pubkey,
                displayName: nil,
                nip05: nil,
                nip05Status: .absent,
                isFollowed: true,
                body: quoted.content,
                createdAt: quoted.createdAt,
                avatarPictureState: .metadataPending,
                avatarImageURL: nil
            )
            return QuotedTimelinePost(
                author: TimelineAuthor.unresolved(pubkey: quoted.pubkey),
                avatar: avatar(for: item),
                body: quoted.content,
                timestamp: relativeTimestamp(from: quoted.createdAt),
                isAvailable: true
            )
        }

        return QuotedTimelinePost(
            author: TimelineAuthor.unresolved(pubkey: quotedID),
            avatar: AvatarStyle(primary: .secondary, secondary: .gray, symbolName: "quote.bubble.fill", pictureState: .metadataPending, placeholderSeed: quotedID),
            body: "Quoted note is not cached yet.",
            timestamp: "",
            isAvailable: false
        )
    }

    private static func quotedPostID(from event: NostrEvent) -> String? {
        if let quotedTagID = event.tags.last(where: { $0.first == "q" && $0.count >= 2 })?[1] {
            return quotedTagID
        }
        if let contentReference = nip19EventReference(in: event.content) {
            return contentReference
        }
        return quoteLikeEventID(from: event.tags)
    }

    private static func nip19EventReference(in content: String) -> String? {
        content
            .split(whereSeparator: \.isWhitespace)
            .lazy
            .compactMap { token -> String? in
                let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\n"))
                guard trimmed.hasPrefix("note1") || trimmed.hasPrefix("nostr:note1") else { return nil }
                return try? NostrNIP19.eventIDHex(from: trimmed)
            }
            .first
    }

    private static func quoteLikeEventID(from tags: [[String]]) -> String? {
        tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "mention"
        }?[1]
    }

    private static func repostTargetID(from event: NostrEvent) -> String? {
        event.tags.last { tag in
            tag.count >= 2 && tag[0] == "e"
        }?[1]
    }

    private static func bodyPresentation(
        body: String,
        linkURLs: [URL],
        isFollowed: Bool,
        filterMatch: NostrFilterMatchReason? = nil
    ) -> TimelineBodyPresentation {
        if filterMatch != nil {
            return .collapsed(lineLimit: 2, reason: .filtered)
        }
        if !isFollowed && !linkURLs.isEmpty {
            return .collapsed(lineLimit: 3, reason: .lowTrustLinks)
        }
        if linkURLs.count >= 5 {
            return .collapsed(lineLimit: 4, reason: .linkHeavy)
        }
        if body.count > 1_000 {
            return .collapsed(lineLimit: 8, reason: .longText)
        }
        return .standard
    }

    private static func linkSummary(from linkURLs: [URL]) -> TimelineLinkSummary? {
        guard !linkURLs.isEmpty else { return nil }
        let hosts = Array(Set(linkURLs.compactMap(\.host))).sorted()
        return TimelineLinkSummary(totalCount: linkURLs.count, visibleHosts: hosts, unresolvedCount: linkURLs.count)
    }

    private static func replyParentID(from tags: [[String]]) -> String? {
        let replyTag = tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        if let replyTag, replyTag.count >= 2 {
            return replyTag[1]
        }

        let eTags = tags.filter { tag in
            tag.count >= 2 && tag[0] == "e"
        }
        let hasMarkedThreadTags = eTags.contains { $0.count >= 4 }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last?[1]
    }
}

private extension NIP05Status {
    init(_ coreStatus: NostrNIP05Status) {
        switch coreStatus {
        case .absent:
            self = .absent
        case .unchecked:
            self = .unchecked
        case .verified:
            self = .valid
        case .invalid, .failed:
            self = .invalid
        }
    }
}
