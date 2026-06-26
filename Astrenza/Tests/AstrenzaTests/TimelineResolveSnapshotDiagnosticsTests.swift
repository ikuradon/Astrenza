import DesignSystem
import Foundation
import Testing
@testable import Astrenza

@Suite("Timeline resolve snapshot diagnostics")
struct TimelineResolveSnapshotDiagnosticsTests {
    private let adapter = FixtureBackedTimelineProjectionAdapter()
    private let boundary = FixtureBackedTimelineRowProjectionBoundary()
    private let mapper = TimelineEntryViewStateMapper()
    private let applyBuilder = TimelineResolveApplyExpectationBuilder()
    private let diagnosticsBuilder = TimelineResolveSnapshotDiagnosticsBuilder()

    @Test("Clean delayed resolve reconfigure maps to snapshot diagnostics")
    func cleanDelayedResolveReconfigureMapsToSnapshotDiagnostics() throws {
        let acceptance = try diagnosticsAcceptance(named: "ogp_pending_to_resolved")

        assertCleanReconfigure(acceptance, reason: .linkPreview)
        #expect(acceptance.diagnostics.mutationRecord?.fallbackReason == nil)
        #expect(acceptance.diagnostics.mutationRecord?.readMarkerChanged == false)
        #expect(acceptance.diagnostics.mutationExpectation.networkWaitedBeforeInteractiveScroll == false)

        let recorded = TimelineDiagnosticsRecorder().recordMutation(
            reason: try #require(acceptance.diagnostics.mutationExpectation.mutationReason),
            anchorBefore: acceptance.anchorBefore,
            anchorAfter: acceptance.anchorAfter,
            visibleIDsBefore: acceptance.visibleIDs,
            visibleIDsAfter: acceptance.visibleIDs,
            timestampMS: acceptance.timestampMS
        )
        #expect(recorded == acceptance.diagnostics.mutationRecord)
    }

    @Test("OGP resolve success maps to reconfigure diagnostics")
    func ogpResolveSuccessMapsToReconfigureDiagnostics() throws {
        let acceptance = try diagnosticsAcceptance(named: "ogp_pending_to_resolved")

        assertCleanReconfigure(acceptance, reason: .linkPreview)
        #expect(acceptance.applyExpectation.reconfigureIntent?.insertedIDs.isEmpty == true)
        #expect(acceptance.applyExpectation.reconfigureIntent?.deletedIDs.isEmpty == true)
        #expect(acceptance.diagnostics.mutationPlan?.insertedIDs.isEmpty == true)
        #expect(acceptance.diagnostics.mutationPlan?.deletedIDs.isEmpty == true)
    }

    @Test("OGP failure keeps source note visible and clean diagnostics")
    func ogpFailureKeepsSourceNoteVisibleAndCleanDiagnostics() throws {
        let acceptance = try diagnosticsAcceptance(named: "ogp_pending_to_failed_urlOnlyFallback")

        assertCleanReconfigure(acceptance, reason: .linkPreview)
        #expect(acceptance.after.body.keepsSourceNoteVisible)
        #expect(acceptance.after.visibility.keepsSourceNoteVisible)
        #expect(acceptance.after.visibility.fallbackMode == .urlOnly)
        guard case .failed(let failure) = acceptance.after.linkPreview else {
            Issue.record("Expected failed OGP fallback")
            return
        }
        #expect(failure.fallbackMode == .urlOnly)
    }

    @Test("Media resolve keeps item ID layout contract and reconfigure diagnostics")
    func mediaResolveKeepsItemIDLayoutContractAndReconfigureDiagnostics() throws {
        let acceptance = try diagnosticsAcceptance(named: "media_imeta_present_aspect_reserved")

        assertCleanReconfigure(acceptance, reason: .media)
        #expect(acceptance.before.id == acceptance.after.id)
        #expect(!acceptance.after.layoutContract.canChangeHeightAfterFirstDisplay)
        #expect(acceptance.after.layoutContract.reservedMediaAspectRatio == 4.0 / 3.0)
        #expect(acceptance.after.layoutContract.reservedMediaHeight == 240)
    }

    @Test("Profile resolve is header only and body mention wrap remains stable")
    func profileResolveIsHeaderOnlyAndBodyMentionWrapRemainsStable() throws {
        let profile = try diagnosticsAcceptance(named: "profile_missing_to_resolved_headerOnly")

        assertCleanReconfigure(profile, reason: .profile)
        #expect(profile.before.id == profile.after.id)
        #expect(!profile.after.layoutContract.canChangeHeightAfterFirstDisplay)

        let mention = try diagnosticsAcceptance(named: "body_mention_profile_resolve_must_not_increase_line_wrap")

        assertCleanReconfigure(mention, reason: .bodyMention)
        #expect(mention.after.layoutContract.bodyMentionRendering == .resolvedDisplayNameWithFallback)
        #expect(mention.after.layoutContract.maxBodyLinesInCollapsedMode == 8)
        #expect(!mention.after.layoutContract.canChangeHeightAfterFirstDisplay)
    }

