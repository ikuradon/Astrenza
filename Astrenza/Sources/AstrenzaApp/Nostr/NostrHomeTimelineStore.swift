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
    private let timelineCache: NostrTimelineCache
    private let eventStore: NostrEventStore?
    private var loadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var noteEvents: [NostrEvent] = []
    private var metadataEvents: [NostrEvent] = []
    private var relayListEvent: NostrEvent?
    private var contactListEvent: NostrEvent?
    private var nip05Resolutions: [String: NostrNIP05Resolution] = [:]
    init(
        timelineLoader: NostrHomeTimelineLoader = NostrHomeTimelineLoader(),
        timelineCache: NostrTimelineCache = NostrTimelineCache(),
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(appDirectory: "Astrenza")
    ) {
        self.timelineLoader = timelineLoader
        self.timelineCache = timelineCache
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
            persistSnapshot(account: account)
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
            persistSnapshot(account: account)
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
            persistSnapshot(account: account)
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

        guard let snapshot = timelineCache.snapshot(accountID: account.pubkey, timelineKey: "home") else {
            entries = []
            resolvedRelays = []
            followedPubkeys = []
            noteEvents = []
            metadataEvents = []
            relayListEvent = nil
            contactListEvent = nil
            nip05Resolutions = [:]
            hasMoreOlder = true
            return
        }

        resolvedRelays = snapshot.relays
        followedPubkeys = snapshot.followedPubkeys
        noteEvents = snapshot.events
        metadataEvents = snapshot.metadataEvents
        relayListEvent = nil
        contactListEvent = nil
        nip05Resolutions = snapshot.nip05Resolutions
        hasMoreOlder = true
        materializeEntries()
        if !entries.isEmpty {
            phase = .loaded
        }
    }

    private func persistSnapshot(account: NostrAccount) {
        timelineCache.saveSnapshot(
            accountID: account.pubkey,
            timelineKey: "home",
            relays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            events: noteEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions
        )
    }

    private func persistDatabase(account: NostrAccount) {
        guard let eventStore else { return }
        do {
            try eventStore.saveHomeTimelineState(loaderState(), accountID: account.pubkey)
        } catch {
            // The UserDefaults snapshot remains the fallback until the DB read path is fully migrated.
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
        entries = NostrTimelineMaterializer.entries(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: Set(followedPubkeys)
        )
    }

    private func materializedPosts(from events: [NostrEvent]) -> [TimelinePost] {
        let pubkeys = Set(events.map(\.pubkey))
        let metadata = (try? eventStore?.latestReplaceableEvents(pubkeys: pubkeys, kind: 0)) ?? metadataEvents.filter { pubkeys.contains($0.pubkey) }

        return NostrTimelineMaterializer.posts(
            noteEvents: events,
            metadataEvents: metadata,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: Set(followedPubkeys)
        )
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
        let fallbackTag = tags.last { $0.name == "e" }
        return replyTag?.value ?? fallbackTag?.value
    }

    private static func replyParentID(from tags: [[String]]) -> String? {
        let replyTag = tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        let fallbackTag = tags.last { tag in
            tag.count >= 2 && tag[0] == "e"
        }
        if let replyTag, replyTag.count >= 2 {
            return replyTag[1]
        }
        if let fallbackTag, fallbackTag.count >= 2 {
            return fallbackTag[1]
        }
        return nil
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
            hasMoreOlder: hasMoreOlder
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
        hasMoreOlder = state.hasMoreOlder
    }
}

enum NostrTimelineMaterializer {
    static func entries(
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>
    ) -> [TimelineFeedEntry] {
        NostrHomeTimelineMaterializer.items(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions
        )
        .map { TimelineFeedEntry.post(post(for: $0)) }
    }

    static func posts(
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>
    ) -> [TimelinePost] {
        NostrHomeTimelineMaterializer.items(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions
        )
        .map(post(for:))
    }

    static func post(for item: NostrHomeTimelineItem) -> TimelinePost {
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

        return TimelinePost(
            id: item.id,
            author: author,
            avatar: avatar(for: item),
            body: item.body,
            timestamp: relativeTimestamp(from: item.createdAt),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil,
            actionState: .none
        )
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
