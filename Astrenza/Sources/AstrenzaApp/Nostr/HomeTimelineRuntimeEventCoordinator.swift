import AstrenzaCore

@MainActor
protocol HomeTimelineRuntimeEventProcessing: AnyObject {
    func process(
        _ request: RuntimeEventProcessingRequest,
        handlers: RuntimeEventProcessingHandlers
    ) async -> HomeTimelineRuntimeEventProcessingOutcome
}

struct RuntimeEventProcessingRequest: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let event: NostrEvent
}

struct RuntimeEventProcessingHandlers: Sendable {
    typealias PresentationStateProvider = @MainActor @Sendable () -> HomeTimelineRuntimeEventPresentationState

    let forwardPresentationState: PresentationStateProvider
    let ensureFeedDefinition: @MainActor @Sendable () -> Void
    let activeFeedContext: @MainActor @Sendable () -> HomeFeedRuntimeContext?
}

extension HomeTimelineRuntimeEventProcessor: HomeTimelineRuntimeEventProcessing {
    func process(
        _ request: RuntimeEventProcessingRequest,
        handlers: RuntimeEventProcessingHandlers
    ) async -> HomeTimelineRuntimeEventProcessingOutcome {
        await process(
            relayURL: request.relayURL,
            subscriptionID: request.subscriptionID,
            event: request.event,
            forwardPresentationState: handlers.forwardPresentationState,
            ensureFeedDefinition: handlers.ensureFeedDefinition,
            activeFeedContext: handlers.activeFeedContext
        )
    }
}

@MainActor
protocol HomeTimelineRuntimeEventApplying: AnyObject {
    func apply(
        _ plan: HomeTimelineRuntimeEventApplicationPlan,
        backwardRequestKey: String?,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> Bool

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

extension HomeTimelineRuntimeEventApplicationCoordinator: HomeTimelineRuntimeEventApplying {}

@MainActor
protocol HomeTimelineRuntimeFeedEventRecording: AnyObject {
    func record(
        _ event: NostrEvent,
        relayURL: String,
        subscriptionID: String
    )
}

extension HomeTimelineFeedSyncCoordinator: HomeTimelineRuntimeFeedEventRecording {}

struct HomeTimelineRuntimeEventRequest: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let event: NostrEvent
    let account: NostrAccount?
    let hasRelayRuntime: Bool
    let receivedWhileRealtime: Bool
}

struct HomeTimelineRuntimeEventDiagnostic: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let message: String
}

enum HomeTimelineRuntimeEventCommand: Equatable, Sendable {
    case recordDiagnostic(HomeTimelineRuntimeEventDiagnostic)
    case scheduleLinkPreviewResolution
}

struct HomeTimelineRuntimeEventHandlers: Sendable {
    typealias PresentationStateProvider = @MainActor @Sendable (
        _ receivedWhileRealtime: Bool
    ) -> HomeTimelineRuntimeEventPresentationState
    typealias AccountValidity = @MainActor @Sendable (_ accountID: String) -> Bool
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineRuntimeEventCommand
    ) -> Void

    let presentationState: PresentationStateProvider
    let isAccountCurrent: AccountValidity
    let application: HomeTimelineRuntimeEventApplicationHandlers
    let perform: CommandHandler
}

@MainActor
final class HomeTimelineRuntimeEventCoordinator {
    private let processor: any HomeTimelineRuntimeEventProcessing
    private let applicationCoordinator: any HomeTimelineRuntimeEventApplying
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let projectionController: HomeFeedProjectionController
    private let feedEventRecorder: any HomeTimelineRuntimeFeedEventRecording
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator

    init(
        processor: any HomeTimelineRuntimeEventProcessing,
        applicationCoordinator: any HomeTimelineRuntimeEventApplying,
        contentCoordinator: HomeTimelineContentCoordinator,
        projectionController: HomeFeedProjectionController,
        feedEventRecorder: any HomeTimelineRuntimeFeedEventRecording,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    ) {
        self.processor = processor
        self.applicationCoordinator = applicationCoordinator
        self.contentCoordinator = contentCoordinator
        self.projectionController = projectionController
        self.feedEventRecorder = feedEventRecorder
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    func handle(
        _ request: HomeTimelineRuntimeEventRequest,
        handlers: HomeTimelineRuntimeEventHandlers
    ) async {
        guard let account = request.account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }

        let outcome = await process(request, account: account, handlers: handlers)

        switch outcome {
        case .ignored:
            return
        case .persistenceFailed(let message):
            handlers.perform(.recordDiagnostic(HomeTimelineRuntimeEventDiagnostic(
                relayURL: request.relayURL,
                subscriptionID: request.subscriptionID,
                message: message
            )))
        case .processed(let result):
            await apply(
                result,
                request: request,
                account: account,
                lifecycle: lifecycle,
                handlers: handlers
            )
        }
    }

    private func process(
        _ request: HomeTimelineRuntimeEventRequest,
        account: NostrAccount,
        handlers: HomeTimelineRuntimeEventHandlers
    ) async -> HomeTimelineRuntimeEventProcessingOutcome {
        await processor.process(
            RuntimeEventProcessingRequest(
                relayURL: request.relayURL,
                subscriptionID: request.subscriptionID,
                event: request.event
            ),
            handlers: RuntimeEventProcessingHandlers(
                forwardPresentationState: {
                    handlers.presentationState(request.receivedWhileRealtime)
                },
                ensureFeedDefinition: { [weak self] in
                    self?.ensureFeedDefinition(accountID: account.pubkey)
                },
                activeFeedContext: { [weak self] in
                    self?.projectionController.runtimeContext()
                }
            )
        )
    }

    private func apply(
        _ result: HomeTimelineRuntimeEventProcessingResult,
        request: HomeTimelineRuntimeEventRequest,
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        handlers: HomeTimelineRuntimeEventHandlers
    ) async {
        guard lifecycleCoordinator.isCurrent(lifecycle),
              handlers.isAccountCurrent(account.pubkey)
        else { return }
        let applied = await applicationCoordinator.apply(
            result.applicationPlan,
            backwardRequestKey: result.backwardRequestKey,
            context: HomeTimelineRuntimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle,
                hasRelayRuntime: request.hasRelayRuntime
            ),
            handlers: handlers.application
        )
        guard applied else { return }
        handlers.perform(.scheduleLinkPreviewResolution)
        feedEventRecorder.record(
            request.event,
            relayURL: request.relayURL,
            subscriptionID: request.subscriptionID
        )
    }

    @discardableResult
    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) -> NostrEvent {
        applicationCoordinator.rememberLatestMetadataEvent(
            event,
            consultEventStore: consultEventStore,
            handlers: handlers
        )
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) {
        applicationCoordinator.resolveNIP05IfNeeded(
            for: metadataEvent,
            context: context,
            handlers: handlers
        )
    }

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> Bool {
        await applicationCoordinator.enqueueDependencies(
            for: event,
            context: context,
            handlers: handlers
        )
    }

    private func ensureFeedDefinition(accountID: String) {
        let content = contentCoordinator.snapshot
        projectionController.ensureDefinition(
            accountID: accountID,
            followedPubkeys: content.followedPubkeys,
            liveEvents: content.noteEvents
        )
    }
}
