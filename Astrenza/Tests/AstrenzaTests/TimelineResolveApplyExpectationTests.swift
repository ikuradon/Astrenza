import Foundation
import Testing
@testable import Astrenza

@Suite("Timeline resolve apply expectations")
struct TimelineResolveApplyExpectationTests {
    private let adapter = FixtureBackedTimelineProjectionAdapter()
    private let boundary = FixtureBackedTimelineRowProjectionBoundary()
    private let mapper = TimelineEntryViewStateMapper()
    private let builder = TimelineResolveApplyExpectationBuilder()
    private let scenarios = TimelineProjectionFixtureBuilder.allScenarios

    @Test("All valid delayed resolve transition fixtures produce reconfigure-style expectation")
    func allValidDelayedResolveTransitionFixturesProduceReconfigureStyleExpectation() throws {
        for scenario in scenarios where scenario.hasDelayedResolveTransition {
            let pair = try viewStatePair(for: scenario)
            let expectation = builder.expectation(
                before: pair.before,
                after: pair.after,
                existingIDs: [pair.after.id]
            )
            let intent = try #require(expectation.reconfigureIntent, "Missing reconfigure intent for \(scenario.name)")

            #expect(expectation.issues.isEmpty, "Unexpected expectation issues for \(scenario.name): \(expectation.issues)")
            #expect(expectation.style == .reconfigure)
            #expect(intent.mutationStyle == .reconfigure)
            #expect(intent.entryIDs == [pair.after.id])
            #expect(intent.insertedIDs.isEmpty)
            #expect(intent.deletedIDs.isEmpty)
            #expect(expectation.insertedIDs.isEmpty)
            #expect(expectation.deletedIDs.isEmpty)
            #expect(!expectation.readMarkerChanged)
            #expect(!expectation.requiresNetworkWork)
            #expect(!expectation.requiresDBWork)
        }
    }

    @Test("Profile resolve transitions preserve ID and read marker")
    func profileResolveTransitionsPreserveIDAndReadMarker() throws {
        for state in [TimelineProjectionResolveState.resolving, .resolved, .failed] {
            let pair = try viewStatePair(
                named: "profile_missing_to_resolved_headerOnly",
                target: .profile,
                from: .pending,
                to: state
            )
            let expectation = builder.expectation(
                before: pair.before,
                after: pair.after,
                existingIDs: [pair.after.id]
            )

            #expect(expectation.issues.isEmpty, "Unexpected profile issue for \(state): \(expectation.issues)")
            #expect(expectation.style == .reconfigure)
            #expect(expectation.reason == .profile)
            #expect(pair.before.id == pair.after.id)
            #expect(!expectation.readMarkerChanged)
        }
    }

    @Test("OGP resolve success preserves ID and fallback rules")
    func ogpResolveSuccessPreservesIDAndFallbackRules() throws {
        for state in [TimelineProjectionResolveState.resolving, .resolved, .blocked, .unavailable] {
            let pair = try viewStatePair(
                named: "ogp_pending_to_resolved",
                target: .linkPreviewOGP,
                from: .pending,
                to: state
            )
            let expectation = builder.expectation(
                before: pair.before,
                after: pair.after,
                existingIDs: [pair.after.id]
            )

            #expect(expectation.issues.isEmpty, "Unexpected OGP issue for \(state): \(expectation.issues)")
            #expect(expectation.style == .reconfigure)
            #expect(expectation.reason == .linkPreview)
            #expect(pair.before.id == pair.after.id)
            #expect(pair.after.visibility.keepsSourceNoteVisible)
        }
    }

    @Test("OGP failure preserves source note visible")
    func ogpFailurePreservesSourceNoteVisible() throws {
        let pair = try viewStatePair(for: try fixture(named: "ogp_pending_to_failed_urlOnlyFallback"))
        let expectation = builder.expectation(
            before: pair.before,
            after: pair.after,
            existingIDs: [pair.after.id]
        )

        #expect(expectation.issues.isEmpty)
        #expect(expectation.style == .reconfigure)
        #expect(pair.after.body.keepsSourceNoteVisible)
        #expect(pair.after.visibility.keepsSourceNoteVisible)
        #expect(pair.after.visibility.fallbackMode == .urlOnly)
    }

    @Test("Media resolve preserves layout contract")
    func mediaResolvePreservesLayoutContract() throws {
        for state in [TimelineProjectionResolveState.resolved, .failed, .blocked] {
            let pair = try viewStatePair(
                named: "media_imeta_present_aspect_reserved",
                target: .media,
                from: .pending,
                to: state
            )
            let expectation = builder.expectation(
                before: pair.before,
                after: pair.after,
                existingIDs: [pair.after.id]
            )

            #expect(expectation.issues.isEmpty, "Unexpected media issue for \(state): \(expectation.issues)")
            #expect(expectation.style == .reconfigure)
            #expect(expectation.reason == .media)
            #expect(!pair.after.layoutContract.canChangeHeightAfterFirstDisplay)
            #expect(pair.after.layoutContract.reservedMediaAspectRatio == 4.0 / 3.0)
            #expect(pair.after.layoutContract.reservedMediaHeight == 240)
        }
    }