    @Test("Repost target resolve keeps repost itemKey without duplicate insertion")
    func repostTargetResolveKeepsRepostItemKeyWithoutDuplicateInsertion() throws {
        let acceptance = try diagnosticsAcceptance(named: "repost_target_pending_to_resolved")
        let repost = try #require(acceptance.after.repost)

        assertCleanReconfigure(acceptance, reason: .repost)
        guard case .resolved(let resolved) = repost else {
            Issue.record("Expected resolved repost")
            return
        }
        #expect(resolved.itemKey == acceptance.after.itemKey)
        #expect(acceptance.diagnostics.mutationPlan?.insertedIDs.isEmpty == true)
    }

    @Test("Quote target resolve stays separate from reply parent")
    func quoteTargetResolveStaysSeparateFromReplyParent() throws {
        let acceptance = try diagnosticsAcceptance(named: "quote_target_pending_to_resolved")

        assertCleanReconfigure(acceptance, reason: .quote)
        #expect(acceptance.after.quote != nil)
        #expect(acceptance.after.replyContext == nil)
        #expect(!acceptance.after.diagnostics.quoteCreatesReplyRelation)
    }

    @Test("Reply parent resolve remains Home header only")
    func replyParentResolveRemainsHomeHeaderOnly() throws {
        let acceptance = try diagnosticsAcceptance(named: "reply_parent_pending_to_resolved_headerOnly")

        assertCleanReconfigure(acceptance, reason: .replyParent)
        #expect(acceptance.after.replyContext != nil)
        #expect(acceptance.after.layoutContract.replyHeaderMode == .oneLine)
        #expect(!acceptance.after.layoutContract.allowsInlineParentPreviewInHome)
    }

    @Test("Stats update maps to reconfigure diagnostics without read marker change")
    func statsUpdateMapsToReconfigureDiagnosticsWithoutReadMarkerChange() throws {
        let acceptance = try diagnosticsAcceptance(named: "stats_resolving_to_resolved_reconfigureOnly")

        assertCleanReconfigure(acceptance, reason: .stats)
        #expect(acceptance.after.stats != .absent)
        #expect(acceptance.diagnostics.mutationRecord?.readMarkerChanged == false)
    }

    @Test("Publish state placeholder update is local only reconfigure")
    func publishStatePlaceholderUpdateIsLocalOnlyReconfigure() throws {
        let acceptance = try diagnosticsAcceptance(named: "publish_state_placeholder_localOnly_noReadMarkerChange")

        assertCleanReconfigure(acceptance, reason: .publishStatePlaceholder)
        #expect(acceptance.after.publishState == .placeholder)
        #expect(!acceptance.applyExpectation.requiresNetworkWork)
        #expect(!acceptance.applyExpectation.requiresDBWork)
    }

    @Test("Pending new without user action remains excluded from visible snapshot")
    func pendingNewWithoutUserActionRemainsExcludedFromVisibleSnapshot() throws {
        let viewState = try mappedViewState(for: try fixture(named: "pending_new_not_visible_until_user_action"))
        let applyExpectation = applyBuilder.expectation(
            before: nil,
            after: viewState,
            existingIDs: []
        )

        let diagnostics = diagnosticsBuilder.expectation(
            scenarioName: viewState.diagnostics.scenarioName,
            resolveApplyExpectation: applyExpectation,
            visibleIDsBefore: [],
            visibleIDsAfter: [],
            timestampMS: 1_735_000_000_000
        )

        #expect(diagnostics.isClean)
        #expect(applyExpectation.style == .none)
        #expect(diagnostics.mutationExpectation.mutationReason == nil)
        #expect(diagnostics.mutationRecord == nil)
        #expect(!viewState.visibility.includedInVisibleSnapshot)
        #expect(!viewState.visibility.pendingNewVisible)
    }

