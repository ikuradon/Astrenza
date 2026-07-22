import AstrenzaCore

struct HomeTimelineContentSnapshot: Equatable, Sendable {
    let resolvedRelays: [String]
    let followedPubkeys: [String]
    let noteEvents: [NostrEvent]
    let metadataEvents: [NostrEvent]
    let relayListEvent: NostrEvent?
    let contactListEvent: NostrEvent?
    let authorRelayListEvents: [NostrEvent]
    let hasMoreOlder: Bool

    init(
        resolvedRelays: [String],
        followedPubkeys: [String],
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent],
        relayListEvent: NostrEvent?,
        contactListEvent: NostrEvent?,
        authorRelayListEvents: [NostrEvent] = [],
        hasMoreOlder: Bool
    ) {
        self.resolvedRelays = resolvedRelays
        self.followedPubkeys = followedPubkeys
        self.noteEvents = noteEvents
        self.metadataEvents = metadataEvents
        self.relayListEvent = relayListEvent
        self.contactListEvent = contactListEvent
        self.authorRelayListEvents = authorRelayListEvents
        self.hasMoreOlder = hasMoreOlder
    }

    static let initial = HomeTimelineContentSnapshot(
        resolvedRelays: [],
        followedPubkeys: [],
        noteEvents: [],
        metadataEvents: [],
        relayListEvent: nil,
        contactListEvent: nil,
        hasMoreOlder: true
    )
}

struct HomeTimelineMetadataUpdate: Equatable, Sendable {
    let event: NostrEvent
    let didChange: Bool
}

@MainActor
final class HomeTimelineContentCoordinator {
    private let eventStore: NostrEventStore?
    private var state = HomeTimelineContentSnapshot.initial

    init(eventStore: NostrEventStore?) {
        self.eventStore = eventStore
    }

    var snapshot: HomeTimelineContentSnapshot {
        state
    }

    var noteEvents: [NostrEvent] {
        state.noteEvents
    }

    var metadataEvents: [NostrEvent] {
        state.metadataEvents
    }

    var relayListEvent: NostrEvent? {
        state.relayListEvent
    }

    var contactListEvent: NostrEvent? {
        state.contactListEvent
    }

    func reset() -> HomeTimelineContentSnapshot {
        state = .initial
        return state
    }

    func replace(
        with incoming: NostrHomeTimelineState
    ) -> HomeTimelineContentSnapshot {
        // `NostrHomeTimelineState` は、MainActorへ届く前に永続化／loader workerで
        // hydrate済みです。ここでreplaceable headを再検索すると処理が重複し、
        // 大きなfollow集合の同期read中に起動アニメーションを止めてしまいます。
        let effectiveRelayListEvent = freshestReplaceableEvent([
            state.relayListEvent,
            incoming.relayListEvent
        ])
        let effectiveContactListEvent = freshestReplaceableEvent([
            state.contactListEvent,
            incoming.contactListEvent
        ])
        let readRelays = NostrRelayList.parse(from: effectiveRelayListEvent).readRelays
        let effectiveRelays: [String]
        if !readRelays.isEmpty {
            effectiveRelays = readRelays
        } else if !incoming.relays.isEmpty {
            effectiveRelays = incoming.relays
        } else {
            effectiveRelays = state.resolvedRelays
        }
        let effectiveFollowedPubkeys: [String]
        if effectiveContactListEvent?.id != nil,
           effectiveContactListEvent?.id != incoming.contactListEvent?.id {
            effectiveFollowedPubkeys = NostrContactList.pubkeys(from: effectiveContactListEvent)
        } else {
            effectiveFollowedPubkeys = incoming.followedPubkeys
        }
        let effectiveAuthorRelayListEvents = freshestReplaceableEventsByAuthor(
            state.authorRelayListEvents + incoming.authorRelayListEvents,
            authors: Set(effectiveFollowedPubkeys)
        )

        state = HomeTimelineContentSnapshot(
            resolvedRelays: effectiveRelays,
            followedPubkeys: effectiveFollowedPubkeys,
            noteEvents: incoming.noteEvents,
            metadataEvents: incoming.metadataEvents,
            relayListEvent: effectiveRelayListEvent,
            contactListEvent: effectiveContactListEvent,
            authorRelayListEvents: effectiveAuthorRelayListEvents,
            hasMoreOlder: incoming.hasMoreOlder
        )
        return state
    }

    func replaceProjectionEvents(_ events: [NostrEvent]) {
        state = state.replacing(noteEvents: events)
    }

    func installProvisionalRelays(_ relays: [String]) -> HomeTimelineContentSnapshot {
        state = state.replacing(resolvedRelays: relays)
        return state
    }

    func replaceFollowedPubkeys(_ pubkeys: [String]) -> HomeTimelineContentSnapshot {
        state = state.replacing(followedPubkeys: pubkeys)
        return state
    }

    func insertOutboxEvent(
        _ event: NostrEvent,
        accountID: String
    ) -> HomeTimelineContentSnapshot {
        var noteEvents = state.noteEvents
        noteEvents.removeAll { $0.id == event.id }
        noteEvents.insert(event, at: 0)
        var followedPubkeys = state.followedPubkeys
        if !followedPubkeys.contains(accountID) {
            followedPubkeys.append(accountID)
        }
        state = state.replacing(
            followedPubkeys: followedPubkeys,
            noteEvents: noteEvents
        )
        return state
    }