    @Test("Repost target resolve preserves repost itemKey")
    func repostTargetResolvePreservesRepostItemKey() throws {
        for name in ["repost_target_pending_to_resolved", "repost_target_deleted_unavailable"] {
            let pair = try viewStatePair(for: try fixture(named: name))
            let expectation = builder.expectation(
                before: pair.before,
                after: pair.after,
                existingIDs: [pair.after.id]
            )
            let repost = try #require(pair.after.repost)

            #expect(expectation.issues.isEmpty, "Unexpected repost issue for \(name): \(expectation.issues)")
            #expect(expectation.style == .reconfigure)
            #expect(expectation.reason == .repost)
            switch repost {
            case .resolved(let resolved):
                #expect(resolved.itemKey == pair.after.itemKey)
            case .unavailable(let unavailable):
                #expect(unavailable.itemKey == pair.after.itemKey)
            default:
                Issue.record("Expected resolved or unavailable repost for \(name)")
            }
        }
    }

    @Test("Quote target resolve does not become reply parent")
    func quoteTargetResolveDoesNotBecomeReplyParent() throws {
        let pair = try viewStatePair(for: try fixture(named: "quote_target_pending_to_resolved"))
        let expectation = builder.expectation(
            before: pair.before,
            after: pair.after,
            existingIDs: [pair.after.id]
        )

        #expect(expectation.issues.isEmpty)
        #expect(expectation.style == .reconfigure)
        #expect(expectation.reason == .quote)
        #expect(pair.after.quote != nil)
        #expect(pair.after.replyContext == nil)
        #expect(!pair.after.diagnostics.quoteCreatesReplyRelation)
    }

    @Test("Reply parent resolve remains header-only")
    func replyParentResolveRemainsHeaderOnly() throws {
        let pair = try viewStatePair(for: try fixture(named: "reply_parent_pending_to_resolved_headerOnly"))
        let expectation = builder.expectation(
            before: pair.before,
            after: pair.after,
            existingIDs: [pair.after.id]
        )

        #expect(expectation.issues.isEmpty)
        #expect(expectation.style == .reconfigure)
        #expect(expectation.reason == .replyParent)
        #expect(pair.after.replyContext != nil)
        #expect(pair.after.layoutContract.replyHeaderMode == .oneLine)
        #expect(!pair.after.layoutContract.allowsInlineParentPreviewInHome)
    }

    @Test("Stats update is reconfigure-only")
    func statsUpdateIsReconfigureOnly() throws {
        let pair = try viewStatePair(for: try fixture(named: "stats_resolving_to_resolved_reconfigureOnly"))
        let expectation = builder.expectation(
            before: pair.before,
            after: pair.after,
            existingIDs: [pair.after.id]
        )

        #expect(expectation.issues.isEmpty)
        #expect(expectation.style == .reconfigure)
        #expect(expectation.reason == .stats)
        #expect(expectation.reconfigureIntent?.entryIDs == [pair.after.id])
        #expect(expectation.insertedIDs.isEmpty)
        #expect(expectation.deletedIDs.isEmpty)
    }

