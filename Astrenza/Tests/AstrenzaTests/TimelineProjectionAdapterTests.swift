import DesignSystem
import Foundation
import Testing
@testable import Astrenza

@Suite("Timeline projection adapter")
struct TimelineProjectionAdapterTests {
    private let adapter = FixtureBackedTimelineProjectionAdapter()
    private let scenarios = TimelineProjectionFixtureBuilder.allScenarios

    @Test("Every Phase 6.0 fixture is accepted by the fixture backed adapter")
    func everyPhase60FixtureIsAcceptedByFixtureBackedAdapter() throws {
        var acceptedCount = 0

        for scenario in scenarios {
            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))

            #expect(output.issues.isEmpty, "Unexpected adapter issues for \(scenario.name): \(output.issues)")
            #expect(output.scenarioName == scenario.name)
            #expect(output.entryID == scenario.expectedOutput.identity.entryID)
            #expect(output.itemKey == scenario.expectedOutput.identity.itemKey)
            #expect(output.sourceEventID == scenario.expectedOutput.identity.sourceEventID)
            #expect(output.subjectEventID == scenario.expectedOutput.identity.subjectEventID)
            #expect(output.sortAt == scenario.expectedOutput.identity.sortAt)
            #expect(output.tieBreakID == scenario.expectedOutput.identity.tieBreakID)
            #expect(output.resolveExpectations == scenario.expectedOutput.resolveExpectations)
            #expect(output.diagnostics.validatedByContractValidator)
            acceptedCount += 1
        }

        #expect(acceptedCount == TimelineProjectionFixtureBuilder.allScenarios.count)
    }

    @Test("Adapter output preserves source event and subject event distinction")
    func adapterOutputPreservesSourceEventAndSubjectEventDistinction() throws {
        let scenario = try fixture(named: "repost_target_pending_to_resolved")
        let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))

        let sourceEventID = try #require(output.sourceEventID)
        let subjectEventID = try #require(output.subjectEventID)

        #expect(sourceEventID == scenario.expectedOutput.identity.sourceEventID)
        #expect(subjectEventID == scenario.expectedOutput.identity.subjectEventID)
        #expect(sourceEventID != subjectEventID)
    }

    @Test("Delayed resolve transitions produce reconfigure mutation without delete or insert")
    func delayedResolveTransitionsProduceReconfigureMutationWithoutDeleteOrInsert() throws {
        for scenario in scenarios where scenario.hasDelayedResolveTransition {
            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
            let mutation = try #require(output.mutationExpectation)

            #expect(mutation.style == .reconfigure, "Unexpected mutation style for \(scenario.name)")
            #expect(mutation.initialEntryID == scenario.expectedOutput.mutation.initialEntryID)
            #expect(mutation.finalEntryID == scenario.expectedOutput.mutation.finalEntryID)
            #expect(mutation.insertedIDs.isEmpty)
            #expect(mutation.deletedIDs.isEmpty)
            #expect(!mutation.allowsDeleteInsertForDelayedResolve)
            #expect(!mutation.readMarkerChanged)
        }
    }

    @Test("Resolve enrichment targets never produce delete or insert mutation")
    func resolveEnrichmentTargetsNeverProduceDeleteOrInsertMutation() throws {
        let enrichmentTargets: Set<TimelineDelayedResolveTarget> = [
            .profile,
            .bodyMention,
            .media,
            .linkPreviewOGP,
            .repostTarget,
            .quoteTarget,
            .replyParentRoot,
            .stats,
            .publishStatePlaceholder
        ]

        for scenario in scenarios {
            let touchesEnrichmentTarget = scenario.expectedOutput.resolveExpectations.contains { expectation in
                enrichmentTargets.contains(expectation.target)
            }
            guard touchesEnrichmentTarget else {
                continue
            }

            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
            let mutation = try #require(output.mutationExpectation)

            #expect(mutation.style == .reconfigure, "Unexpected mutation style for \(scenario.name)")
            #expect(mutation.insertedIDs.isEmpty)
            #expect(mutation.deletedIDs.isEmpty)
        }
    }

    @Test("Failed or blocked resolve returns fallback while keeping source note visible")
    func failedOrBlockedResolveReturnsFallbackWhileKeepingSourceNoteVisible() throws {
        for scenario in scenarios where scenario.expectedOutput.resolveExpectations.contains(where: \.requiresFallback) {
            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
            let fallback = try #require(output.fallback)
            let visibility = try #require(output.visibilityDecision)

            #expect(fallback.keepsSourceNoteVisible)
            #expect(visibility.removesSourceNote == false)
            #expect(visibility.fallbackMode == scenario.expectedOutput.fallback.mode)
        }
    }

    @Test("Quote target and reply parent boundaries remain distinct")
    func quoteTargetAndReplyParentBoundariesRemainDistinct() throws {
        let quote = adapter.project(TimelineProjectionAdapterInput(
            scenario: try fixture(named: "quote_target_must_not_create_reply_relation")
        ))
        let quoteMutation = try #require(quote.mutationExpectation)
        let quoteLayout = try #require(quote.layoutDecision)

        #expect(!quoteMutation.quoteCreatesReplyRelation)
        #expect(quoteLayout.contract.quoteMode == .collapsedCard)
        #expect(quoteLayout.contract.replyHeaderMode == .absent)

        let reply = adapter.project(TimelineProjectionAdapterInput(
            scenario: try fixture(named: "reply_parent_pending_to_resolved_headerOnly")
        ))
        let replyLayout = try #require(reply.layoutDecision)

        #expect(replyLayout.contract.rowKind == .home)
        #expect(replyLayout.contract.replyHeaderMode == .oneLine)
        #expect(!replyLayout.contract.allowsInlineParentPreviewInHome)
    }

    @Test("Pending new stays hidden until explicit user action")
    func pendingNewStaysHiddenUntilExplicitUserAction() throws {
        let scenario = try fixture(named: "pending_new_not_visible_until_user_action")
        let entryID = scenario.expectedOutput.identity.entryID

        let blocked = adapter.project(TimelineProjectionAdapterInput(
            scenario: scenario,
            currentVisibleEntryIDs: [],
            pendingNewEntryIDs: [entryID],
            userActionAllowsPendingNewInsertion: false
        ))
        let blockedVisibility = try #require(blocked.visibilityDecision)
        let blockedMutation = try #require(blocked.mutationExpectation)

        #expect(!blockedVisibility.includedInVisibleSnapshot)
        #expect(!blockedVisibility.pendingNewVisible)
        #expect(blockedMutation.style == .none)
        #expect(!blocked.diagnostics.pendingNewVisible)

        let allowed = adapter.project(TimelineProjectionAdapterInput(
            scenario: scenario,
            currentVisibleEntryIDs: [],
            pendingNewEntryIDs: [entryID],
            userActionAllowsPendingNewInsertion: true
        ))
        let allowedVisibility = try #require(allowed.visibilityDecision)
        let allowedMutation = try #require(allowed.mutationExpectation)

        #expect(allowedVisibility.includedInVisibleSnapshot)
        #expect(allowedVisibility.pendingNewVisible)
        #expect(allowedMutation.style == .insertOnlyForExplicitUserPendingNewAction)
        #expect(allowedMutation.insertedIDs == [entryID])
        #expect(allowed.diagnostics.pendingNewVisible)
    }

    @Test("Publish state placeholder requires no remote work")
    func publishStatePlaceholderRequiresNoRemoteWork() throws {
        let output = adapter.project(TimelineProjectionAdapterInput(
            scenario: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange")
        ))

        #expect(output.resolveExpectations.allSatisfy { expectation in
            expectation.target == .publishStatePlaceholder && !expectation.requiresRemoteWork
        })
        #expect(!output.diagnostics.requiresNetworkWork)
        #expect(!output.diagnostics.requiresDBWork)
    }

    @Test("Adapter diagnostics keep read marker network and database work disabled")
    func adapterDiagnosticsKeepReadMarkerNetworkAndDatabaseWorkDisabled() {
        for scenario in scenarios {
            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))

            #expect(!output.diagnostics.readMarkerChanged)
            #expect(!output.diagnostics.requiresNetworkWork)
            #expect(!output.diagnostics.requiresDBWork)
        }
    }

    @Test("Adapter uses validator and rejects invalid contract scenarios")
    func adapterUsesValidatorAndRejectsInvalidContractScenarios() throws {
        var unstableIdentity = try fixture(named: "ogp_pending_to_resolved")
        unstableIdentity.expectedOutput.identity.itemKey += ":resolved"
        unstableIdentity.expectedOutput.mutation.finalEntryID = unstableIdentity.expectedOutput.identity.entryID
        expectContractIssue(.unstableIdentity, in: unstableIdentity)

        var readMarkerChanged = try fixture(named: "profile_missing_to_resolved_headerOnly")
        readMarkerChanged.expectedOutput.mutation.readMarkerChanged = true
        expectContractIssue(.readMarkerMustNotChange, in: readMarkerChanged)

        var pendingNewViolation = try fixture(named: "pending_new_not_visible_until_user_action")
        pendingNewViolation.expectedOutput.visibility.includedInVisibleSnapshot = true
        pendingNewViolation.expectedOutput.mutation.pendingNewInsertedIntoVisibleSnapshot = true
        expectContractIssue(.pendingNewMustWaitForUserAction, in: pendingNewViolation)
    }

    @Test("Adapter covers every delayed resolve target and resolve state")
    func adapterCoversEveryDelayedResolveTargetAndResolveState() {
        let outputs = scenarios.map { scenario in
            adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
        }
        let targets = Set(outputs.flatMap { output in
            output.resolveExpectations.map(\.target)
        })
        let states = Set(outputs.flatMap { output in
            output.resolveExpectations.flatMap { expectation in
                [expectation.initialState, expectation.expectedState]
            }
        })

        #expect(targets.isSuperset(of: Set(TimelineDelayedResolveTarget.allCases)))
        #expect(states.isSuperset(of: Set(TimelineProjectionResolveState.allCases)))
    }

    @Test("Adapter models are codable equatable and sendable")
    func adapterModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineProjectionAdapterInput.self)
        assertSendable(TimelineProjectionAdapterOutput.self)
        assertSendable(TimelineProjectionAdapterIssue.self)
        assertSendable(TimelineProjectionAdapterDiagnostics.self)
        assertSendable(TimelineProjectionMutationExpectation.self)
        assertSendable(TimelineProjectionLayoutDecision.self)
        assertSendable(TimelineProjectionVisibilityDecision.self)

        let input = TimelineProjectionAdapterInput(
            scenario: try fixture(named: "ogp_pending_to_resolved"),
            surface: .home,
            currentVisibleEntryIDs: [TimelineEntryID(rawValue: "home:visible")],
            pendingNewEntryIDs: [],
            userActionAllowsPendingNewInsertion: false
        )
        let output = adapter.project(input)

        try assertCodableRoundTrip(input)
        try assertCodableRoundTrip(output)
        try assertCodableRoundTrip(try #require(output.mutationExpectation))
        try assertCodableRoundTrip(try #require(output.layoutDecision))
        try assertCodableRoundTrip(try #require(output.visibilityDecision))
        try assertCodableRoundTrip(output.diagnostics)
    }

    private func fixture(named name: String) throws -> TimelineProjectionScenario {
        try #require(TimelineProjectionFixtureBuilder.scenario(named: name))
    }

    private func expectContractIssue(
        _ rule: TimelineProjectionValidationIssue.Rule,
        in scenario: TimelineProjectionScenario
    ) {
        let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))

        #expect(output.entryID == nil)
        #expect(output.issues.contains { issue in
            issue.kind == .contractValidation && issue.contractRule == rule
        }, "Expected \(rule), got \(output.issues)")
        #expect(output.diagnostics.validatedByContractValidator)
        #expect(output.diagnostics.contractIssueCount > 0)
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }
}
