import AstrenzaCore
@testable import Astrenza

enum StorePresentationEvent: Equatable {
    case applied(Int)
    case completion(Int)
}

struct StorePresentationSchedule: Equatable {
    let delayNanoseconds: UInt64?
    let allowsRealtimeFollow: Bool?
}

enum StorePresentationCommand: Equatable {
    case requestNewestProjectionReload
    case clearNewestProjectionReload
    case restoreReadBoundary(String)
}

@MainActor
final class StorePresentationSourceSpy: HomeStorePresentationSourcing {
    var snapshot: HomeStoreMaterializationSnapshot
    var onApply: ((HomeTimelinePresentationTransition) -> Void)?
    private(set) var appliedTransitions:
        [HomeTimelinePresentationTransition] = []

    var appliedRevisions: [Int] {
        appliedTransitions.map(\.snapshot.resolvedContentRevision)
    }

    init(snapshot: HomeStoreMaterializationSnapshot) {
        self.snapshot = snapshot
    }

    func materializationSnapshot() -> HomeStoreMaterializationSnapshot {
        snapshot
    }

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        appliedTransitions.append(transition)
        onApply?(transition)
    }
}

@MainActor
final class StoreProjectionMaterializingSpy:
    HomeStoreProjectionMaterializing {
    private(set) var requests: [HomeTimelineMaterializationRequest] = []
    private var handlers: [HomeTimelineMaterializationCoordinating
        .TransitionHandler] = []

    func materialize(
        _ request: HomeTimelineMaterializationRequest,
        onTransition: @escaping HomeTimelineMaterializationCoordinating
            .TransitionHandler
    ) {
        requests.append(request)
        handlers.append(onTransition)
    }

    func completeLast(with transition: HomeTimelinePresentationTransition) {
        handlers.last?(transition)
    }
}

@MainActor
final class StorePresentationSchedulingSpy:
    HomeStorePresentationScheduling {
    let restoredTransition: HomeTimelinePresentationTransition
    var interactionState: HomeTimelinePresentationInteractionState
    private(set) var schedules: [StorePresentationSchedule] = []
    private(set) var commands: [StorePresentationCommand] = []
    private var scheduledMaterialize:
        HomeTimelinePresentationCoordinating.MaterializeHandler?

    init(
        interactionState: HomeTimelinePresentationInteractionState,
        restoredTransition: HomeTimelinePresentationTransition
    ) {
        self.interactionState = interactionState
        self.restoredTransition = restoredTransition
    }

    func requestNewestProjectionReload() {
        commands.append(.requestNewestProjectionReload)
    }

    func clearNewestProjectionReload() {
        commands.append(.clearNewestProjectionReload)
    }

    func restoreReadBoundary(
        postID: TimelinePost.ID
    ) -> HomeTimelinePresentationTransition {
        commands.append(.restoreReadBoundary(postID))
        return restoredTransition
    }

    func scheduleMaterialization(
        delayNanoseconds: UInt64?,
        allowsRealtimeFollow: Bool?,
        materialize: @escaping HomeTimelinePresentationCoordinating
            .MaterializeHandler
    ) {
        schedules.append(StorePresentationSchedule(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        ))
        scheduledMaterialize = materialize
    }

    func runScheduledMaterialization(allowsRealtimeFollow: Bool) {
        scheduledMaterialize?(allowsRealtimeFollow)
    }

    #if DEBUG
    func replaceEntriesForTesting(
        _: [TimelineFeedEntry],
        renderFingerprint _: [Int]
    ) -> HomeTimelinePresentationTransition {
        restoredTransition
    }

    func setReadBoundaryForTesting(
        postID _: TimelinePost.ID
    ) -> HomeTimelinePresentationTransition {
        restoredTransition
    }
    #endif
}

