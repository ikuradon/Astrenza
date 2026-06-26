import Foundation
import Testing
@testable import Astrenza

@Suite("ResolveCoordinator boundary contract")
struct ResolveCoordinatorBoundaryContractTests {
    private let adapter = FixtureBackedTimelineProjectionAdapter()
    private let rowBoundary = FixtureBackedTimelineRowProjectionBoundary()
    private let mapper = TimelineEntryViewStateMapper()
    private let boundary = FakeResolveCoordinatorBoundary()

    @Test("Valid profile resolve request creates a plan with visible-row priority")
    func validProfileResolveRequestCreatesPlanWithVisibleRowPriority() {
        let request = resolveRequest(kind: .profile, scope: .visibleRows, priority: .visibleRows)
        let plan = boundary.plan([request])

        #expect(plan.issues.isEmpty)
        #expect(plan.acceptedRequests == [request])
        #expect(plan.rejectedRequests.isEmpty)
        #expect(plan.orderedRequestIDs == [request.id])
        #expect(request.priority.sortRank > ResolvePriority.nearViewport.sortRank)
        #expect(plan.diagnostics.visibleRowResolveCount == 1)
        #expect(plan.diagnostics.futureNetworkTargetCount == 1)
        #expect(plan.diagnostics.networkWorkStarted == false)
        #expect(plan.diagnostics.dbWorkStarted == false)
    }

    @Test("Near viewport request has lower priority than visible-row request")
    func nearViewportRequestHasLowerPriorityThanVisibleRowRequest() {
        let near = resolveRequest(id: "near", kind: .profile, scope: .nearViewport, priority: .nearViewport)
        let visible = resolveRequest(id: "visible", kind: .profile, scope: .visibleRows, priority: .visibleRows)
        let plan = boundary.plan([near, visible])

        #expect(plan.issues.isEmpty)
        #expect(plan.orderedRequestIDs == [visible.id, near.id])
        #expect(visible.priority.sortRank > near.priority.sortRank)
    }

    @Test("Background cache warming has lowest priority")
    func backgroundCacheWarmingHasLowestPriority() {
        let background = resolveRequest(
            id: "background",
            kind: .profile,
            scope: .backgroundCacheWarming,
            priority: .backgroundCacheWarming
        )
        let near = resolveRequest(id: "near", kind: .profile, scope: .nearViewport, priority: .nearViewport)
        let visible = resolveRequest(id: "visible", kind: .profile, scope: .visibleRows, priority: .visibleRows)
        let plan = boundary.plan([background, near, visible])

        #expect(plan.issues.isEmpty)
        #expect(plan.orderedRequestIDs == [visible.id, near.id, background.id])
        #expect(background.priority.sortRank < near.priority.sortRank)
    }

    @Test("Priority ordering is deterministic for matching ranks")
    func priorityOrderingIsDeterministicForMatchingRanks() {
        let laterID = resolveRequest(id: "visible-b", kind: .profile, scope: .visibleRows, priority: .visibleRows)
        let earlierID = resolveRequest(id: "visible-a", kind: .profile, scope: .visibleRows, priority: .visibleRows)
        let plan = boundary.plan([laterID, earlierID])

        #expect(plan.issues.isEmpty)
        #expect(plan.orderedRequestIDs == [earlierID.id, laterID.id])
    }

    @Test("OGP resolve result maps to reconfigure-style TimelineResolveApplyExpectation")
    func ogpResolveResultMapsToReconfigureStyleExpectation() throws {
        let acceptance = try resolveAcceptance(
            named: "ogp_pending_to_resolved",
            kind: .linkPreviewOGP,
            scriptedResult: .resolved
        )

        assertReconfigure(acceptance.result, reason: .linkPreview, entryID: acceptance.after.id)
        #expect(acceptance.result.diagnostics.pendingNewInserted == false)
        #expect(acceptance.result.diagnostics.readMarkerChanged == false)
    }

    @Test("Media metadata result maps to reconfigure-style expectation")
    func mediaMetadataResultMapsToReconfigureStyleExpectation() throws {
        let acceptance = try resolveAcceptance(
            named: "media_imeta_present_aspect_reserved",
            kind: .mediaMetadata,
            scriptedResult: .resolved
        )

        assertReconfigure(acceptance.result, reason: .media, entryID: acceptance.after.id)
        #expect(acceptance.after.layoutContract.reservedMediaAspectRatio == 4.0 / 3.0)
    }

