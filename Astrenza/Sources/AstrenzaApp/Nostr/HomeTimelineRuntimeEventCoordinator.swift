import AstrenzaCore

@MainActor
protocol HomeTimelineRuntimeEventProcessing: AnyObject {
    func process(
        _ request: RuntimeEventProcessingRequest,
        handlers: RuntimeEventProcessingHandlers
    ) async -> HomeTimelineRuntimeEventProcessingOutcome

    func process(
        _ requests: [RuntimeEventProcessingRequest],
        handlers: RuntimeEventProcessingHandlers
    ) async -> [HomeTimelineRuntimeEventProcessingOutcome]
}

extension HomeTimelineRuntimeEventProcessing {
    func process(
        _ requests: [RuntimeEventProcessingRequest],
        handlers: RuntimeEventProcessingHandlers
    ) async -> [HomeTimelineRuntimeEventProcessingOutcome] {
        var outcomes: [HomeTimelineRuntimeEventProcessingOutcome] = []
        outcomes.reserveCapacity(requests.count)
        for request in requests {
            outcomes.append(await process(request, handlers: handlers))
        }
        return outcomes
    }
}

struct RuntimeEventProcessingRequest: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let event: NostrEvent
}

struct RuntimeEventProcessingHandlers: Sendable {
    typealias PresentationStateProvider = @MainActor @Sendable () -> HomeTimelineRuntimeEventPresentationState

    let forwardPresentationState: PresentationStateProvider
    let ensureFeedDefinition: @MainActor @Sendable () async -> Void
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

    func process(
        _ requests: [RuntimeEventProcessingRequest],
        handlers: RuntimeEventProcessingHandlers
    ) async -> [HomeTimelineRuntimeEventProcessingOutcome] {
        await process(
            requests,
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

    func apply(
        _ requests: [HomeTimelineRuntimeEventApplicationRequest],
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> [Bool]

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

extension HomeTimelineRuntimeEventApplying {
    func apply(
        _ requests: [HomeTimelineRuntimeEventApplicationRequest],
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> [Bool] {
        var results: [Bool] = []
        results.reserveCapacity(requests.count)
        for request in requests {
            results.append(await apply(
                request.plan,
                backwardRequestKey: request.backwardRequestKey,
                context: context,
                handlers: handlers
            ))
        }
        return results
    }
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
        await handle([request], handlers: handlers)
    }

    func handle(
        _ requests: [HomeTimelineRuntimeEventRequest],
        handlers: HomeTimelineRuntimeEventHandlers
    ) async {
        guard let first = requests.first,
              let account = first.account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        let currentRequests = requests.filter { $0.account?.pubkey == account.pubkey }
        let outcomes = await process(
            currentRequests,
            account: account,
            handlers: handlers
        )
        var processed: [(HomeTimelineRuntimeEventRequest, HomeTimelineRuntimeEventProcessingResult)] = []

        for (request, outcome) in zip(currentRequests, outcomes) {
            switch outcome {
            case .ignored:
                continue
            case .persistenceFailed(let message):
                handlers.perform(.recordDiagnostic(HomeTimelineRuntimeEventDiagnostic(
                    relayURL: request.relayURL,
                    subscriptionID: request.subscriptionID,
                    message: message
                )))
            case .processed(let result):
                processed.append((request, result))
            }
        }
        guard !processed.isEmpty,
              lifecycleCoordinator.isCurrent(lifecycle),
              handlers.isAccountCurrent(account.pubkey)
        else { return }

        let applied = await applicationCoordinator.apply(
            processed.map { item in
                HomeTimelineRuntimeEventApplicationRequest(
                    plan: item.1.applicationPlan,
                    backwardRequestKey: item.1.backwardRequestKey
                )
            },
            context: HomeTimelineRuntimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle,
                hasRelayRuntime: first.hasRelayRuntime
            ),
            handlers: handlers.application
        )
        var didApplyEvent = false
        for (item, wasApplied) in zip(processed, applied) where wasApplied {
            didApplyEvent = true
            feedEventRecorder.record(
                item.0.event,
                relayURL: item.0.relayURL,
                subscriptionID: item.0.subscriptionID
            )
        }
        if didApplyEvent {
            handlers.perform(.scheduleLinkPreviewResolution)
        }
    }

    private func process(
        _ requests: [HomeTimelineRuntimeEventRequest],
        account: NostrAccount,
        handlers: HomeTimelineRuntimeEventHandlers
    ) async -> [HomeTimelineRuntimeEventProcessingOutcome] {
        await processor.process(
            requests.map { request in
                RuntimeEventProcessingRequest(
                    relayURL: request.relayURL,
                    subscriptionID: request.subscriptionID,
                    event: request.event
                )
            },
            handlers: RuntimeEventProcessingHandlers(
                forwardPresentationState: {
                    handlers.presentationState(
                        requests.first?.receivedWhileRealtime ?? false
                    )
                },
                ensureFeedDefinition: { [weak self] in
                    await self?.ensureFeedDefinition(accountID: account.pubkey)
                },
                activeFeedContext: { [weak self] in
                    self?.projectionController.runtimeContext()
                }
            )
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

    private func ensureFeedDefinition(accountID: String) async {
        let content = contentCoordinator.snapshot
        await projectionController.ensureDefinition(
            accountID: accountID,
            followedPubkeys: content.followedPubkeys,
            liveEvents: content.noteEvents
        )
    }
}