    func markOlderEnd() -> HomeTimelineContentSnapshot {
        state = state.replacing(hasMoreOlder: false)
        return state
    }

    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true
    ) -> HomeTimelineMetadataUpdate {
        let storedMetadataEvent = consultEventStore
            ? try? eventStore?.latestReplaceableEvent(pubkey: event.pubkey, kind: 0)
            : nil
        let currentMetadataEvent = state.metadataEvents.first { $0.pubkey == event.pubkey }
        let effectiveMetadataEvent = freshestReplaceableEvent([
            currentMetadataEvent,
            event,
            storedMetadataEvent
        ]) ?? event
        let didChange = currentMetadataEvent?.id != effectiveMetadataEvent.id
        var metadataEvents = state.metadataEvents
        metadataEvents.removeAll { $0.pubkey == event.pubkey }
        metadataEvents.append(effectiveMetadataEvent)
        state = state.replacing(metadataEvents: metadataEvents)
        return HomeTimelineMetadataUpdate(
            event: effectiveMetadataEvent,
            didChange: didChange
        )
    }

    func removeEventsDeletedFromCurrentProjection(by deletionEvent: NostrEvent) -> String? {
        let targetEventIDs = Set(deletionEvent.tags.compactMap { tag in
            tag.count >= 2 && tag[0] == "e" ? tag[1] : nil
        })
        guard !targetEventIDs.isEmpty else { return nil }
        let retainedEvents = state.noteEvents.filter { event in
            !targetEventIDs.contains(event.id) || event.pubkey != deletionEvent.pubkey
        }
        state = state.replacing(noteEvents: retainedEvents)
        return targetEventIDs.sorted().first
    }

    func loaderState(
        nip05Resolutions: [String: NostrNIP05Resolution],
        relaySyncEvents: [NostrRelaySyncEventRecord]
    ) -> NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: state.resolvedRelays,
            followedPubkeys: state.followedPubkeys,
            noteEvents: state.noteEvents,
            metadataEvents: state.metadataEvents,
            relayListEvent: state.relayListEvent,
            contactListEvent: state.contactListEvent,
            authorRelayListEvents: state.authorRelayListEvents,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: state.hasMoreOlder,
            relaySyncEvents: relaySyncEvents
        )
    }

    func runtimeBootstrapState(
        from bootstrapState: NostrHomeTimelineState,
        nip05Resolutions: [String: NostrNIP05Resolution]
    ) -> NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: bootstrapState.relays,
            followedPubkeys: bootstrapState.followedPubkeys,
            noteEvents: state.noteEvents,
            metadataEvents: state.metadataEvents,
            relayListEvent: bootstrapState.relayListEvent,
            contactListEvent: bootstrapState.contactListEvent,
            authorRelayListEvents: bootstrapState.authorRelayListEvents,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: state.hasMoreOlder,
            relaySyncEvents: bootstrapState.relaySyncEvents.map { event in
                NostrRelaySyncEventRecord(
                    accountID: event.accountID,
                    timelineKey: event.timelineKey,
                    relayURL: event.relayURL,
                    kind: event.kind,
                    occurredAt: event.occurredAt,
                    subscriptionID: event.subscriptionID,
                    eventCount: event.eventCount,
                    newestCreatedAt: nil,
                    oldestCreatedAt: nil,
                    latencyMilliseconds: event.latencyMilliseconds,
                    message: event.message
                )
            }
        )
    }

    private func freshestReplaceableEvent(_ events: [NostrEvent?]) -> NostrEvent? {
        events.compactMap(\.self).max { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func freshestReplaceableEventsByAuthor(
        _ events: [NostrEvent],
        authors: Set<String>
    ) -> [NostrEvent] {
        let normalizedAuthors = Set(authors.map { $0.lowercased() })
        var latestByAuthor: [String: NostrEvent] = [:]
        for event in events where event.kind == 10_002 {
            let author = event.pubkey.lowercased()
            guard normalizedAuthors.contains(author) else { continue }
            let latest = freshestReplaceableEvent([
                latestByAuthor[author],
                event
            ])
            latestByAuthor[author] = latest
        }
        return latestByAuthor.values.sorted { $0.pubkey < $1.pubkey }
    }
}

private extension HomeTimelineContentSnapshot {
    func replacing(
        resolvedRelays: [String]? = nil,
        followedPubkeys: [String]? = nil,
        noteEvents: [NostrEvent]? = nil,
        metadataEvents: [NostrEvent]? = nil,
        hasMoreOlder: Bool? = nil
    ) -> HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot(
            resolvedRelays: resolvedRelays ?? self.resolvedRelays,
            followedPubkeys: followedPubkeys ?? self.followedPubkeys,
            noteEvents: noteEvents ?? self.noteEvents,
            metadataEvents: metadataEvents ?? self.metadataEvents,
            relayListEvent: relayListEvent,
            contactListEvent: contactListEvent,
            authorRelayListEvents: authorRelayListEvents,
            hasMoreOlder: hasMoreOlder ?? self.hasMoreOlder
        )
    }
}