    @Test("Repost target result maps to reconfigure-style expectation")
    func repostTargetResultMapsToReconfigureStyleExpectation() throws {
        let acceptance = try resolveAcceptance(
            named: "repost_target_pending_to_resolved",
            kind: .repostTarget,
            scriptedResult: .resolved
        )

        assertReconfigure(acceptance.result, reason: .repost, entryID: acceptance.after.id)
        #expect(acceptance.after.repost != nil)
    }

    @Test("Quote target result maps to reconfigure-style expectation and not reply relation")
    func quoteTargetResultMapsToReconfigureStyleExpectationAndNotReplyRelation() throws {
        let acceptance = try resolveAcceptance(
            named: "quote_target_pending_to_resolved",
            kind: .quoteTarget,
            scriptedResult: .resolved
        )

        assertReconfigure(acceptance.result, reason: .quote, entryID: acceptance.after.id)
        #expect(acceptance.after.quote != nil)
        #expect(acceptance.after.replyContext == nil)
        #expect(acceptance.after.diagnostics.quoteCreatesReplyRelation == false)
    }

    @Test("Reply parent result maps to header-only update")
    func replyParentResultMapsToHeaderOnlyUpdate() throws {
        let acceptance = try resolveAcceptance(
            named: "reply_parent_pending_to_resolved_headerOnly",
            kind: .replyParent,
            scriptedResult: .resolved
        )

        assertReconfigure(acceptance.result, reason: .replyParent, entryID: acceptance.after.id)
        #expect(acceptance.after.replyContext != nil)
        #expect(acceptance.after.layoutContract.replyHeaderMode == .oneLine)
        #expect(acceptance.after.layoutContract.allowsInlineParentPreviewInHome == false)
    }

    @Test("Failed OGP profile and media result keeps source note visible with fallback")
    func failedOGPProfileAndMediaResultKeepsSourceNoteVisibleWithFallback() throws {
        for fixture in [
            ("ogp_pending_to_failed_urlOnlyFallback", ResolveTargetKind.linkPreviewOGP, TimelineFallbackMode.urlOnly),
            ("profile_missing_to_failed_npubFallback", .profile, .npubHeaderOnly),
            ("media_imeta_absent_fixed_placeholder", .mediaMetadata, .fixedMediaPlaceholder)
        ] {
            let acceptance = try resolveAcceptance(
                named: fixture.0,
                kind: fixture.1,
                scriptedResult: .failed
            )

            #expect(acceptance.result.state == .failed)
            #expect(acceptance.result.keepsSourceNoteVisible)
            #expect(acceptance.result.fallbackMode == fixture.2)
            #expect(acceptance.after.body.keepsSourceNoteVisible)
            #expect(acceptance.after.visibility.keepsSourceNoteVisible)
            assertReconfigure(acceptance.result, reason: fixture.1.resolveApplyReason, entryID: acceptance.after.id)
        }
    }

    @Test("Blocked or unavailable target returns fallback and no note removal")
    func blockedOrUnavailableTargetReturnsFallbackAndNoNoteRemoval() throws {
        let blocked = try resolveAcceptance(
            named: "media_blocked_keepsBlockedPlaceholder",
            kind: .mediaMetadata,
            scriptedResult: .blocked
        )
        let unavailable = try resolveAcceptance(
            named: "repost_target_deleted_unavailable",
            kind: .repostTarget,
            scriptedResult: .unavailable
        )

        #expect(blocked.result.state == .blocked)
        #expect(blocked.result.keepsSourceNoteVisible)
        #expect(blocked.after.visibility.removesSourceNote == false)
        #expect(unavailable.result.state == .unavailable)
        #expect(unavailable.result.keepsSourceNoteVisible)
        #expect(unavailable.after.visibility.removesSourceNote == false)
    }

    @Test("PublishStatePlaceholder is local-only and no network or DB")
    func publishStatePlaceholderIsLocalOnlyAndNoNetworkOrDB() throws {
        let request = resolveRequest(
            kind: .publishStatePlaceholder,
            scope: .localOnly,
            priority: .localOnly
        )
        let plan = boundary.plan([request])
        let acceptance = try resolveAcceptance(
            named: "publish_state_placeholder_localOnly_noReadMarkerChange",
            kind: .publishStatePlaceholder,
            scriptedResult: .resolved
        )

        #expect(plan.issues.isEmpty)
        #expect(request.target.isLocalOnly)
        #expect(plan.diagnostics.futureNetworkTargetCount == 0)
        #expect(plan.diagnostics.futureDBTargetCount == 0)
        #expect(plan.diagnostics.networkWorkStarted == false)
        #expect(plan.diagnostics.dbWorkStarted == false)
        assertReconfigure(acceptance.result, reason: .publishStatePlaceholder, entryID: acceptance.after.id)
    }

