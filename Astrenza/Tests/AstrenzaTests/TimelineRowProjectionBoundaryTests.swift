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

    @Test("Malformed adapter outputs produce typed row projection issues")
    func malformedAdapterOutputsProduceTypedRowProjectionIssues() throws {
        var network = try adapterOutput(named: "publish_state_placeholder_localOnly_noReadMarkerChange")
        network.diagnostics.requiresNetworkWork = true
        expectBoundaryIssue(.requiresNetworkWork, in: network)

        var database = try adapterOutput(named: "publish_state_placeholder_localOnly_noReadMarkerChange")
        database.diagnostics.requiresDBWork = true
        expectBoundaryIssue(.requiresDBWork, in: database)

        var deleteInsert = try adapterOutput(named: "ogp_pending_to_resolved")
        var deleteInsertMutation = try #require(deleteInsert.mutationExpectation)
        deleteInsertMutation.deletedIDs = [deleteInsertMutation.initialEntryID]
        deleteInsert.mutationExpectation = deleteInsertMutation
        expectBoundaryIssue(.deleteInsertMutationIntroduced, in: deleteInsert)

        var quoteReply = try adapterOutput(named: "quote_target_pending_to_resolved")
        var quoteReplyMutation = try #require(quoteReply.mutationExpectation)
        quoteReplyMutation.quoteCreatesReplyRelation = true
        quoteReply.mutationExpectation = quoteReplyMutation
        expectBoundaryIssue(.quoteTargetBecameReplyParent, in: quoteReply)

        var replyInline = try adapterOutput(named: "reply_parent_pending_to_resolved_headerOnly")
        var replyInlineLayout = try #require(replyInline.layoutDecision)
        replyInlineLayout.contract.replyHeaderMode = .inlineParentInDetail
        replyInlineLayout.contract.allowsInlineParentPreviewInHome = true
        replyInline.layoutDecision = replyInlineLayout
        expectBoundaryIssue(.homeReplyParentMustBeHeaderOnly, in: replyInline)

        let pendingNewScenario = try fixture(named: "pending_new_not_visible_until_user_action")
        let pendingNewEntryID = pendingNewScenario.expectedOutput.identity.entryID
        let pendingNewVisible = adapter.project(TimelineProjectionAdapterInput(
            scenario: pendingNewScenario,
            pendingNewEntryIDs: [pendingNewEntryID],
            userActionAllowsPendingNewInsertion: true
        ))
        expectBoundaryIssue(.pendingNewVisibilityRequiresExplicitUserAction, in: pendingNewVisible)

        var readMarker = try adapterOutput(named: "profile_missing_to_resolved_headerOnly")
        readMarker.diagnostics.readMarkerChanged = true
        expectBoundaryIssue(.readMarkerChanged, in: readMarker)

        var missingLayoutContract = try adapterOutput(named: "textOnly_author_visible")
        var layout = try #require(missingLayoutContract.layoutDecision)
        layout.hasLayoutContract = false
        missingLayoutContract.layoutDecision = layout
        expectBoundaryIssue(.missingLayoutContract, in: missingLayoutContract)
    }

    @Test("Every row projection issue kind has explicit negative coverage")
    func everyRowProjectionIssueKindHasExplicitNegativeCoverage() throws {
        let coverageCases = rowProjectionIssueCoverageCases
        let coveredKinds = Set(coverageCases.map { $0.kind.rawValue })
        let allKinds = Set(TimelineRowProjectionIssue.Kind.allCases.map(\.rawValue))

        #expect(
            allKinds.subtracting(coveredKinds).isEmpty,
            "Missing row projection issue coverage for \(allKinds.subtracting(coveredKinds).sorted())"
        )
        #expect(
            coveredKinds.subtracting(allKinds).isEmpty,
            "Stale row projection issue coverage for \(coveredKinds.subtracting(allKinds).sorted())"
        )

        for coverageCase in coverageCases {
            let input = try coverageCase.makeInput()
            let output = boundary.project(input)

            #expect(output.draft == nil, "\(coverageCase.testCaseName) should reject the draft")
            #expect(
                output.issues.contains { $0.kind == coverageCase.kind },
                "\(coverageCase.testCaseName) expected \(coverageCase.kind), got \(output.issues)"
            )
        }
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

    private func adapterOutput(named name: String) throws -> TimelineProjectionAdapterOutput {
        adapter.project(TimelineProjectionAdapterInput(scenario: try fixture(named: name)))
    }

    private func fixture(named name: String) throws -> TimelineProjectionScenario {
        try #require(TimelineProjectionFixtureBuilder.scenario(named: name))
    }

    private func expectBoundaryIssue(
        _ kind: TimelineRowProjectionIssue.Kind,
        in adapterOutput: TimelineProjectionAdapterOutput,
        userActionContext: TimelineRowProjectionUserActionContext = TimelineRowProjectionUserActionContext()
    ) {
        let output = boundary.project(TimelineRowProjectionInput(
            adapterOutput: adapterOutput,
            userActionContext: userActionContext
        ))

        #expect(output.draft == nil)
        #expect(output.issues.contains { $0.kind == kind }, "Expected \(kind), got \(output.issues)")
    }

    private var rowProjectionIssueCoverageCases: [RowProjectionIssueCoverageCase] {
        // New issue kinds must add a direct negative case here before they can ship.
        [
            RowProjectionIssueCoverageCase(
                kind: .adapterIssue,
                testCaseName: "invalidAdapterInputsBecomeTypedRowProjectionIssues"
            ) {
                var invalid = try fixture(named: "ogp_pending_to_resolved")
                invalid.expectedOutput.identity.itemKey += ":resolved"
                invalid.expectedOutput.mutation.finalEntryID = invalid.expectedOutput.identity.entryID
                let adapterOutput = adapter.project(TimelineProjectionAdapterInput(scenario: invalid))
                return TimelineRowProjectionInput(adapterOutput: adapterOutput)
            },
            RowProjectionIssueCoverageCase(
                kind: .missingEntryID,
                testCaseName: "missing entry ID adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.entryID = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingItemKey,
                testCaseName: "missing item key adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.itemKey = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingSourceEventID,
                testCaseName: "missing source event ID adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.sourceEventID = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingSortAt,
                testCaseName: "missing sort_at adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.sortAt = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingTieBreakID,
                testCaseName: "missing tie-break adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.tieBreakID = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingFeedItemReason,
                testCaseName: "missing feed item reason adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.feedItemReason = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingMutationExpectation,
                testCaseName: "missing mutation expectation adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.mutationExpectation = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingLayoutDecision,
                testCaseName: "missing layout decision adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.layoutDecision = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingLayoutContract,
                testCaseName: "malformedAdapterOutputsProduceTypedRowProjectionIssues"
            ) {
                try input(named: "textOnly_author_visible") { output in
                    output.layoutDecision?.hasLayoutContract = false
                }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingVisibilityDecision,
                testCaseName: "missing visibility decision adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.visibilityDecision = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .missingFallback,
                testCaseName: "missing fallback adapter output"
            ) {
                try input(named: "textOnly_author_visible") { $0.fallback = nil }
            },
            RowProjectionIssueCoverageCase(
                kind: .delayedResolveMustReconfigure,
                testCaseName: "malformed delayed resolve mutation"
            ) {
                try input(named: "ogp_pending_to_resolved") { output in
                    output.mutationExpectation?.style = .none
                }
            },
            RowProjectionIssueCoverageCase(
                kind: .deleteInsertMutationIntroduced,
                testCaseName: "malformedAdapterOutputsProduceTypedRowProjectionIssues"
            ) {
                try input(named: "ogp_pending_to_resolved") { output in
                    let entryID = try #require(output.entryID)
                    output.mutationExpectation?.deletedIDs = [entryID]
                }
            },
            RowProjectionIssueCoverageCase(
                kind: .pendingNewVisibilityRequiresExplicitUserAction,
                testCaseName: "pendingNewRemainsHiddenUnlessAdapterAndBoundaryHaveExplicitUserAction"
            ) {
                let scenario = try fixture(named: "pending_new_not_visible_until_user_action")
                let entryID = scenario.expectedOutput.identity.entryID
                let adapterOutput = adapter.project(TimelineProjectionAdapterInput(
                    scenario: scenario,
                    pendingNewEntryIDs: [entryID],
                    userActionAllowsPendingNewInsertion: true
                ))
                return TimelineRowProjectionInput(adapterOutput: adapterOutput)
            },
            RowProjectionIssueCoverageCase(
                kind: .readMarkerChanged,
                testCaseName: "malformedAdapterOutputsProduceTypedRowProjectionIssues"
            ) {
                try input(named: "profile_missing_to_resolved_headerOnly") {
                    $0.diagnostics.readMarkerChanged = true
                }
            },
            RowProjectionIssueCoverageCase(
                kind: .requiresNetworkWork,
                testCaseName: "malformedAdapterOutputsProduceTypedRowProjectionIssues"
            ) {
                try input(named: "publish_state_placeholder_localOnly_noReadMarkerChange") {
                    $0.diagnostics.requiresNetworkWork = true
                }
            },
            RowProjectionIssueCoverageCase(
                kind: .requiresDBWork,
                testCaseName: "malformedAdapterOutputsProduceTypedRowProjectionIssues"
            ) {
                try input(named: "publish_state_placeholder_localOnly_noReadMarkerChange") {
                    $0.diagnostics.requiresDBWork = true
                }
            },
            RowProjectionIssueCoverageCase(
                kind: .quoteTargetBecameReplyParent,
                testCaseName: "malformedAdapterOutputsProduceTypedRowProjectionIssues"
            ) {
                try input(named: "quote_target_pending_to_resolved") {
                    $0.mutationExpectation?.quoteCreatesReplyRelation = true
                }
            },
            RowProjectionIssueCoverageCase(
                kind: .homeReplyParentMustBeHeaderOnly,
                testCaseName: "malformedAdapterOutputsProduceTypedRowProjectionIssues"
            ) {
                try input(named: "reply_parent_pending_to_resolved_headerOnly") { output in
                    output.layoutDecision?.contract.replyHeaderMode = .inlineParentInDetail
                    output.layoutDecision?.contract.allowsInlineParentPreviewInHome = true
                }
            }
        ]
    }

    private func input(
        named name: String,
        mutate: (inout TimelineProjectionAdapterOutput) throws -> Void
    ) throws -> TimelineRowProjectionInput {
        var output = try adapterOutput(named: name)
        try mutate(&output)
        return TimelineRowProjectionInput(adapterOutput: output)
    }

    private struct RowProjectionIssueCoverageCase {
        var kind: TimelineRowProjectionIssue.Kind
        var testCaseName: String
        var makeInput: () throws -> TimelineRowProjectionInput
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }
}
