import AstrenzaCore

@MainActor
protocol HomeTimelineRuntimeEventCoordinating: AnyObject {
    func handle(
        _ request: HomeTimelineRuntimeEventRequest,
        handlers: HomeTimelineRuntimeEventHandlers
    ) async

    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) -> NostrEvent

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    )

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> Bool
}

extension HomeTimelineRuntimeEventCoordinator: HomeTimelineRuntimeEventCoordinating {}

struct HomeTimelineRuntimeEventInput: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let event: NostrEvent
    let account: NostrAccount?
    let hasRelayRuntime: Bool
    let receivedWhileRealtime: Bool
}

struct HomeTimelineRuntimeApplicationEffects: Sendable {
    typealias ListRevisionHandler = @MainActor @Sendable (_ revision: Int) -> Void
    typealias PendingCountHandler = @MainActor @Sendable (_ count: Int) -> Void
    typealias ProjectionReloader = @MainActor @Sendable (
        _ anchorEventID: String?,
        _ materialization: HomeTimelineRuntimeEventApplicationPlan.DeletionMaterialization
    ) -> Void
    typealias NewestProjectionReloader = @MainActor @Sendable (
        _ allowsRealtimeFollow: Bool
    ) -> Void
    typealias MaterializationScheduler = @MainActor @Sendable (
        _ schedule: HomeTimelineRuntimeEventApplicationPlan.MaterializationSchedule
    ) -> Void
    typealias MetadataPersistence = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void
    typealias SourceInstallFailure = @MainActor @Sendable (_ message: String) -> Void

    let listRevisionChanged: ListRevisionHandler
    let pendingCountChanged: PendingCountHandler
    let reloadProjection: ProjectionReloader
    let reloadNewestProjection: NewestProjectionReloader
    let scheduleMaterialization: MaterializationScheduler
    let persistTimelineMetadata: MetadataPersistence
    let sourceInstallFailed: SourceInstallFailure
}

struct HomeTimelineRuntimeEventEffects: Sendable {
    typealias PresentationStateProvider = @MainActor @Sendable (
        _ receivedWhileRealtime: Bool
    ) -> HomeTimelineRuntimeEventPresentationState
    typealias AccountValidity = @MainActor @Sendable (_ accountID: String) -> Bool
    typealias DiagnosticHandler = @MainActor @Sendable (
        _ diagnostic: HomeTimelineRuntimeEventDiagnostic
    ) -> Void
    typealias LinkPreviewScheduler = @MainActor @Sendable () -> Void

    let presentationState: PresentationStateProvider
    let isAccountCurrent: AccountValidity
    let application: HomeTimelineRuntimeApplicationEffects
    let recordDiagnostic: DiagnosticHandler
    let scheduleLinkPreviewResolution: LinkPreviewScheduler
}

@MainActor
final class HomeTimelineRuntimeEventWorkflow {
    private let coordinator: any HomeTimelineRuntimeEventCoordinating

    init(coordinator: any HomeTimelineRuntimeEventCoordinating) {
        self.coordinator = coordinator
    }

    func handle(
        _ input: HomeTimelineRuntimeEventInput,
        effects: HomeTimelineRuntimeEventEffects
    ) async {
        await coordinator.handle(
            HomeTimelineRuntimeEventRequest(
                relayURL: input.relayURL,
                subscriptionID: input.subscriptionID,
                event: input.event,
                account: input.account,
                hasRelayRuntime: input.hasRelayRuntime,
                receivedWhileRealtime: input.receivedWhileRealtime
            ),
            handlers: eventHandlers(effects: effects)
        )
    }

    @discardableResult
    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true,
        effects: HomeTimelineRuntimeApplicationEffects
    ) -> NostrEvent {
        coordinator.rememberLatestMetadataEvent(
            event,
            consultEventStore: consultEventStore,
            handlers: applicationHandlers(effects: effects)
        )
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    ) {
        coordinator.resolveNIP05IfNeeded(
            for: metadataEvent,
            context: context,
            handlers: applicationHandlers(effects: effects)
        )
    }

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        await coordinator.enqueueDependencies(
            for: event,
            context: context,
            handlers: applicationHandlers(effects: effects)
        )
    }

    private func eventHandlers(
        effects: HomeTimelineRuntimeEventEffects
    ) -> HomeTimelineRuntimeEventHandlers {
        HomeTimelineRuntimeEventHandlers(
            presentationState: effects.presentationState,
            isAccountCurrent: effects.isAccountCurrent,
            application: applicationHandlers(effects: effects.application),
            perform: { [weak self] command in
                self?.apply(command, effects: effects)
            }
        )
    }

    private func applicationHandlers(
        effects: HomeTimelineRuntimeApplicationEffects
    ) -> HomeTimelineRuntimeEventApplicationHandlers {
        HomeTimelineRuntimeEventApplicationHandlers(
            listRevisionChanged: effects.listRevisionChanged,
            pendingCountChanged: effects.pendingCountChanged,
            perform: { [weak self] command in
                self?.apply(command, effects: effects)
            },
            persistTimelineMetadata: effects.persistTimelineMetadata,
            sourceInstallFailed: effects.sourceInstallFailed
        )
    }

    private func apply(
        _ command: HomeTimelineRuntimeEventCommand,
        effects: HomeTimelineRuntimeEventEffects
    ) {
        switch command {
        case .recordDiagnostic(let diagnostic):
            effects.recordDiagnostic(diagnostic)
        case .scheduleLinkPreviewResolution:
            effects.scheduleLinkPreviewResolution()
        }
    }

    private func apply(
        _ command: HomeTimelineRuntimeEventApplicationCommand,
        effects: HomeTimelineRuntimeApplicationEffects
    ) {
        switch command {
        case .reloadProjection(let anchorEventID, let materialization):
            effects.reloadProjection(anchorEventID, materialization)
        case .requestNewestProjectionReloadAndSchedule(let allowsRealtimeFollow):
            effects.reloadNewestProjection(allowsRealtimeFollow)
        case .scheduleMaterialization(let schedule):
            effects.scheduleMaterialization(schedule)
        }
    }
}

extension HomeTimelineRuntimeEventWorkflow: HomeTimelineProfileUpdateApplying {}
