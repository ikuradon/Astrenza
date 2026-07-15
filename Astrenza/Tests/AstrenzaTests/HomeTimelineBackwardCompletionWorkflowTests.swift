import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline backward completion workflow")
@MainActor
struct HomeBackwardCompletionWorkflowTests {
    @Test("Backward commands route through one stable effect boundary")
    func routesBackwardCommands() throws {
        let account = backwardCompletionWorkflowAccount()
        let feedContext = try backwardCompletionWorkflowFeedContext(
            accountID: account.pubkey
        )
        let gap = PendingGapBackfill(
            newerPostID: "newer",
            olderPostID: "older",
            direction: .older
        )
        let backwardDiagnostic = HomeTimelineBackwardCompletionDiagnostic(
            relayURL: "wss://backward.example",
            message: "backward failed"
        )
        let completion = backwardCompletionWorkflowCompletion()
        let completionCoordinator = BackwardCompletionWorkflowCoordinatorSpy(
            commands: backwardCompletionWorkflowCommands(
                diagnostic: backwardDiagnostic,
                gap: gap,
                feedContext: feedContext
            )
        )
        let gapReconciliation = BackwardCompletionWorkflowGapSpy()
        let probe = BackwardCompletionWorkflowEffectProbe()
        let workflow = HomeTimelineBackwardCompletionWorkflow(
            completionCoordinator: completionCoordinator,
            gapReconciliation: gapReconciliation
        )

        workflow.handle(
            HomeTimelineBackwardCompletionInput(
                completion: completion,
                account: account
            ),
            effects: probe.effects
        )

        let completionCall = try #require(completionCoordinator.calls.first)
        #expect(completionCall.completion == completion)
        #expect(completionCall.accountID == account.pubkey)
        let gapStart = try #require(gapReconciliation.starts.first)
        #expect(gapStart.gap == gap)
        #expect(gapStart.feedContext == feedContext)
        #expect(gapStart.account == account)
        #expect(probe.receivedEffects == backwardCompletionWorkflowEffects(
            account: account,
            diagnostic: backwardDiagnostic
        ))
    }

    @Test("Gap commands preserve diagnostics, anchor reload, and activity revisions")
    func routesGapCommands() throws {
        let account = backwardCompletionWorkflowAccount()
        let feedContext = try backwardCompletionWorkflowFeedContext(
            accountID: account.pubkey
        )
        let gap = PendingGapBackfill(
            newerPostID: "newer",
            olderPostID: "older",
            direction: .older
        )
        let diagnostic = HomeTimelineGapReconciliationDiagnostic(
            relayURL: "wss://gap.example",
            subscriptionID: "astrenza-gap",
            message: "gap failed"
        )
        let completionCoordinator = BackwardCompletionWorkflowCoordinatorSpy(
            commands: [.reconcileGap(gap: gap, context: feedContext)]
        )
        let gapReconciliation = BackwardCompletionWorkflowGapSpy(commands: [
            .incrementRelayStatusRevision,
            .recordDiagnostic(diagnostic),
            .reloadProjection(anchorEventID: gap.stableAnchorPostID)
        ])
        let probe = BackwardCompletionWorkflowEffectProbe()
        let workflow = HomeTimelineBackwardCompletionWorkflow(
            completionCoordinator: completionCoordinator,
            gapReconciliation: gapReconciliation
        )

        workflow.handle(
            HomeTimelineBackwardCompletionInput(
                completion: backwardCompletionWorkflowCompletion(),
                account: account
            ),
            effects: probe.effects
        )

        #expect(probe.receivedEffects == gapReconciliationWorkflowEffects(
            account: account,
            gap: gap,
            diagnostic: diagnostic
        ))
    }

    @Test("Gap dependency resolution and cancellation preserve their boundaries")
    func delegatesGapDependenciesAndCancellation() async throws {
        let account = backwardCompletionWorkflowAccount()
        let feedContext = try backwardCompletionWorkflowFeedContext(
            accountID: account.pubkey
        )
        let gap = PendingGapBackfill(
            newerPostID: "newer",
            olderPostID: "older",
            direction: .older
        )
        let completionCoordinator = BackwardCompletionWorkflowCoordinatorSpy(
            commands: [.reconcileGap(gap: gap, context: feedContext)]
        )
        let gapReconciliation = BackwardCompletionWorkflowGapSpy()
        let probe = BackwardCompletionWorkflowEffectProbe()
        probe.dependencyResult = false
        let workflow = HomeTimelineBackwardCompletionWorkflow(
            completionCoordinator: completionCoordinator,
            gapReconciliation: gapReconciliation
        )
        workflow.handle(
            HomeTimelineBackwardCompletionInput(
                completion: backwardCompletionWorkflowCompletion(),
                account: account
            ),
            effects: probe.effects
        )
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let token = lifecycle.begin(accountID: account.pubkey)
        let dependencyContext = HomeTimelineGapReconciliationApplicationContext(
            account: account,
            lifecycle: token,
            feedContext: feedContext
        )
        let recoveredEvent = backwardCompletionWorkflowEvent()
        let handlers = try #require(gapReconciliation.handlers)

        let resolved = await handlers.resolveDependencies(
            recoveredEvent,
            dependencyContext
        )
        workflow.cancel()

        #expect(!resolved)
        #expect(probe.dependencyEvents == [recoveredEvent])
        let receivedContext = try #require(probe.dependencyContexts.first)
        #expect(receivedContext.account == account)
        #expect(receivedContext.lifecycle == token)
        #expect(receivedContext.feedContext == feedContext)
        #expect(gapReconciliation.cancelCount == 1)
    }

    @Test("Account-bound work is ignored when completion has no current account")
    func ignoresAccountBoundCommandsWithoutAccount() throws {
        let feedContext = try backwardCompletionWorkflowFeedContext(
            accountID: String(repeating: "a", count: 64)
        )
        let gap = PendingGapBackfill(
            newerPostID: "newer",
            olderPostID: "older",
            direction: .newer
        )
        let completionCoordinator = BackwardCompletionWorkflowCoordinatorSpy(
            commands: [
                .reloadProjection(
                    anchorEventID: "anchor",
                    mergingWithCurrentWindow: true
                ),
                .reconcileGap(gap: gap, context: feedContext),
                .applyContentSnapshot(.initial),
                .incrementRelayStatusRevision
            ]
        )
        let gapReconciliation = BackwardCompletionWorkflowGapSpy()
        let probe = BackwardCompletionWorkflowEffectProbe()
        let workflow = HomeTimelineBackwardCompletionWorkflow(
            completionCoordinator: completionCoordinator,
            gapReconciliation: gapReconciliation
        )

        workflow.handle(
            HomeTimelineBackwardCompletionInput(
                completion: backwardCompletionWorkflowCompletion(),
                account: nil
            ),
            effects: probe.effects
        )

        #expect(completionCoordinator.calls.first?.accountID == nil)
        #expect(gapReconciliation.starts.isEmpty)
        #expect(probe.receivedEffects == [
            .applyContentSnapshot(.initial),
            .incrementRelayStatusRevision
        ])
    }
}
