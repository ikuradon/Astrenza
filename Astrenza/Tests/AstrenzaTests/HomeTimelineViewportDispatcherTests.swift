import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline viewport application dispatcher")
@MainActor
struct HomeTimelineViewportDispatcherTests {
    @Test("Applications preserve effect order and payloads")
    func applicationsDispatchEffects() {
        let fixture = ViewportApplicationDispatcherFixture()
        let transition = fixture.presentationTransition
        let applications: [HomeTimelineViewportApplication] = [
            .applyProjectionViewportTransition(.setRestoreAnchor("anchor")),
            .reloadNewestProjectionWindow(fixture.account),
            .materializeEntries(allowsRealtimeFollow: true),
            .applyRestoreProjectionAnchor(fixture.account),
            .applyPresentationTransition(transition),
            .scheduleReadStateSave,
            .applyPendingEventCountPublication(
                HomeTimelinePendingEventCountPublication(count: 3)
            ),
            .clearPendingProjectionReload,
            .scheduleLinkPreviewResolution
        ]

        for application in applications {
            fixture.dispatcher.apply(application, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .projectionViewportTransition(.setRestoreAnchor("anchor")),
            .reloadNewestProjectionWindow(fixture.account.pubkey),
            .materializeEntries(allowsRealtimeFollow: true),
            .applyRestoreProjectionAnchor(fixture.account.pubkey),
            .presentationTransition(
                changes: transition.changes.rawValue,
                didChangeReadState: transition.didChangeReadState
            ),
            .scheduleReadStateSave,
            .pendingEventCountPublication(3),
            .clearPendingProjectionReload,
            .scheduleLinkPreviewResolution
        ])
    }

    @Test("Loads preserve account lifecycle and order")
    func loadsDispatchEffects() async {
        let fixture = ViewportApplicationDispatcherFixture()

        await fixture.dispatcher.perform(
            .refreshLatest(fixture.account, fixture.lifecycle),
            effects: fixture.effects
        )
        await fixture.dispatcher.perform(
            .loadOlder(fixture.account, fixture.lifecycle),
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .refreshLatest(
                accountID: fixture.account.pubkey,
                lifecycle: fixture.lifecycle
            ),
            .loadOlder(
                accountID: fixture.account.pubkey,
                lifecycle: fixture.lifecycle
            )
        ])
    }
}

@MainActor
private final class ViewportApplicationDispatchProbe {
    enum Event: Equatable {
        case projectionViewportTransition(
            HomeTimelineProjectionViewportTransition
        )
        case reloadNewestProjectionWindow(String)
        case materializeEntries(allowsRealtimeFollow: Bool)
        case applyRestoreProjectionAnchor(String)
        case presentationTransition(
            changes: Int,
            didChangeReadState: Bool
        )
        case scheduleReadStateSave
        case pendingEventCountPublication(Int)
        case clearPendingProjectionReload
        case scheduleLinkPreviewResolution
        case refreshLatest(
            accountID: String,
            lifecycle: HomeTimelineLifecycleToken
        )
        case loadOlder(
            accountID: String,
            lifecycle: HomeTimelineLifecycleToken
        )
    }

    var events: [Event] = []
}

@MainActor
private struct ViewportApplicationDispatcherFixture {
    let dispatcher = HomeTimelineViewportDispatcher()
    let probe = ViewportApplicationDispatchProbe()

    var account: NostrAccount {
        NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "viewport-dispatcher",
            readOnly: true
        )
    }

    var lifecycle: HomeTimelineLifecycleToken {
        HomeTimelineLifecycleToken(
            accountID: account.pubkey,
            generation: 7
        )
    }

    var presentationTransition: HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 4,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries, .resolvedContentRevision],
            didChangeReadState: true
        )
    }

    var effects: HomeTimelineViewportApplicationEffects {
        HomeTimelineViewportApplicationEffects(
            applyProjectionViewportTransition: { [probe] transition in
                probe.events.append(.projectionViewportTransition(transition))
            },
            reloadNewestProjectionWindow: { [probe] account in
                probe.events.append(
                    .reloadNewestProjectionWindow(account.pubkey)
                )
            },
            materializeEntries: { [probe] allowsRealtimeFollow in
                probe.events.append(.materializeEntries(
                    allowsRealtimeFollow: allowsRealtimeFollow
                ))
            },
            waitForPendingPresentation: { true },
            applyRestoreProjectionAnchor: { [probe] account in
                probe.events.append(.applyRestoreProjectionAnchor(
                    account.pubkey
                ))
            },
            applyPresentationTransition: { [probe] transition in
                probe.events.append(.presentationTransition(
                    changes: transition.changes.rawValue,
                    didChangeReadState: transition.didChangeReadState
                ))
            },
            scheduleReadStateSave: { [probe] in
                probe.events.append(.scheduleReadStateSave)
            },
            applyPendingEventCountPublication: { [probe] publication in
                probe.events.append(.pendingEventCountPublication(
                    publication.count
                ))
            },
            clearPendingProjectionReload: { [probe] in
                probe.events.append(.clearPendingProjectionReload)
            },
            scheduleLinkPreviewResolution: { [probe] in
                probe.events.append(.scheduleLinkPreviewResolution)
            },
            refreshLatest: { [probe] account, lifecycle in
                probe.events.append(.refreshLatest(
                    accountID: account.pubkey,
                    lifecycle: lifecycle
                ))
            },
            loadOlder: { [probe] account, lifecycle in
                probe.events.append(.loadOlder(
                    accountID: account.pubkey,
                    lifecycle: lifecycle
                ))
            }
        )
    }
}
