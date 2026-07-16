import AstrenzaCore
@testable import Astrenza

@MainActor
final class StoreApplicationDispatchProbe {
    enum Event: Equatable {
        case presentation(changes: Int)
        case contentRelays([String])
        case relaySnapshot(plannedCount: Int)
        case listRevision(Int)
        case pendingCount(Int)
        case reloadProjection(
            accountID: String,
            anchorEventID: String?,
            mergingWithCurrentWindow: Bool
        )
        case reloadNewestProjectionWindow(String)
        case requestNewestProjectionReload
        case scheduleMaterialization(
            delayNanoseconds: UInt64?,
            allowsRealtimeFollow: Bool?
        )
        case materializeEntries
        case relayTransition(HomeTimelineRelayStatusTransition?)
        case setRealtime(Bool)
        case setPhase(NostrHomeTimelinePhase)
        case backwardCompletion(NostrBackwardREQCompletion)
        case invalidateListEntries
        case scheduleLinkPreviewResolution
        case publishProfileMetadataChange
        case publishRelayStatusChange
        case runtimeEvent(
            relayURL: String,
            subscriptionID: String,
            eventID: String
        )
        case persistDatabase(String)
    }

    var events: [Event] = []
}

@MainActor
struct StoreApplicationDispatcherFixture {
    let dispatcher = HomeTimelineStoreApplicationDispatcher()
    let probe = StoreApplicationDispatchProbe()

    var account: NostrAccount {
        NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "dispatcher",
            readOnly: true
        )
    }

    var presentationTransition: HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 0,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries, .unreadCounts],
            didChangeReadState: false
        )
    }

    var contentSnapshot: HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot(
            resolvedRelays: ["wss://content.example"],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        )
    }

    var relaySnapshot: HomeTimelineRelayStatusSnapshot {
        HomeTimelineRelayStatusSnapshot(
            runtimeStates: [:],
            connectedRelayCount: 1,
            plannedRelayCount: 2
        )
    }

    var relayTransition: HomeTimelineRelayStatusTransition {
        HomeTimelineRelayStatusTransition(
            snapshot: relaySnapshot,
            invalidatedRealtimeRelayURL: "wss://stale.example",
            publishesStatusChange: true
        )
    }

    var backwardCompletion: NostrBackwardREQCompletion {
        NostrBackwardREQCompletion(
            groupID: "backward",
            relayURLs: ["wss://relay.example"],
            subscriptionIDs: ["backward-subscription"],
            eventCount: 2,
            eoseCount: 1,
            closedCount: 0,
            timeoutCount: 0
        )
    }

    var event: NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: account.pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "event",
            sig: String(repeating: "2", count: 128)
        )
    }

    var effects: HomeTimelineStoreApplicationEffects {
        HomeTimelineStoreApplicationEffects(
            applyPresentationTransition: { [probe] transition in
                probe.events.append(.presentation(
                    changes: transition.changes.rawValue
                ))
            },
            applyContentSnapshot: { [probe] snapshot in
                probe.events.append(.contentRelays(snapshot.resolvedRelays))
            },
            applyRelayStatusSnapshot: { [probe] snapshot in
                probe.events.append(.relaySnapshot(
                    plannedCount: snapshot.plannedRelayCount
                ))
            },
            applyListProjectionInvalidation: { [probe] invalidation in
                probe.events.append(.listRevision(invalidation.revision))
            },
            applyPendingEventCountPublication: { [probe] publication in
                probe.events.append(.pendingCount(publication.count))
            },
            reloadProjection: { [probe] account, anchorEventID, merging in
                probe.events.append(.reloadProjection(
                    accountID: account.pubkey,
                    anchorEventID: anchorEventID,
                    mergingWithCurrentWindow: merging
                ))
            },
            reloadNewestProjectionWindow: { [probe] account in
                probe.events.append(.reloadNewestProjectionWindow(
                    account.pubkey
                ))
            },
            requestNewestProjectionReload: { [probe] in
                probe.events.append(.requestNewestProjectionReload)
            },
            scheduleMaterialization: { [probe] delay, realtimeFollow in
                probe.events.append(.scheduleMaterialization(
                    delayNanoseconds: delay,
                    allowsRealtimeFollow: realtimeFollow
                ))
            },
            materializeEntries: { [probe] in
                probe.events.append(.materializeEntries)
            },
            applyRelayStatusTransition: { [probe] transition in
                probe.events.append(.relayTransition(transition))
            },
            setRealtime: { [probe] isRealtime in
                probe.events.append(.setRealtime(isRealtime))
            },
            setPhase: { [probe] phase in
                probe.events.append(.setPhase(phase))
            },
            handleBackwardCompletion: { [probe] completion in
                probe.events.append(.backwardCompletion(completion))
            },
            invalidateListEntries: { [probe] in
                probe.events.append(.invalidateListEntries)
            },
            scheduleLinkPreviewResolution: { [probe] in
                probe.events.append(.scheduleLinkPreviewResolution)
            },
            publishProfileMetadataChange: { [probe] in
                probe.events.append(.publishProfileMetadataChange)
            },
            publishRelayStatusChange: { [probe] in
                probe.events.append(.publishRelayStatusChange)
            },
            handleRuntimeEvents: { [probe] events in
                for event in events {
                    probe.events.append(.runtimeEvent(
                        relayURL: event.relayURL,
                        subscriptionID: event.subscriptionID,
                        eventID: event.event.id
                    ))
                }
            },
            persistDatabase: { [probe] account in
                probe.events.append(.persistDatabase(account.pubkey))
            }
        )
    }
}