@MainActor
struct StorePresentationFixture {
    let account = Self.account(character: "a")
    let replacementAccount = Self.account(character: "b")
    let transition = Self.transition(revision: 7)
    let initialSnapshot: HomeStoreMaterializationSnapshot
    let replacementSnapshot: HomeStoreMaterializationSnapshot
    let events: StorePresentationEventRecorder
    let source: StorePresentationSourceSpy
    let projection = StoreProjectionMaterializingSpy()
    let scheduler: StorePresentationSchedulingSpy
    let coordinator: HomeStorePresentationCoordinator

    init() {
        let initialSnapshot = Self.snapshot(
            account: account,
            resolutionKey: "initial",
            policy: .default(networkType: .cellular)
        )
        let replacementSnapshot = Self.snapshot(
            account: replacementAccount,
            resolutionKey: "replacement",
            policy: .default(networkType: .wifi, lowPowerMode: true)
        )
        let events = StorePresentationEventRecorder()
        let source = StorePresentationSourceSpy(snapshot: initialSnapshot)
        let scheduler = StorePresentationSchedulingSpy(
            interactionState: HomeTimelinePresentationInteractionState(
                hasPendingNewestProjectionReload: true,
                readBoundaryPostID: "boundary",
                defaultDelayNanoseconds: 16
            ),
            restoredTransition: Self.transition(revision: 5)
        )
        source.onApply = { transition in
            events.append(.applied(
                transition.snapshot.resolvedContentRevision
            ))
        }

        self.initialSnapshot = initialSnapshot
        self.replacementSnapshot = replacementSnapshot
        self.events = events
        self.source = source
        self.scheduler = scheduler
        coordinator = HomeStorePresentationCoordinator(
            source: source,
            projection: projection,
            scheduler: scheduler
        )
    }

    private static func account(character: Character) -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: character, count: 64),
            displayIdentifier: "presentation",
            readOnly: true
        )
    }

    private static func snapshot(
        account: NostrAccount,
        resolutionKey: String,
        policy: NostrSyncPolicy
    ) -> HomeStoreMaterializationSnapshot {
        HomeStoreMaterializationSnapshot(
            account: account,
            dependencies: HomeTimelineDependencyResolutionState(
                nip05Resolutions: [
                    resolutionKey: NostrNIP05Resolution(
                        identifier: "user@example.com",
                        pubkey: account.pubkey,
                        relays: [],
                        status: .verified
                    )
                ],
                profileResolutionStates: [
                    resolutionKey: .resolved
                ]
            ),
            policy: policy
        )
    }

    static func transition(
        revision: Int
    ) -> HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: revision,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.resolvedContentRevision],
            didChangeReadState: false
        )
    }
}

@MainActor
final class StorePresentationEventRecorder {
    private(set) var values: [StorePresentationEvent] = []

    func append(_ event: StorePresentationEvent) {
        values.append(event)
    }
}

@MainActor
struct RetainedStorePresentationFixture {
    let source: StorePresentationSourceSpy
    let projection = StoreProjectionMaterializingSpy()
    let scheduler: StorePresentationSchedulingSpy
    let transition = StorePresentationFixture.transition(revision: 9)

    init() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "retained-presentation",
            readOnly: true
        )
        source = StorePresentationSourceSpy(
            snapshot: HomeStoreMaterializationSnapshot(
                account: account,
                dependencies: HomeTimelineDependencyResolutionState(
                    nip05Resolutions: [:],
                    profileResolutionStates: [:]
                ),
                policy: .default()
            )
        )
        scheduler = StorePresentationSchedulingSpy(
            interactionState: HomeTimelinePresentationInteractionState(
                hasPendingNewestProjectionReload: false,
                readBoundaryPostID: nil,
                defaultDelayNanoseconds: 16
            ),
            restoredTransition: transition
        )
    }

    func makeCoordinator() -> HomeStorePresentationCoordinator {
        HomeStorePresentationCoordinator(
            source: source,
            projection: projection,
            scheduler: scheduler
        )
    }
}
