import AstrenzaCore
import Foundation
@testable import Astrenza

@MainActor
final class BackwardCompletionWorkflowCoordinatorSpy:
    HomeTimelineBackwardCompletionRouting {
    struct Call {
        let completion: NostrBackwardREQCompletion
        let accountID: String?
    }

    let commands: [HomeTimelineBackwardCompletionCommand]
    private(set) var calls: [Call] = []

    init(commands: [HomeTimelineBackwardCompletionCommand]) {
        self.commands = commands
    }

    func handle(
        _ completion: NostrBackwardREQCompletion,
        accountID: String?
    ) -> [HomeTimelineBackwardCompletionCommand] {
        calls.append(Call(completion: completion, accountID: accountID))
        return commands
    }
}

@MainActor
final class BackwardCompletionWorkflowGapSpy:
    HomeTimelineGapReconciliationApplying {
    struct Start {
        let gap: PendingGapBackfill
        let feedContext: HomeFeedRuntimeContext
        let account: NostrAccount
    }

    let commands: [HomeTimelineGapReconciliationApplicationCommand]
    private(set) var starts: [Start] = []
    private(set) var handlers: HomeTimelineGapReconciliationApplicationHandlers?
    private(set) var cancelCount = 0

    init(commands: [HomeTimelineGapReconciliationApplicationCommand] = []) {
        self.commands = commands
    }

    func start(
        _ gap: PendingGapBackfill,
        feedContext: HomeFeedRuntimeContext,
        account: NostrAccount,
        handlers: HomeTimelineGapReconciliationApplicationHandlers
    ) -> Bool {
        starts.append(Start(
            gap: gap,
            feedContext: feedContext,
            account: account
        ))
        self.handlers = handlers
        for command in commands {
            handlers.perform(command)
        }
        return true
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
final class BackwardCompletionWorkflowEffectProbe {
    var dependencyResult = true
    private(set) var receivedEffects: [BackwardCompletionWorkflowEffect] = []
    private(set) var dependencyEvents: [NostrEvent] = []
    private(set) var dependencyContexts: [HomeTimelineGapReconciliationApplicationContext] = []

    var effects: HomeTimelineBackwardCompletionEffects {
        HomeTimelineBackwardCompletionEffects(
            applyContentSnapshot: { [self] snapshot in
                receivedEffects.append(.applyContentSnapshot(snapshot))
            },
            recordDiagnostic: { [self] relayURL, subscriptionID, message in
                receivedEffects.append(.recordDiagnostic(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID,
                    message: message
                ))
            },
            reloadProjection: { [self] account, anchorEventID, mergingWithCurrentWindow in
                receivedEffects.append(.reloadProjection(
                    account: account,
                    anchorEventID: anchorEventID,
                    mergingWithCurrentWindow: mergingWithCurrentWindow
                ))
            },
            incrementRelayStatusRevision: { [self] in
                receivedEffects.append(.incrementRelayStatusRevision)
            },
            resolveDependencies: { [self] event, context in
                dependencyEvents.append(event)
                dependencyContexts.append(context)
                return dependencyResult
            }
        )
    }
}

enum BackwardCompletionWorkflowEffect: Equatable, Sendable {
    case applyContentSnapshot(HomeTimelineContentSnapshot)
    case recordDiagnostic(
        relayURL: String,
        subscriptionID: String?,
        message: String
    )
    case reloadProjection(
        account: NostrAccount,
        anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    )
    case incrementRelayStatusRevision
}

func backwardCompletionWorkflowAccount() -> NostrAccount {
    NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "workflow",
        readOnly: true
    )
}

func backwardCompletionWorkflowFeedContext(
    accountID: String
) throws -> HomeFeedRuntimeContext {
    let specification = try JSONEncoder().encode(
        HomeFeedSpecification(authors: [accountID], kinds: [1, 6])
    )
    return HomeFeedRuntimeContext(definition: NostrFeedDefinitionRecord(
        feedID: "feed:home:\(accountID)",
        accountID: accountID,
        kind: "home",
        specificationJSON: specification,
        specificationHash: "workflow",
        revision: 1,
        createdAt: 1,
        updatedAt: 1
    ))
}

func backwardCompletionWorkflowCompletion() -> NostrBackwardREQCompletion {
    NostrBackwardREQCompletion(
        groupID: "workflow",
        relayURLs: ["wss://relay.example"],
        subscriptionIDs: ["astrenza-workflow"],
        eventCount: 1,
        eoseCount: 1,
        closedCount: 0,
        timeoutCount: 0
    )
}

func backwardCompletionWorkflowEvent() -> NostrEvent {
    NostrEvent(
        id: String(repeating: "1", count: 64),
        pubkey: String(repeating: "a", count: 64),
        createdAt: 100,
        kind: 1,
        tags: [],
        content: "recovered",
        sig: String(repeating: "b", count: 128)
    )
}

func backwardCompletionWorkflowCommands(
    diagnostic: HomeTimelineBackwardCompletionDiagnostic,
    gap: PendingGapBackfill,
    feedContext: HomeFeedRuntimeContext
) -> [HomeTimelineBackwardCompletionCommand] {
    [
        .applyContentSnapshot(.initial),
        .recordDiagnostic(diagnostic),
        .reloadProjection(
            anchorEventID: "anchor",
            mergingWithCurrentWindow: true
        ),
        .reconcileGap(gap: gap, context: feedContext),
        .incrementRelayStatusRevision
    ]
}

func backwardCompletionWorkflowEffects(
    account: NostrAccount,
    diagnostic: HomeTimelineBackwardCompletionDiagnostic
) -> [BackwardCompletionWorkflowEffect] {
    [
        .applyContentSnapshot(.initial),
        .recordDiagnostic(
            relayURL: diagnostic.relayURL,
            subscriptionID: nil,
            message: diagnostic.message
        ),
        .reloadProjection(
            account: account,
            anchorEventID: "anchor",
            mergingWithCurrentWindow: true
        ),
        .incrementRelayStatusRevision
    ]
}

func gapReconciliationWorkflowEffects(
    account: NostrAccount,
    gap: PendingGapBackfill,
    diagnostic: HomeTimelineGapReconciliationDiagnostic
) -> [BackwardCompletionWorkflowEffect] {
    [
        .incrementRelayStatusRevision,
        .recordDiagnostic(
            relayURL: diagnostic.relayURL,
            subscriptionID: diagnostic.subscriptionID,
            message: diagnostic.message
        ),
        .reloadProjection(
            account: account,
            anchorEventID: gap.stableAnchorPostID,
            mergingWithCurrentWindow: false
        )
    ]
}
