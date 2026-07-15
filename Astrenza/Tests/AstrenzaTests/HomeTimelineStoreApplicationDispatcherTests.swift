import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline store application dispatcher")
@MainActor
struct HomeStoreApplicationDispatcherTests {
    @Test("State applications preserve command order and payloads")
    func stateApplicationsDispatchEffects() {
        let fixture = StoreApplicationDispatcherFixture()
        let account = fixture.account
        let transition = fixture.presentationTransition
        let content = fixture.contentSnapshot
        let relaySnapshot = fixture.relaySnapshot
        let relayTransition = fixture.relayTransition

        let applications: [HomeTimelineStateInteractionApplication] = [
            .applyPresentationTransition(transition),
            .applyContentSnapshot(content),
            .applyRelayStatusSnapshot(relaySnapshot),
            .applyListProjectionInvalidation(
                HomeTimelineListProjectionInvalidation(revision: 4)
            ),
            .applyPendingEventCountPublication(
                HomeTimelinePendingEventCountPublication(count: 3)
            ),
            .reloadProjection(account: account, anchorEventID: "anchor"),
            .requestNewestProjectionReload,
            .scheduleMaterialization(
                delayNanoseconds: 120,
                allowsRealtimeFollow: true
            ),
            .materializeEntries,
            .applyRelayStatusTransition(relayTransition)
        ]
        for application in applications {
            fixture.dispatcher.apply(application, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .presentation(changes: transition.changes.rawValue),
            .contentRelays(content.resolvedRelays),
            .relaySnapshot(plannedCount: relaySnapshot.plannedRelayCount),
            .listRevision(4),
            .pendingCount(3),
            .reloadProjection(accountID: account.pubkey, anchorEventID: "anchor"),
            .requestNewestProjectionReload,
            .scheduleMaterialization(
                delayNanoseconds: 120,
                allowsRealtimeFollow: true
            ),
            .materializeEntries,
            .relayTransition(relayTransition)
        ])
    }

    @Test("Runtime applications preserve payloads and default scheduling")
    func runtimeApplicationsDispatchEffects() {
        let fixture = StoreApplicationDispatcherFixture()
        let completion = fixture.backwardCompletion

        fixture.dispatcher.apply(.setRealtime(true), effects: fixture.effects)
        fixture.dispatcher.apply(
            .applyRelayStatusTransition(nil),
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            .handleBackwardCompletion(completion),
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            .invalidateListEntries,
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            .scheduleMaterialization,
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            .scheduleLinkPreviewResolution,
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .setRealtime(true),
            .relayTransition(nil),
            .backwardCompletion(completion),
            .invalidateListEntries,
            .scheduleMaterialization(
                delayNanoseconds: nil,
                allowsRealtimeFollow: nil
            ),
            .scheduleLinkPreviewResolution
        ])
    }

    @Test("Async runtime event preserves relay subscription and event")
    func asyncRuntimeEventDispatchesEffect() async {
        let fixture = StoreApplicationDispatcherFixture()
        let event = fixture.event

        await fixture.dispatcher.perform(
            .handleEvent(
                relayURL: "wss://relay.example",
                subscriptionID: "home-subscription",
                event: event
            ),
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .runtimeEvent(
                relayURL: "wss://relay.example",
                subscriptionID: "home-subscription",
                eventID: event.id
            )
        ])
    }
}

@MainActor
private final class StoreApplicationDispatchProbe {
    enum Event: Equatable {
        case presentation(changes: Int)
        case contentRelays([String])
        case relaySnapshot(plannedCount: Int)
        case listRevision(Int)
        case pendingCount(Int)
        case reloadProjection(accountID: String, anchorEventID: String?)
        case requestNewestProjectionReload
        case scheduleMaterialization(
            delayNanoseconds: UInt64?,
            allowsRealtimeFollow: Bool?
        )
        case materializeEntries
        case relayTransition(HomeTimelineRelayStatusTransition?)
        case setRealtime(Bool)
        case backwardCompletion(NostrBackwardREQCompletion)
        case invalidateListEntries
        case scheduleLinkPreviewResolution
        case runtimeEvent(
            relayURL: String,
            subscriptionID: String,
            eventID: String
        )
    }

    var events: [Event] = []
}

@MainActor
private struct StoreApplicationDispatcherFixture {
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
            reloadProjection: { [probe] account, anchorEventID in
                probe.events.append(.reloadProjection(
                    accountID: account.pubkey,
                    anchorEventID: anchorEventID
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
            handleBackwardCompletion: { [probe] completion in
                probe.events.append(.backwardCompletion(completion))
            },
            invalidateListEntries: { [probe] in
                probe.events.append(.invalidateListEntries)
            },
            scheduleLinkPreviewResolution: { [probe] in
                probe.events.append(.scheduleLinkPreviewResolution)
            },
            handleRuntimeEvent: { [probe] relayURL, subscriptionID, event in
                probe.events.append(.runtimeEvent(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID,
                    eventID: event.id
                ))
            }
        )
    }
}
