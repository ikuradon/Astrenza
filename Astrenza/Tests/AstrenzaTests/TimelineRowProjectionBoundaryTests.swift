import Foundation
import Testing
@testable import Astrenza

@Suite("Timeline row projection boundary")
struct TimelineRowProjectionBoundaryTests {
    private let adapter = FixtureBackedTimelineProjectionAdapter()
    private let boundary = FixtureBackedTimelineRowProjectionBoundary()
    private let scenarios = TimelineProjectionFixtureBuilder.allScenarios

    @Test("Every Phase 6.0 fixture maps through adapter boundary and draft")
    func everyPhase60FixtureMapsThroughAdapterBoundaryAndDraft() throws {
        var projectedCount = 0

        for scenario in scenarios {
            let adapterOutput = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
            let output = boundary.project(TimelineRowProjectionInput(adapterOutput: adapterOutput))
            let draft = try #require(output.draft, "Missing draft for \(scenario.name)")

            #expect(output.issues.isEmpty, "Unexpected boundary issues for \(scenario.name): \(output.issues)")
            #expect(output.scenarioName == scenario.name)
            #expect(output.surface == adapterOutput.surface)
            #expect(draft.id == scenario.expectedOutput.identity.entryID)
            #expect(draft.itemKey == scenario.expectedOutput.identity.itemKey)
            #expect(draft.sourceEventID == scenario.expectedOutput.identity.sourceEventID)
            #expect(draft.subjectEventID == scenario.expectedOutput.identity.subjectEventID)
            #expect(draft.sortAt == scenario.expectedOutput.identity.sortAt)
            #expect(draft.tieBreakID == scenario.expectedOutput.identity.tieBreakID)
            #expect(draft.feedItemReason == scenario.expectedOutput.identity.feedItemReason)
            #expect(draft.resolveExpectations == scenario.expectedOutput.resolveExpectations)
            #expect(draft.layoutDecision == adapterOutput.layoutDecision)
            #expect(draft.visibilityDecision == adapterOutput.visibilityDecision)
            #expect(draft.fallback == adapterOutput.fallback)
            #expect(draft.mutationExpectation == adapterOutput.mutationExpectation)
            projectedCount += 1
        }

        #expect(projectedCount == TimelineProjectionFixtureBuilder.allScenarios.count)
    }