    @Test("Explicit pending new user action is the only insert style exception")
    func explicitPendingNewUserActionIsTheOnlyInsertStyleException() throws {
        let scenario = try fixture(named: "pending_new_not_visible_until_user_action")
        let entryID = scenario.expectedOutput.identity.entryID
        let viewState = try mappedViewState(
            for: scenario,
            pendingNewEntryIDs: [entryID],
            allowsPendingNewVisibility: true
        )
        let userAction = TimelineResolveApplyUserAction(
            pendingNewEntryIDs: [entryID],
            allowsPendingNewInsertion: true
        )
        let applyExpectation = applyBuilder.expectation(
            before: nil,
            after: viewState,
            existingIDs: [],
            userAction: userAction
        )
        let anchorBefore = anchor(for: entryID, delta: -8)
        let anchorAfter = anchor(for: entryID, delta: -8)

        let diagnostics = diagnosticsBuilder.expectation(
            scenarioName: scenario.name,
            resolveApplyExpectation: applyExpectation,
            visibleIDsBefore: [],
            visibleIDsAfter: [entryID],
            anchorBefore: anchorBefore,
            anchorAfter: anchorAfter,
            timestampMS: 1_735_000_000_000
        )

        #expect(diagnostics.isClean)
        #expect(applyExpectation.style == .insertOnlyForExplicitUserPendingNewAction)
        #expect(diagnostics.mutationExpectation.mutationReason == .userInsertedPendingNew)
        #expect(diagnostics.mutationPlan?.insertedIDs == [entryID])
        #expect(diagnostics.mutationRecord?.readMarkerChanged == false)
        #expect(diagnostics.mutationExpectation.pendingNewInsertedIntoVisibleSnapshot)
    }