    @Test("Stats update is local and reconfigure-only")
    func statsUpdateIsLocalAndReconfigureOnly() throws {
        let request = resolveRequest(kind: .stats, scope: .localOnly, priority: .localOnly)
        let plan = boundary.plan([request])
        let acceptance = try resolveAcceptance(
            named: "stats_resolving_to_resolved_reconfigureOnly",
            kind: .stats,
            scriptedResult: .resolved
        )

        #expect(plan.issues.isEmpty)
        #expect(request.target.isLocalOnly)
        #expect(plan.diagnostics.futureNetworkTargetCount == 0)
        #expect(plan.diagnostics.futureDBTargetCount == 0)
        assertReconfigure(acceptance.result, reason: .stats, entryID: acceptance.after.id)
    }

    @Test("Pending new is not inserted by resolve boundary")
    func pendingNewIsNotInsertedByResolveBoundary() throws {
        let viewState = try mappedViewState(for: try fixture(named: "pending_new_not_visible_until_user_action"))
        let request = resolveRequest(kind: .profile, entryID: viewState.id)
        let result = boundary.result(
            for: request,
            before: nil,
            after: viewState,
            existingIDs: []
        )
        let applyExpectation = try #require(result.applyExpectation)

        #expect(result.issues.isEmpty)
        #expect(applyExpectation.style == TimelineResolveApplyExpectation.Style.none)
        #expect(applyExpectation.insertedIDs.isEmpty)
        #expect(result.diagnostics.pendingNewInserted == false)
        #expect(viewState.visibility.includedInVisibleSnapshot == false)
    }

    @Test("Read marker changed stays false")
    func readMarkerChangedStaysFalse() throws {
        let acceptance = try resolveAcceptance(
            named: "profile_missing_to_resolved_headerOnly",
            kind: .profile,
            scriptedResult: .resolved
        )

        #expect(acceptance.result.applyExpectation?.readMarkerChanged == false)
        #expect(acceptance.result.diagnostics.readMarkerChanged == false)
    }

    @Test("Result read marker change is rejected and not exposed")
    func resultReadMarkerChangeIsRejectedAndNotExposed() throws {
        let pair = try viewStatePair(for: try fixture(named: "profile_missing_to_resolved_headerOnly"))
        var after = pair.after
        after.diagnostics.readMarkerChanged = true
        let request = resolveRequest(kind: .profile, entryID: after.id)
        let result = boundary.result(
            for: request,
            before: pair.before,
            after: after,
            existingIDs: [after.id]
        )

        #expect(result.state == .blocked)
        #expect(result.applyExpectation == nil)
        #expect(result.issues.contains { $0.kind == .readMarkerAdvanceAttempted })
        #expect(result.diagnostics.readMarkerChanged == false)
    }

    @Test("No network request allowed in no-network test mode")
    func noNetworkRequestAllowedInNoNetworkTestMode() {
        let request = resolveRequest(kind: .linkPreviewOGP, requestsNetworkWork: true)
        let plan = boundary.plan([request])

        #expect(plan.acceptedRequests.isEmpty)
        #expect(plan.issues.contains { $0.kind == .networkRequestedInNoNetworkMode })
        #expect(plan.diagnostics.networkWorkStarted == false)
    }

    @Test("No DB request allowed in no-DB test mode")
    func noDBRequestAllowedInNoDBTestMode() {
        let request = resolveRequest(kind: .profile, requestsDBWork: true)
        let plan = boundary.plan([request])

        #expect(plan.acceptedRequests.isEmpty)
        #expect(plan.issues.contains { $0.kind == .dbRequestedInNoDBMode })
        #expect(plan.diagnostics.dbWorkStarted == false)
    }

    @Test("Invalid target kind returns typed issue")
    func invalidTargetKindReturnsTypedIssue() {
        let request = resolveRequest(kind: .unsupported)
        let plan = boundary.plan([request])

        #expect(plan.acceptedRequests.isEmpty)
        #expect(plan.issues.contains { $0.kind == .unsupportedTargetKind })
    }