    @Test("Invalid adapter inputs become typed row projection issues")
    func invalidAdapterInputsBecomeTypedRowProjectionIssues() throws {
        var invalid = try fixture(named: "ogp_pending_to_resolved")
        invalid.expectedOutput.identity.itemKey += ":resolved"
        invalid.expectedOutput.mutation.finalEntryID = invalid.expectedOutput.identity.entryID

        let adapterOutput = adapter.project(TimelineProjectionAdapterInput(scenario: invalid))
        let output = boundary.project(TimelineRowProjectionInput(adapterOutput: adapterOutput))

        #expect(output.draft == nil)
        #expect(output.issues.contains { issue in
            issue.kind == .adapterIssue
                && issue.adapterIssueKind == .contractValidation
                && issue.adapterContractRule == .unstableIdentity
        }, "Expected adapter issue mapping, got \(output.issues)")
    }

    @Test("Draft preserves item key TimelineEntryID and source subject distinction")
    func draftPreservesItemKeyTimelineEntryIDAndSourceSubjectDistinction() throws {
        let scenario = try fixture(named: "repost_target_pending_to_resolved")
        let output = try projectedOutput(for: scenario)
        let draft = try #require(output.draft)

        #expect(draft.id.rawValue == scenario.expectedOutput.identity.itemKey)
        #expect(draft.id == scenario.expectedOutput.identity.entryID)
        #expect(draft.sourceEventID == scenario.expectedOutput.identity.sourceEventID)
        #expect(draft.subjectEventID == scenario.expectedOutput.identity.subjectEventID)
        #expect(draft.subjectEventID != nil)
        #expect(draft.sourceEventID != draft.subjectEventID)
    }

    @Test("Delayed resolve drafts preserve reconfigure mutation without delete or insert")
    func delayedResolveDraftsPreserveReconfigureMutationWithoutDeleteOrInsert() throws {
        for scenario in scenarios where scenario.hasDelayedResolveTransition {
            let draft = try #require(projectedOutput(for: scenario).draft)
            let mutation = draft.mutationExpectation

            #expect(mutation.style == .reconfigure, "Unexpected mutation style for \(scenario.name)")
            #expect(mutation.delayedResolveStyle == .neverDeleteInsertForDelayedResolve)
            #expect(mutation.initialEntryID == mutation.finalEntryID)
            #expect(mutation.initialEntryID == scenario.expectedOutput.identity.entryID)
            #expect(mutation.insertedIDs.isEmpty)
            #expect(mutation.deletedIDs.isEmpty)
            #expect(!mutation.allowsDeleteInsertForDelayedResolve)
            #expect(!mutation.readMarkerChanged)
        }
    }

    @Test("Failed OGP media profile and target drafts keep source note visible with fallback")
    func failedOGPMediaProfileAndTargetDraftsKeepSourceNoteVisibleWithFallback() throws {
        for name in [
            "ogp_pending_to_failed_urlOnlyFallback",
            "media_imeta_absent_fixed_placeholder",
            "profile_missing_to_failed_npubFallback",
            "repost_target_deleted_unavailable",
            "quote_target_blocked_unavailableCard"
        ] {
            let draft = try #require(projectedOutput(for: try fixture(named: name)).draft)

            #expect(draft.fallback.keepsSourceNoteVisible, "Fallback hides source note for \(name)")
            #expect(!draft.visibilityDecision.removesSourceNote, "Visibility removes source note for \(name)")
            #expect(draft.visibilityDecision.fallbackMode == draft.fallback.mode)
        }
    }

    @Test("Quote target stays distinct from Home reply parent header")
    func quoteTargetStaysDistinctFromHomeReplyParentHeader() throws {
        let quote = try #require(projectedOutput(
            for: try fixture(named: "quote_target_must_not_create_reply_relation")
        ).draft)

        #expect(quote.resolveExpectations.contains { $0.target == .quoteTarget })
        #expect(!quote.mutationExpectation.quoteCreatesReplyRelation)
        #expect(quote.layoutDecision.contract.quoteMode == .collapsedCard)
        #expect(quote.layoutDecision.contract.replyHeaderMode == .absent)

        let reply = try #require(projectedOutput(
            for: try fixture(named: "reply_parent_pending_to_resolved_headerOnly")
        ).draft)

        #expect(reply.resolveExpectations.contains { $0.target == .replyParentRoot })
        #expect(reply.layoutDecision.contract.rowKind == .home)
        #expect(reply.layoutDecision.contract.replyHeaderMode == .oneLine)
        #expect(!reply.layoutDecision.contract.allowsInlineParentPreviewInHome)
    }

    @Test("Pending new remains hidden unless adapter and boundary have explicit user action")
    func pendingNewRemainsHiddenUnlessAdapterAndBoundaryHaveExplicitUserAction() throws {
        let scenario = try fixture(named: "pending_new_not_visible_until_user_action")
        let entryID = scenario.expectedOutput.identity.entryID

        let blockedAdapterOutput = adapter.project(TimelineProjectionAdapterInput(
            scenario: scenario,
            pendingNewEntryIDs: [entryID],
            userActionAllowsPendingNewInsertion: false
        ))
        let blocked = boundary.project(TimelineRowProjectionInput(
            adapterOutput: blockedAdapterOutput,
            userActionContext: TimelineRowProjectionUserActionContext(
                pendingNewEntryIDs: [entryID],
                allowsPendingNewVisibility: false
            )
        ))
        let blockedDraft = try #require(blocked.draft)

        #expect(!blockedDraft.visibilityDecision.includedInVisibleSnapshot)
        #expect(!blockedDraft.visibilityDecision.pendingNewVisible)
        #expect(!blockedDraft.diagnostics.pendingNewVisible)
        #expect(blockedDraft.mutationExpectation.style == .none)

        let allowedAdapterOutput = adapter.project(TimelineProjectionAdapterInput(
            scenario: scenario,
            pendingNewEntryIDs: [entryID],
            userActionAllowsPendingNewInsertion: true
        ))
        let allowed = boundary.project(TimelineRowProjectionInput(
            adapterOutput: allowedAdapterOutput,
            userActionContext: TimelineRowProjectionUserActionContext(
                pendingNewEntryIDs: [entryID],
                allowsPendingNewVisibility: true
            )
        ))
        let allowedDraft = try #require(allowed.draft)

        #expect(allowedDraft.visibilityDecision.includedInVisibleSnapshot)
        #expect(allowedDraft.visibilityDecision.pendingNewVisible)
        #expect(allowedDraft.diagnostics.pendingNewVisible)
        #expect(allowedDraft.mutationExpectation.style == .insertOnlyForExplicitUserPendingNewAction)
        #expect(allowedDraft.mutationExpectation.insertedIDs == [entryID])

        let mismatched = boundary.project(TimelineRowProjectionInput(
            adapterOutput: allowedAdapterOutput,
            userActionContext: TimelineRowProjectionUserActionContext(
                pendingNewEntryIDs: [entryID],
                allowsPendingNewVisibility: false
            )
        ))

        #expect(mismatched.draft == nil)
        #expect(mismatched.issues.contains { $0.kind == .pendingNewVisibilityRequiresExplicitUserAction })
    }

    @Test("Publish placeholder and diagnostics require no remote db or read marker work")
    func publishPlaceholderAndDiagnosticsRequireNoRemoteDBOrReadMarkerWork() throws {
        let draft = try #require(projectedOutput(
            for: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange")
        ).draft)

        #expect(draft.resolveExpectations.allSatisfy { expectation in
            expectation.target == .publishStatePlaceholder && !expectation.requiresRemoteWork
        })
        #expect(!draft.diagnostics.readMarkerChanged)
        #expect(!draft.diagnostics.requiresNetworkWork)
        #expect(!draft.diagnostics.requiresDBWork)

        for scenario in scenarios {
            let draft = try #require(projectedOutput(for: scenario).draft)

            #expect(!draft.diagnostics.readMarkerChanged, "Read marker changed for \(scenario.name)")
            #expect(!draft.diagnostics.requiresNetworkWork, "Network work required for \(scenario.name)")
            #expect(!draft.diagnostics.requiresDBWork, "DB work required for \(scenario.name)")
        }
    }

    @Test("Boundary draft models are codable equatable and sendable")
    func boundaryDraftModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineRowProjectionInput.self)
        assertSendable(TimelineRowProjectionUserActionContext.self)
        assertSendable(TimelineRowProjectionOutput.self)
        assertSendable(TimelineRowProjectionIssue.self)
        assertSendable(TimelineRowProjectionDiagnostics.self)
        assertSendable(TimelineProjectedRowDraft.self)

        let output = try projectedOutput(for: try fixture(named: "ogp_pending_to_resolved"))
        let draft = try #require(output.draft)

        try assertCodableRoundTrip(TimelineRowProjectionInput(
            adapterOutput: adapter.project(TimelineProjectionAdapterInput(scenario: try fixture(named: "ogp_pending_to_resolved"))),
            surface: .home,
            userActionContext: TimelineRowProjectionUserActionContext()
        ))
        try assertCodableRoundTrip(output)
        try assertCodableRoundTrip(draft)
        try assertCodableRoundTrip(draft.diagnostics)
    }

    private func projectedOutput(for scenario: TimelineProjectionScenario) throws -> TimelineRowProjectionOutput {
        let adapterOutput = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
        let output = boundary.project(TimelineRowProjectionInput(adapterOutput: adapterOutput))

        #expect(output.issues.isEmpty, "Unexpected boundary issues for \(scenario.name): \(output.issues)")
        return output
    }

    private func fixture(named name: String) throws -> TimelineProjectionScenario {
        try #require(TimelineProjectionFixtureBuilder.scenario(named: name))
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }
}