    @Test("Publish state placeholder update is reconfigure-only and local-only")
    func publishStatePlaceholderUpdateIsReconfigureOnlyAndLocalOnly() throws {
        let pair = try viewStatePair(for: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange"))
        let expectation = builder.expectation(
            before: pair.before,
            after: pair.after,
            existingIDs: [pair.after.id]
        )

        #expect(expectation.issues.isEmpty)
        #expect(expectation.style == .reconfigure)
        #expect(expectation.reason == .publishStatePlaceholder)
        #expect(pair.after.publishState == .placeholder)
        #expect(!expectation.requiresNetworkWork)
        #expect(!expectation.requiresDBWork)
    }

    @Test("Pending new without user action does not produce visible insert")
    func pendingNewWithoutUserActionDoesNotProduceVisibleInsert() throws {
        let viewState = try mappedViewState(for: try fixture(named: "pending_new_not_visible_until_user_action"))
        let expectation = builder.expectation(
            before: nil,
            after: viewState,
            existingIDs: []
        )

        #expect(expectation.issues.isEmpty)
        #expect(expectation.style == .none)
        #expect(expectation.insertedIDs.isEmpty)
        #expect(!viewState.visibility.includedInVisibleSnapshot)
        #expect(!viewState.visibility.pendingNewVisible)
    }

    @Test("Explicit pending new user action is the only case allowed to produce insert-style expectation")
    func explicitPendingNewUserActionIsOnlyAllowedInsertStyleExpectation() throws {
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
        let allowed = builder.expectation(
            before: nil,
            after: viewState,
            existingIDs: [],
            userAction: userAction
        )
        let rejected = builder.expectation(
            before: nil,
            after: viewState,
            existingIDs: []
        )

        #expect(allowed.issues.isEmpty)
        #expect(allowed.style == .insertOnlyForExplicitUserPendingNewAction)
        #expect(allowed.insertedIDs == [entryID])
        #expect(rejected.issues.contains { $0.kind == .pendingNewInsertRequiresExplicitUserAction })
    }

    @Test("Identity mismatch produces typed invalid issue")
    func identityMismatchProducesTypedInvalidIssue() throws {
        let pair = try viewStatePair(for: try fixture(named: "ogp_pending_to_resolved"))
        let mismatched = replacing(
            pair.after,
            id: TimelineEntryID(rawValue: pair.after.id.rawValue + ":resolved")
        )
        let expectation = builder.expectation(
            before: pair.before,
            after: mismatched,
            existingIDs: [pair.before.id]
        )

        #expect(expectation.style == .invalid)
        #expect(expectation.issues.contains { $0.kind == .identityChanged })
    }

    @Test("Read marker changed true produces typed invalid issue")
    func readMarkerChangedTrueProducesTypedInvalidIssue() throws {
        var viewState = try mappedViewState(for: try fixture(named: "profile_missing_to_resolved_headerOnly"))
        viewState.diagnostics.readMarkerChanged = true

        let expectation = builder.expectation(
            before: nil,
            after: viewState,
            existingIDs: [viewState.id]
        )

        #expect(expectation.style == .invalid)
        #expect(expectation.issues.contains { $0.kind == .readMarkerChanged })
    }

    @Test("Requires network or database work true produces typed invalid issue")
    func requiresNetworkOrDBWorkTrueProducesTypedInvalidIssue() throws {
        var network = try mappedViewState(for: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange"))
        network.diagnostics.requiresNetworkWork = true
        var database = network
        database.diagnostics.requiresNetworkWork = false
        database.diagnostics.requiresDBWork = true

        let networkExpectation = builder.expectation(before: nil, after: network, existingIDs: [network.id])
        let databaseExpectation = builder.expectation(before: nil, after: database, existingIDs: [database.id])

        #expect(networkExpectation.style == .invalid)
        #expect(networkExpectation.issues.contains { $0.kind == .requiresNetworkWork })
        #expect(databaseExpectation.style == .invalid)
        #expect(databaseExpectation.issues.contains { $0.kind == .requiresDBWork })
    }

    @Test("Delete insert delayed resolve expectation is rejected")
    func deleteInsertDelayedResolveExpectationIsRejected() throws {
        var viewState = try mappedViewState(for: try fixture(named: "media_imeta_present_aspect_reserved"))
        viewState.diagnostics.insertedIDs = [TimelineEntryID(rawValue: "unexpected:insert")]
        viewState.diagnostics.deletedIDs = [viewState.id]
        viewState.diagnostics.allowsDeleteInsertForDelayedResolve = true

        let expectation = builder.expectation(
            before: nil,
            after: viewState,
            existingIDs: [viewState.id]
        )

        #expect(expectation.style == .invalid)
        #expect(expectation.issues.contains { $0.kind == .deleteInsertMutationIntroduced })
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

    private func viewStatePair(
        named name: String,
        target: TimelineDelayedResolveTarget,
        from initialState: TimelineProjectionResolveState,
        to expectedState: TimelineProjectionResolveState
    ) throws -> (before: TimelineEntryViewState, after: TimelineEntryViewState) {
        var afterDraft = try projectedDraft(for: try fixture(named: name))
        afterDraft.resolveExpectations = [
            TimelineResolveExpectation(
                target: target,
                initialState: initialState,
                expectedState: expectedState
            )
        ]
        afterDraft.mutationExpectation = reconfigureMutation(for: afterDraft)
        afterDraft.diagnostics = diagnostics(for: afterDraft)

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
        initial.diagnostics = diagnostics(for: initial)
        return initial
    }

    private func reconfigureMutation(for draft: TimelineProjectedRowDraft) -> TimelineProjectionMutationExpectation {
        TimelineProjectionMutationExpectation(
            style: .reconfigure,
            delayedResolveStyle: .neverDeleteInsertForDelayedResolve,
            initialEntryID: draft.id,
            finalEntryID: draft.id,
            insertedIDs: [],
            deletedIDs: [],
            allowsDeleteInsertForDelayedResolve: false,
            readMarkerChanged: false,
            pendingNewInsertedIntoVisibleSnapshot: false,
            quoteCreatesReplyRelation: false
        )
    }

    private func diagnostics(for draft: TimelineProjectedRowDraft) -> TimelineRowProjectionDiagnostics {
        TimelineRowProjectionDiagnostics(
            scenarioName: draft.diagnostics.scenarioName,
            adapterIssueCount: 0,
            rowProjectionIssueCount: 0,
            readMarkerChanged: false,
            pendingNewVisible: draft.visibilityDecision.pendingNewVisible,
            requiresNetworkWork: false,
            requiresDBWork: false
        )
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
        id: TimelineEntryID? = nil
    ) -> TimelineEntryViewState {
        TimelineEntryViewState(
            id: id ?? state.id,
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

    private func fixture(named name: String) throws -> TimelineProjectionScenario {
        try #require(TimelineProjectionFixtureBuilder.scenario(named: name))
    }
}
