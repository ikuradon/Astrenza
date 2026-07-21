import AstrenzaCore
import Foundation
@testable import Astrenza

struct RuntimeEventProcessingCall: Equatable {
    let relayURL: String
    let subscriptionID: String
    let event: NostrEvent
}

@MainActor
final class RuntimeEventProcessorSpy: HomeTimelineRuntimeEventProcessing {
    var outcome: HomeTimelineRuntimeEventProcessingOutcome
    var beforePresentationSample: (() -> Void)?
    private(set) var calls: [RuntimeEventProcessingCall] = []
    private(set) var presentationStates: [HomeTimelineRuntimeEventPresentationState] = []
    private(set) var activeFeedContexts: [HomeFeedRuntimeContext?] = []

    init(outcome: HomeTimelineRuntimeEventProcessingOutcome) {
        self.outcome = outcome
    }

    func process(
        _ request: RuntimeEventProcessingRequest,
        handlers: RuntimeEventProcessingHandlers
    ) async -> HomeTimelineRuntimeEventProcessingOutcome {
        calls.append(RuntimeEventProcessingCall(
            relayURL: request.relayURL,
            subscriptionID: request.subscriptionID,
            event: request.event
        ))
        await handlers.ensureFeedDefinition()
        activeFeedContexts.append(handlers.activeFeedContext())
        beforePresentationSample?()
        presentationStates.append(handlers.forwardPresentationState(
            request.receivedWhileRealtime
        ))
        return outcome
    }
}

@MainActor
final class RuntimeEventApplicationSpy: HomeTimelineRuntimeEventApplying {
    var applyResult: Bool
    var rememberedEvent: NostrEvent?
    var enqueueResult = true
    private(set) var appliedPlans: [HomeTimelineRuntimeEventApplicationPlan] = []
    private(set) var backwardRequestKeys: [String?] = []
    private(set) var applicationContexts: [HomeTimelineRuntimeEventApplicationContext] = []
    private(set) var resolvedMetadataEvents: [NostrEvent] = []
    private(set) var enqueuedEvents: [NostrEvent] = []

    init(applyResult: Bool) {
        self.applyResult = applyResult
    }

    func apply(
        _ plan: HomeTimelineRuntimeEventApplicationPlan,
        backwardRequestKey: String?,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> Bool {
        appliedPlans.append(plan)
        backwardRequestKeys.append(backwardRequestKey)
        applicationContexts.append(context)
        return applyResult
    }

    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) -> NostrEvent {
        rememberedEvent ?? event
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) {
        resolvedMetadataEvents.append(metadataEvent)
    }

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> Bool {
        enqueuedEvents.append(event)
        return enqueueResult
    }
}

struct RuntimeEventFeedRecord: Equatable {
    let event: NostrEvent
    let relayURL: String
    let subscriptionID: String
}

@MainActor
final class RuntimeEventFeedRecorderSpy: HomeTimelineRuntimeFeedEventRecording {
    private(set) var records: [RuntimeEventFeedRecord] = []

    func record(
        _ event: NostrEvent,
        relayURL: String,
        subscriptionID: String
    ) {
        records.append(RuntimeEventFeedRecord(
            event: event,
            relayURL: relayURL,
            subscriptionID: subscriptionID
        ))
    }
}

@MainActor
final class RuntimeEventHandlerProbe {
    var state = HomeTimelineRuntimeEventPresentationState(
        receivedWhileRealtime: false,
        hasRestoreProjectionAnchor: true,
        isTimelineAtNewestWindow: false,
        hasPendingEvents: true
    )
    var isAccountCurrent = true
    private(set) var commands: [HomeTimelineRuntimeEventCommand] = []

    var handlers: HomeTimelineRuntimeEventHandlers {
        HomeTimelineRuntimeEventHandlers(
            presentationState: { [self] receivedWhileRealtime in
                HomeTimelineRuntimeEventPresentationState(
                    receivedWhileRealtime: receivedWhileRealtime,
                    hasRestoreProjectionAnchor: state.hasRestoreProjectionAnchor,
                    isTimelineAtNewestWindow: state.isTimelineAtNewestWindow,
                    hasPendingEvents: state.hasPendingEvents
                )
            },
            isAccountCurrent: { [self] _ in isAccountCurrent },
            application: Self.applicationHandlers,
            perform: { [self] command in commands.append(command) }
        )
    }

    private static var applicationHandlers: HomeTimelineRuntimeEventApplicationHandlers {
        HomeTimelineRuntimeEventApplicationHandlers(
            applyListProjectionInvalidation: { _ in },
            applyPendingEventCountPublication: { _ in },
            perform: { _ in },
            persistTimelineMetadata: { _ in },
            sourceInstallFailed: { _ in }
        )
    }
}

@MainActor
struct RuntimeEventCoordinatorTestSystem {
    let account: NostrAccount
    let followedPubkey: String
    let event: NostrEvent
    let lifecycle: HomeTimelineLifecycleCoordinator
    let lifecycleToken: HomeTimelineLifecycleToken
    let processor: RuntimeEventProcessorSpy
    let application: RuntimeEventApplicationSpy
    let recorder: RuntimeEventFeedRecorderSpy
    let coordinator: HomeTimelineRuntimeEventCoordinator
    let probe = RuntimeEventHandlerProbe()

    init(
        outcome: HomeTimelineRuntimeEventProcessingOutcome,
        applyResult: Bool = true
    ) throws {
        let accountID = String(repeating: "a", count: 64)
        let followedPubkey = String(repeating: "b", count: 64)
        let account = NostrAccount(
            pubkey: accountID,
            displayIdentifier: "account",
            readOnly: true
        )
        let event = Self.event(pubkey: followedPubkey)
        let content = HomeTimelineContentCoordinator(eventStore: nil)
        _ = content.replace(
            with: NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [followedPubkey],
                noteEvents: [event],
                metadataEvents: []
            ),
            accountID: accountID
        )
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let lifecycleToken = lifecycle.begin(accountID: accountID)
        let processor = RuntimeEventProcessorSpy(outcome: outcome)
        let application = RuntimeEventApplicationSpy(applyResult: applyResult)
        let recorder = RuntimeEventFeedRecorderSpy()
        let eventStore = try NostrEventStore.inMemory()
        try eventStore.save(events: [event])

        self.account = account
        self.followedPubkey = followedPubkey
        self.event = event
        self.lifecycle = lifecycle
        self.lifecycleToken = lifecycleToken
        self.processor = processor
        self.application = application
        self.recorder = recorder
        self.coordinator = HomeTimelineRuntimeEventCoordinator(
            processor: processor,
            applicationCoordinator: application,
            contentCoordinator: content,
            projectionController: HomeFeedProjectionController(
                eventStore: eventStore
            ),
            feedEventRecorder: recorder,
            lifecycleCoordinator: lifecycle
        )
    }

    func request(
        account: NostrAccount? = nil,
        hasRelayRuntime: Bool = true,
        receivedWhileRealtime: Bool = true
    ) -> HomeTimelineRuntimeEventRequest {
        HomeTimelineRuntimeEventRequest(
            relayURL: "wss://relay.example",
            subscriptionID: "astrenza-home-forward-test",
            event: event,
            account: account ?? self.account,
            hasRelayRuntime: hasRelayRuntime,
            receivedWhileRealtime: receivedWhileRealtime
        )
    }

    private static func event(pubkey: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "event",
            sig: String(repeating: "0", count: 128)
        )
    }
}