    @Test("Invalid resolve expectations cannot create clean snapshot diagnostics")
    func invalidResolveExpectationsCannotCreateCleanSnapshotDiagnostics() throws {
        try assertInvalidIssue(.identityChanged) {
            let pair = try viewStatePair(for: try fixture(named: "ogp_pending_to_resolved"))
            var after = pair.after
            after = replacing(after, id: TimelineEntryID(rawValue: after.id.rawValue + ":resolved"))
            return applyBuilder.expectation(before: pair.before, after: after, existingIDs: [pair.before.id])
        }

        try assertInvalidIssue(.readMarkerChanged) {
            var viewState = try mappedViewState(for: try fixture(named: "profile_missing_to_resolved_headerOnly"))
            viewState.diagnostics.readMarkerChanged = true
            return applyBuilder.expectation(before: nil, after: viewState, existingIDs: [viewState.id])
        }

        try assertInvalidIssue(.requiresNetworkWork) {
            var viewState = try mappedViewState(for: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange"))
            viewState.diagnostics.requiresNetworkWork = true
            return applyBuilder.expectation(before: nil, after: viewState, existingIDs: [viewState.id])
        }

        try assertInvalidIssue(.requiresDBWork) {
            var viewState = try mappedViewState(for: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange"))
            viewState.diagnostics.requiresDBWork = true
            return applyBuilder.expectation(before: nil, after: viewState, existingIDs: [viewState.id])
        }

        try assertInvalidIssue(.deleteInsertMutationIntroduced) {
            var viewState = try mappedViewState(for: try fixture(named: "media_imeta_present_aspect_reserved"))
            viewState.diagnostics.insertedIDs = [TimelineEntryID(rawValue: "unexpected:insert")]
            viewState.diagnostics.deletedIDs = [viewState.id]
            viewState.diagnostics.allowsDeleteInsertForDelayedResolve = true
            return applyBuilder.expectation(before: nil, after: viewState, existingIDs: [viewState.id])
        }
    }

    private func diagnosticsAcceptance(named name: String) throws -> TimelineResolveSnapshotDiagnosticsAcceptance {
        let pair = try viewStatePair(for: try fixture(named: name))
        let visibleIDs = [
            pair.after.id,
            TimelineEntryID(rawValue: "home:stable:tail")
        ]
        let anchorBefore = anchor(for: pair.after.id, delta: -8)
        let anchorAfter = anchor(for: pair.after.id, delta: -8)
        let timestampMS: Int64 = 1_735_000_000_000
        let applyExpectation = applyBuilder.expectation(
            before: pair.before,
            after: pair.after,
            existingIDs: visibleIDs
        )
        let diagnostics = diagnosticsBuilder.expectation(
            scenarioName: name,
            resolveApplyExpectation: applyExpectation,
            visibleIDsBefore: visibleIDs,
            visibleIDsAfter: visibleIDs,
            anchorBefore: anchorBefore,
            anchorAfter: anchorAfter,
            timestampMS: timestampMS
        )

        return TimelineResolveSnapshotDiagnosticsAcceptance(
            before: pair.before,
            after: pair.after,
            applyExpectation: applyExpectation,
            diagnostics: diagnostics,
            visibleIDs: visibleIDs,
            anchorBefore: anchorBefore,
            anchorAfter: anchorAfter,
            timestampMS: timestampMS
        )
    }

    private func assertCleanReconfigure(
        _ acceptance: TimelineResolveSnapshotDiagnosticsAcceptance,
        reason: ResolveApplyReason
    ) {
        #expect(acceptance.applyExpectation.issues.isEmpty)
        #expect(acceptance.applyExpectation.style == .reconfigure)
        #expect(acceptance.applyExpectation.reason == reason)
        #expect(acceptance.diagnostics.isClean)
        #expect(acceptance.diagnostics.mutationExpectation.mutationReason == reason.snapshotReason)
        #expect(acceptance.diagnostics.mutationPlan?.reason == reason.snapshotReason)
        #expect(acceptance.diagnostics.mutationPlan?.reconfigureIDs == [acceptance.after.id])
        #expect(acceptance.diagnostics.mutationPlan?.insertedIDs.isEmpty == true)
        #expect(acceptance.diagnostics.mutationPlan?.deletedIDs.isEmpty == true)
        #expect(acceptance.diagnostics.mutationRecord?.mutationReason == reason.snapshotReason)
        #expect(acceptance.diagnostics.mutationRecord?.visibleIDsBefore == acceptance.visibleIDs)
        #expect(acceptance.diagnostics.mutationRecord?.visibleIDsAfter == acceptance.visibleIDs)
        #expect(acceptance.diagnostics.mutationRecord?.anchorBefore?.anchorItemKey == acceptance.after.id.rawValue)
        #expect(acceptance.diagnostics.mutationRecord?.anchorAfter?.anchorItemKey == acceptance.after.id.rawValue)
        #expect(acceptance.diagnostics.mutationRecord?.anchorDelta?.deltaPoints == 0)
        #expect(acceptance.diagnostics.mutationRecord?.fallbackReason == nil)
        #expect(acceptance.diagnostics.mutationRecord?.readMarkerChanged == false)
        #expect(!acceptance.diagnostics.mutationExpectation.pendingNewInsertedIntoVisibleSnapshot)
    }

    private func assertInvalidIssue(
        _ kind: TimelineResolveSnapshotDiagnosticsIssue.Kind,
        makeExpectation: () throws -> TimelineResolveApplyExpectation
    ) throws {
        let applyExpectation = try makeExpectation()
        let diagnostics = diagnosticsBuilder.expectation(
            scenarioName: "invalid",
            resolveApplyExpectation: applyExpectation,
            visibleIDsBefore: [TimelineEntryID(rawValue: "home:stable")],
            visibleIDsAfter: [TimelineEntryID(rawValue: "home:stable")],
            timestampMS: 1_735_000_000_000
        )

        #expect(!diagnostics.isClean)
        #expect(diagnostics.mutationRecord == nil)
        #expect(diagnostics.issues.contains { $0.kind == kind }, "Expected \(kind), got \(diagnostics.issues)")
    }

    private func viewStatePair(
        for scenario: TimelineProjectionScenario
    ) throws -> (before: TimelineEntryViewState, after: TimelineEntryViewState) {
        let afterDraft = try projectedDraft(for: scenario)
        let beforeDraft = initialDraft(from: afterDraft)

        return (
            before: try mappedViewState(for: beforeDraft),
            after: try mappedViewState(for: afterDraft)
        )
    }

    private func projectedDraft(for scenario: TimelineProjectionScenario) throws -> TimelineProjectedRowDraft {
        let adapterOutput = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
        let output = boundary.project(TimelineRowProjectionInput(adapterOutput: adapterOutput))

        #expect(output.issues.isEmpty, "Unexpected boundary issues for \(scenario.name): \(output.issues)")
        return try #require(output.draft, "Missing draft for \(scenario.name)")
    }

    private func initialDraft(from draft: TimelineProjectedRowDraft) -> TimelineProjectedRowDraft {
        var initial = draft
        initial.resolveExpectations = draft.resolveExpectations.map { expectation in
            TimelineResolveExpectation(
                target: expectation.target,
                initialState: expectation.initialState,
                expectedState: expectation.initialState,
                requiresRemoteWork: false
            )
        }
        initial.mutationExpectation = TimelineProjectionMutationExpectation(
            style: .none,
            delayedResolveStyle: nil,
            initialEntryID: draft.id,
            finalEntryID: draft.id,
            insertedIDs: [],
            deletedIDs: [],
            allowsDeleteInsertForDelayedResolve: false,
            readMarkerChanged: false,
            pendingNewInsertedIntoVisibleSnapshot: false,
            quoteCreatesReplyRelation: false
        )
        initial.diagnostics = TimelineRowProjectionDiagnostics(
            scenarioName: draft.diagnostics.scenarioName,
            adapterIssueCount: 0,
            rowProjectionIssueCount: 0,
            readMarkerChanged: false,
            pendingNewVisible: draft.visibilityDecision.pendingNewVisible,
            requiresNetworkWork: false,
            requiresDBWork: false
        )
        return initial
    }

    private func mappedViewState(for draft: TimelineProjectedRowDraft) throws -> TimelineEntryViewState {
        let output = mapper.map(TimelineEntryViewStateMappingInput(draft: draft))

        #expect(output.issues.isEmpty, "Unexpected mapping issues for \(draft.diagnostics.scenarioName): \(output.issues)")
        return try #require(output.viewState, "Missing view state for \(draft.diagnostics.scenarioName)")
    }

    private func mappedViewState(
        for scenario: TimelineProjectionScenario,
        pendingNewEntryIDs: [TimelineEntryID] = [],
        allowsPendingNewVisibility: Bool = false
    ) throws -> TimelineEntryViewState {
        let userActionContext = TimelineRowProjectionUserActionContext(
            pendingNewEntryIDs: pendingNewEntryIDs,
            allowsPendingNewVisibility: allowsPendingNewVisibility
        )
        let adapterOutput = adapter.project(TimelineProjectionAdapterInput(
            scenario: scenario,
            pendingNewEntryIDs: pendingNewEntryIDs,
            userActionAllowsPendingNewInsertion: allowsPendingNewVisibility
        ))
        let output = boundary.project(TimelineRowProjectionInput(
            adapterOutput: adapterOutput,
            userActionContext: userActionContext
        ))
        let draft = try #require(output.draft, "Missing draft for \(scenario.name): \(output.issues)")
        let mapped = mapper.map(TimelineEntryViewStateMappingInput(
            draft: draft,
            userActionContext: userActionContext
        ))

        #expect(mapped.issues.isEmpty, "Unexpected mapping issues for \(scenario.name): \(mapped.issues)")
        return try #require(mapped.viewState, "Missing view state for \(scenario.name)")
    }

    private func replacing(
        _ state: TimelineEntryViewState,
        id: TimelineEntryID
    ) -> TimelineEntryViewState {
        TimelineEntryViewState(
            id: id,
            itemKey: state.itemKey,
            sourceEventID: state.sourceEventID,
            subjectEventID: state.subjectEventID,
            sortKey: state.sortKey,
            reason: state.reason,
            author: state.author,
            body: state.body,
            media: state.media,
            linkPreview: state.linkPreview,
            repost: state.repost,
            quote: state.quote,
            replyContext: state.replyContext,
            stats: state.stats,
            visibility: state.visibility,
            publishState: state.publishState,
            layoutContract: state.layoutContract,
            diagnostics: state.diagnostics
        )
    }

    private func anchor(
        for entryID: TimelineEntryID,
        delta: Double
    ) -> TimelineVisualAnchor {
        TimelineVisualAnchor(
            accountID: AccountID(rawValue: "account-a"),
            feedID: FeedID(rawValue: 1),
            timelineKey: TimelineKey(rawValue: "home"),
            anchorItemKey: entryID.rawValue,
            anchorEventID: entryID.sourceEventID,
            anchorSortAt: entryID.sortAt ?? 0,
            anchorTieBreakID: entryID.tieBreakID ?? entryID.rawValue,
            cellTopDeltaFromViewportTop: delta,
            viewportHeight: 844,
            viewportWidth: 390,
            contentInsetTop: 0,
            contentInsetBottom: 34,
            lastVisibleTopItemKey: entryID.rawValue,
            lastVisibleBottomItemKey: entryID.rawValue,
            markerEventID: nil,
            markerSortAt: nil,
            capturedAtMS: 1_735_000_000_000,
            schemaVersion: 1
        )
    }

    private func fixture(named name: String) throws -> TimelineProjectionScenario {
        try #require(TimelineProjectionFixtureBuilder.scenario(named: name))
    }

    private struct TimelineResolveSnapshotDiagnosticsAcceptance {
        var before: TimelineEntryViewState
        var after: TimelineEntryViewState
        var applyExpectation: TimelineResolveApplyExpectation
        var diagnostics: TimelineResolveSnapshotDiagnosticsExpectation
        var visibleIDs: [TimelineEntryID]
        var anchorBefore: TimelineVisualAnchor
        var anchorAfter: TimelineVisualAnchor
        var timestampMS: Int64
    }
}