    @Test("Invalid target missing entry invalid scope production runtime and unsafe payload return typed issues")
    func invalidTargetMissingEntryInvalidScopeProductionRuntimeAndUnsafePayloadReturnTypedIssues() {
        let invalidTarget = resolveRequest(kind: .profile, isTargetValid: false)
        let missingEntry = resolveRequest(id: "missing-entry", kind: .profile, entryID: nil)
        let invalidScope = resolveRequest(id: "invalid-scope", kind: .profile, scope: .invalid)
        let invalidPriority = resolveRequest(id: "invalid-priority", kind: .profile, priority: .invalid)
        let readMarkerAdvance = resolveRequest(
            id: "read-marker",
            kind: .profile,
            attemptsReadMarkerAdvance: true
        )
        let productionHome = resolveRequest(
            id: "production-home",
            kind: .profile,
            requiresProductionHomeRuntime: true
        )
        let unsafePayload = resolveRequest(
            id: "unsafe-payload",
            kind: .profile,
            payloadPreview: "fixture " + "n" + "sec" + " material"
        )

        let plan = boundary.plan([
            invalidTarget,
            missingEntry,
            invalidScope,
            invalidPriority,
            readMarkerAdvance,
            productionHome,
            unsafePayload
        ])
        let kinds = Set(plan.issues.map(\.kind))

        #expect(kinds.isSuperset(of: [
            .invalidTarget,
            .missingTimelineEntryID,
            .invalidScope,
            .invalidPriority,
            .readMarkerAdvanceAttempted,
            .requiresProductionHomeRuntime,
            .unsafeSensitivePayload
        ]))
        #expect(plan.acceptedRequests.isEmpty)
    }

    @Test("Insert delete delayed resolve attempt returns typed issue")
    func insertDeleteDelayedResolveAttemptReturnsTypedIssue() {
        let id = TimelineEntryID(rawValue: "unexpected:insert")
        let request = resolveRequest(
            kind: .linkPreviewOGP,
            attemptedInsertedIDs: [id],
            attemptedDeletedIDs: [id]
        )
        let plan = boundary.plan([request])

        #expect(plan.acceptedRequests.isEmpty)
        #expect(plan.issues.contains { $0.kind == .insertDeleteAttemptedForDelayedResolve })
    }

    @Test("Result insert delete mutation is rejected and not exposed")
    func resultInsertDeleteMutationIsRejectedAndNotExposed() throws {
        let pair = try viewStatePair(for: try fixture(named: "ogp_pending_to_resolved"))
        var after = pair.after
        after.diagnostics.insertedIDs = [after.id]
        let request = resolveRequest(kind: .linkPreviewOGP, entryID: after.id)
        let result = boundary.result(
            for: request,
            before: pair.before,
            after: after,
            existingIDs: [after.id]
        )

        #expect(result.state == .blocked)
        #expect(result.applyExpectation == nil)
        #expect(result.issues.contains { $0.kind == .insertDeleteAttemptedForDelayedResolve })
        #expect(result.diagnostics.pendingNewInserted == false)
    }

    @Test("Fake boundary scripted results are deterministic")
    func fakeBoundaryScriptedResultsAreDeterministic() throws {
        let pair = try viewStatePair(for: try fixture(named: "ogp_pending_to_resolved"))
        let request = resolveRequest(kind: .linkPreviewOGP, entryID: pair.after.id)
        let fake = FakeResolveCoordinatorBoundary(scriptedResults: [request.id: .resolved])

        let first = fake.result(for: request, before: pair.before, after: pair.after, existingIDs: [pair.after.id])
        let second = fake.result(for: request, before: pair.before, after: pair.after, existingIDs: [pair.after.id])

        #expect(first == second)
        #expect(first.state == .resolved)
        #expect(first.diagnostics.visibleRowResolveCount == 1)
    }

    @Test("Models are Codable Equatable and Sendable where appropriate")
    func modelsAreCodableEquatableAndSendableWhereAppropriate() throws {
        assertSendable(ResolveRequestID.self)
        assertSendable(ResolveTarget.self)
        assertSendable(ResolveTargetKind.self)
        assertSendable(ResolveScope.self)
        assertSendable(ResolvePriority.self)
        assertSendable(ResolveRequest.self)
        assertSendable(ResolveResult.self)
        assertSendable(ResolveFailure.self)
        assertSendable(ResolveCoordinatorBoundaryIssue.self)
        assertSendable(ResolveCoordinatorBoundaryDiagnostics.self)
        assertSendable(ResolveCoordinatorBoundaryPlan.self)
        assertSendable(FakeResolveCoordinatorBoundary.self)

        let request = resolveRequest(kind: .profile)
        let plan = boundary.plan([request])
        let acceptance = try resolveAcceptance(
            named: "profile_missing_to_resolved_headerOnly",
            kind: .profile,
            scriptedResult: .resolved
        )

        try assertCodableRoundTrip(request.id)
        try assertCodableRoundTrip(request.target)
        try assertCodableRoundTrip(request)
        try assertCodableRoundTrip(plan)
        try assertCodableRoundTrip(acceptance.result)
        try assertCodableRoundTrip(FakeResolveCoordinatorBoundary(scriptedResults: [request.id: .resolved]))
    }

    private func resolveAcceptance(
        named name: String,
        kind: ResolveTargetKind,
        scriptedResult: FakeResolveCoordinatorBoundary.ScriptedResult
    ) throws -> ResolveBoundaryAcceptance {
        let pair = try viewStatePair(for: try fixture(named: name))
        let request = resolveRequest(kind: kind, entryID: pair.after.id)
        let fake = FakeResolveCoordinatorBoundary(scriptedResults: [request.id: scriptedResult])
        let result = fake.result(
            for: request,
            before: pair.before,
            after: pair.after,
            existingIDs: [pair.after.id]
        )

        #expect(result.issues.isEmpty, "Unexpected result issues for \(name): \(result.issues)")
        return ResolveBoundaryAcceptance(
            before: pair.before,
            after: pair.after,
            result: result
        )
    }

    private func assertReconfigure(
        _ result: ResolveResult,
        reason: ResolveApplyReason,
        entryID: TimelineEntryID
    ) {
        #expect(result.applyExpectation?.style == .reconfigure)
        #expect(result.applyExpectation?.reason == reason)
        #expect(result.applyExpectation?.reconfigureIntent?.mutationStyle == .reconfigure)
        #expect(result.applyExpectation?.reconfigureIntent?.entryIDs == [entryID])
        #expect(result.applyExpectation?.insertedIDs.isEmpty == true)
        #expect(result.applyExpectation?.deletedIDs.isEmpty == true)
        #expect(result.applyExpectation?.readMarkerChanged == false)
        #expect(result.applyExpectation?.requiresNetworkWork == false)
        #expect(result.applyExpectation?.requiresDBWork == false)
    }

    private func resolveRequest(
        id: String = "request",
        kind: ResolveTargetKind,
        scope: ResolveScope = .visibleRows,
        priority: ResolvePriority = .visibleRows,
        entryID: TimelineEntryID? = TimelineEntryID(rawValue: "home:resolve:entry"),
        isTargetValid: Bool = true,
        requestsNetworkWork: Bool = false,
        requestsDBWork: Bool = false,
        attemptedInsertedIDs: [TimelineEntryID] = [],
        attemptedDeletedIDs: [TimelineEntryID] = [],
        attemptsReadMarkerAdvance: Bool = false,
        requiresProductionHomeRuntime: Bool = false,
        payloadPreview: String? = nil
    ) -> ResolveRequest {
        ResolveRequest(
            id: ResolveRequestID(rawValue: id),
            target: ResolveTarget(
                kind: kind,
                entryID: entryID,
                isValid: isTargetValid,
                payloadPreview: payloadPreview
            ),
            scope: scope,
            priority: priority,
            requestsNetworkWork: requestsNetworkWork,
            requestsDBWork: requestsDBWork,
            attemptedInsertedIDs: attemptedInsertedIDs,
            attemptedDeletedIDs: attemptedDeletedIDs,
            attemptsReadMarkerAdvance: attemptsReadMarkerAdvance,
            requiresProductionHomeRuntime: requiresProductionHomeRuntime
        )
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
        let output = rowBoundary.project(TimelineRowProjectionInput(adapterOutput: adapterOutput))

        #expect(output.issues.isEmpty, "Unexpected row boundary issues for \(scenario.name): \(output.issues)")
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

    private func mappedViewState(for scenario: TimelineProjectionScenario) throws -> TimelineEntryViewState {
        let draft = try projectedDraft(for: scenario)
        return try mappedViewState(for: draft)
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

    private struct ResolveBoundaryAcceptance {
        var before: TimelineEntryViewState
        var after: TimelineEntryViewState
        var result: ResolveResult
    }
}
