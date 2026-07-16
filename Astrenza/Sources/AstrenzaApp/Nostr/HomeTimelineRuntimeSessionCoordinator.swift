import AstrenzaCore

@MainActor
protocol HomeTimelineRuntimeEventPumping: AnyObject {
    func start(
        stream: @escaping HomeTimelineRuntimeEventPump.StreamProvider,
        isSourceCurrent: @escaping HomeTimelineRuntimeEventPump.SourceValidity,
        onPacket: @escaping HomeTimelineRuntimeEventPump.PacketHandler
    ) -> Bool

    func cancel()
}

extension HomeTimelineRuntimeEventPump: HomeTimelineRuntimeEventPumping {}

@MainActor
protocol HomeTimelineProfileUpdateObserving: AnyObject {
    func startProfileUpdates(
        relayURLs: [String],
        onUpdate: @escaping HomeTimelineDependencyResolutionCoordinator.ProfileUpdateHandler
    ) -> Bool

    func stopProfileUpdates() async
}

extension HomeTimelineDependencyResolutionCoordinator: HomeTimelineProfileUpdateObserving {}

@MainActor
protocol HomeTimelineProfileUpdateApplying: AnyObject {
    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        effects: HomeTimelineRuntimeApplicationEffects
    ) -> NostrEvent

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    )
}

struct HomeTimelineRuntimeSessionRequest: Equatable, Sendable {
    let account: NostrAccount?
    let profileRelayURLs: [String]
    let hasRelayRuntime: Bool
    let isTerminating: Bool
}

struct HomeTimelineRuntimeSessionStart: Equatable, Sendable {
    let didStartProfileUpdates: Bool
    let didStartRuntimeEvents: Bool

    static let inactive = HomeTimelineRuntimeSessionStart(
        didStartProfileUpdates: false,
        didStartRuntimeEvents: false
    )
}

enum HomeTimelineRuntimeSessionCommand: Equatable, Sendable {
    case profileMetadataChanged
    case profileDirectoryChanged
}

struct HomeTimelineRuntimeSessionHandlers: Sendable {
    typealias AccountValidity = @MainActor @Sendable (_ accountID: String) -> Bool
    typealias PacketHandler = @MainActor @Sendable (
        _ packets: [NostrRelayRuntimePacket]
    ) async -> Void
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineRuntimeSessionCommand
    ) -> Void

    let isAccountCurrent: AccountValidity
    let handlePacket: PacketHandler
    let applicationEffects: HomeTimelineRuntimeApplicationEffects
    let perform: CommandHandler
}

@MainActor
final class HomeTimelineRuntimeSessionCoordinator {
    typealias RuntimeStream = @MainActor @Sendable () async -> AsyncStream<NostrRelayRuntimePacket>

    private let runtimeEventPump: any HomeTimelineRuntimeEventPumping
    private let runtimeStream: RuntimeStream?
    private let profileUpdateObserver: any HomeTimelineProfileUpdateObserving
    private let profileUpdateApplication: any HomeTimelineProfileUpdateApplying
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator

    init(
        runtimeEventPump: any HomeTimelineRuntimeEventPumping,
        runtimeStream: RuntimeStream?,
        profileUpdateObserver: any HomeTimelineProfileUpdateObserving,
        profileUpdateApplication: any HomeTimelineProfileUpdateApplying,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    ) {
        self.runtimeEventPump = runtimeEventPump
        self.runtimeStream = runtimeStream
        self.profileUpdateObserver = profileUpdateObserver
        self.profileUpdateApplication = profileUpdateApplication
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    @discardableResult
    func start(
        _ request: HomeTimelineRuntimeSessionRequest,
        handlers: HomeTimelineRuntimeSessionHandlers
    ) -> HomeTimelineRuntimeSessionStart {
        guard !request.isTerminating,
              let account = request.account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return .inactive }

        let didStartProfileUpdates = profileUpdateObserver.startProfileUpdates(
            relayURLs: request.profileRelayURLs
        ) { [weak self] update in
            self?.applyProfileUpdate(
                update,
                request: request,
                account: account,
                lifecycle: lifecycle,
                handlers: handlers
            )
        }

        let didStartRuntimeEvents: Bool
        if request.hasRelayRuntime, let runtimeStream {
            didStartRuntimeEvents = runtimeEventPump.start(
                stream: runtimeStream,
                isSourceCurrent: { [weak self] in
                    self?.lifecycleCoordinator.isCurrent(lifecycle) == true &&
                        handlers.isAccountCurrent(account.pubkey)
                },
                onPacket: handlers.handlePacket
            )
        } else {
            didStartRuntimeEvents = false
        }

        return HomeTimelineRuntimeSessionStart(
            didStartProfileUpdates: didStartProfileUpdates,
            didStartRuntimeEvents: didStartRuntimeEvents
        )
    }

    func cancelRuntimeEvents() {
        runtimeEventPump.cancel()
    }

    func stopProfileUpdates() async {
        await profileUpdateObserver.stopProfileUpdates()
    }

    private func applyProfileUpdate(
        _ update: NostrProfileDirectoryUpdate,
        request: HomeTimelineRuntimeSessionRequest,
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        handlers: HomeTimelineRuntimeSessionHandlers
    ) {
        guard lifecycleCoordinator.isCurrent(lifecycle),
              handlers.isAccountCurrent(account.pubkey)
        else { return }

        let context = HomeTimelineRuntimeEventApplicationContext(
            account: account,
            lifecycle: lifecycle,
            hasRelayRuntime: request.hasRelayRuntime
        )
        for event in update.metadataEvents {
            let effectiveEvent = profileUpdateApplication.rememberLatestMetadataEvent(
                event,
                consultEventStore: false,
                effects: handlers.applicationEffects
            )
            profileUpdateApplication.resolveNIP05IfNeeded(
                for: effectiveEvent,
                context: context,
                effects: handlers.applicationEffects
            )
        }
        if !update.metadataEvents.isEmpty {
            handlers.perform(.profileMetadataChanged)
        }
        if !update.states.isEmpty || !update.metadataEvents.isEmpty {
            handlers.perform(.profileDirectoryChanged)
        }
    }
}
