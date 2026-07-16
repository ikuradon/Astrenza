import AstrenzaCore
@testable import Astrenza

@MainActor
final class StoreRestoreEventRecorder {
    enum Event: Equatable {
        case reloadProjection(
            accountID: String,
            anchorEventID: String?,
            mergesCurrentWindow: Bool
        )
        case materialize(allowsRealtimeFollow: Bool)
        case scheduleLinkPreviewResolution
        case applyActivityIntent(HomeTimelineActivityIntent)
    }

    private(set) var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }
}

@MainActor
final class StoreRestoreSourceSpy: HomeStoreRestoreSourcing {
    var identity: HomeStoreRestoreIdentity

    init(identity: HomeStoreRestoreIdentity) {
        self.identity = identity
    }

    func restoreIdentity() -> HomeStoreRestoreIdentity {
        identity
    }
}

@MainActor
final class StoreRestoreProjectionSpy:
    HomeStoreRestoreProjectionReloading {
    private let events: StoreRestoreEventRecorder
    private var completion: HomeTimelineMaterializationCoordinating
        .ProjectionReloadHandler?

    init(events: StoreRestoreEventRecorder) {
        self.events = events
    }

    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    ) {
        events.record(.reloadProjection(
            accountID: account.pubkey,
            anchorEventID: anchorEventID,
            mergesCurrentWindow: mergingWithCurrentWindow
        ))
        completion = onCompletion
    }

    func complete(didReload: Bool) {
        let completion = completion
        self.completion = nil
        completion?(didReload)
    }
}

@MainActor
final class StoreRestorePresentationSpy: HomeStoreRestoreMaterializing {
    private let events: StoreRestoreEventRecorder
    private var transition: HomeTimelineMaterializationCoordinating
        .TransitionHandler?

    init(events: StoreRestoreEventRecorder) {
        self.events = events
    }

    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    ) {
        events.record(.materialize(
            allowsRealtimeFollow: allowsRealtimeFollow
        ))
        transition = onTransition
    }

    func complete(hasEntries: Bool) {
        let transition = transition
        self.transition = nil
        transition?(Self.presentationTransition(hasEntries: hasEntries))
    }

    private static func presentationTransition(
        hasEntries: Bool
    ) -> HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: hasEntries
                    ? [.deleted(TimelineDeletedEntry(id: "restored"))]
                    : [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 1,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries],
            didChangeReadState: false
        )
    }
}

@MainActor
final class StoreRestoreLinkPreviewSpy:
    HomeStoreRestoreLinkPreviewScheduling {
    private let events: StoreRestoreEventRecorder

    init(events: StoreRestoreEventRecorder) {
        self.events = events
    }

    func scheduleLinkPreviewResolution() -> Bool {
        events.record(.scheduleLinkPreviewResolution)
        return true
    }
}

@MainActor
final class StoreRestoreActivitySpy:
    HomeStoreRestoreActivityPublishing {
    private let events: StoreRestoreEventRecorder

    init(events: StoreRestoreEventRecorder) {
        self.events = events
    }

    func applyActivityIntent(_ intent: HomeTimelineActivityIntent) {
        events.record(.applyActivityIntent(intent))
    }
}

@MainActor
struct StoreRestoreCoordinatorFixture {
    let anchorEventID: String?
    let account: NostrAccount
    let replacementAccount: NostrAccount
    let events: StoreRestoreEventRecorder
    let source: StoreRestoreSourceSpy
    let projection: StoreRestoreProjectionSpy
    let presentation: StoreRestorePresentationSpy
    let linkPreview: StoreRestoreLinkPreviewSpy
    let activity: StoreRestoreActivitySpy
    let coordinator: HomeStoreRestoreCoordinator

    init(anchorEventID: String? = "anchor") {
        let account = Self.makeAccount(pubkeyCharacter: "a")
        let events = StoreRestoreEventRecorder()
        let source = StoreRestoreSourceSpy(
            identity: HomeStoreRestoreIdentity(
                accountID: account.pubkey,
                anchorEventID: anchorEventID
            )
        )
        let projection = StoreRestoreProjectionSpy(events: events)
        let presentation = StoreRestorePresentationSpy(events: events)
        let linkPreview = StoreRestoreLinkPreviewSpy(events: events)
        let activity = StoreRestoreActivitySpy(events: events)

        self.anchorEventID = anchorEventID
        self.account = account
        replacementAccount = Self.makeAccount(pubkeyCharacter: "b")
        self.events = events
        self.source = source
        self.projection = projection
        self.presentation = presentation
        self.linkPreview = linkPreview
        self.activity = activity
        coordinator = HomeStoreRestoreCoordinator(
            source: source,
            projection: projection,
            presentation: presentation,
            linkPreview: linkPreview,
            activity: activity
        )
    }

    static func makeAccount(pubkeyCharacter: Character) -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: pubkeyCharacter, count: 64),
            displayIdentifier: "restore-projection",
            readOnly: true
        )
    }
}
