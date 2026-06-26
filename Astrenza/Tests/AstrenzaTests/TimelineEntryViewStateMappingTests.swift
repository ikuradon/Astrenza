import DesignSystem
import Foundation
import Testing
@testable import Astrenza

@Suite("Timeline entry view state mapping")
struct TimelineEntryViewStateMappingTests {
    private let adapter = FixtureBackedTimelineProjectionAdapter()
    private let boundary = FixtureBackedTimelineRowProjectionBoundary()
    private let mapper = TimelineEntryViewStateMapper()
    private let scenarios = TimelineProjectionFixtureBuilder.allScenarios

    @Test("Every Phase 6.0 fixture maps through contract adapter boundary and view state")
    func everyPhase60FixtureMapsThroughFullPipelineToViewState() throws {
        var mappedCount = 0

        for scenario in scenarios {
            let draft = try projectedDraft(for: scenario)
            let output = mapper.map(TimelineEntryViewStateMappingInput(draft: draft))
            let viewState = try #require(output.viewState, "Missing view state for \(scenario.name)")

            #expect(output.issues.isEmpty, "Unexpected mapping issues for \(scenario.name): \(output.issues)")
            #expect(viewState.id == draft.id)
            #expect(viewState.itemKey == draft.itemKey)
            #expect(viewState.id.rawValue == draft.itemKey)
            #expect(viewState.sourceEventID == draft.sourceEventID)
            #expect(viewState.subjectEventID == draft.subjectEventID)
            #expect(viewState.sortKey.sortAt == draft.sortAt)
            #expect(viewState.sortKey.tieBreakID == draft.tieBreakID)
            #expect(viewState.reason == FeedItemReason(draft.feedItemReason))
            #expect(viewState.layoutContract == draft.layoutDecision.contract)
            #expect(viewState.visibility.includedInVisibleSnapshot == draft.visibilityDecision.includedInVisibleSnapshot)
            #expect(viewState.visibility.pendingNewVisible == draft.visibilityDecision.pendingNewVisible)
            #expect(viewState.visibility.keepsSourceNoteVisible == draft.fallback.keepsSourceNoteVisible)
            #expect(viewState.diagnostics.scenarioName == scenario.name)
            #expect(!viewState.diagnostics.readMarkerChanged)
            #expect(!viewState.diagnostics.requiresNetworkWork)
            #expect(!viewState.diagnostics.requiresDBWork)
            mappedCount += 1
        }

        #expect(mappedCount == TimelineProjectionFixtureBuilder.allScenarios.count)
    }

    @Test("View state preserves source subject identity and reconfigure-only delayed resolve")
    func viewStatePreservesIdentityAndReconfigureOnlyDelayedResolve() throws {
        for scenario in scenarios where scenario.hasDelayedResolveTransition {
            let draft = try projectedDraft(for: scenario)
            let viewState = try mappedViewState(for: draft)

            #expect(viewState.id == draft.mutationExpectation.initialEntryID)
            #expect(viewState.id == draft.mutationExpectation.finalEntryID)
            #expect(viewState.diagnostics.mutationStyle == .reconfigure)
            #expect(viewState.diagnostics.delayedResolveMutationStyle == .neverDeleteInsertForDelayedResolve)
            #expect(viewState.diagnostics.reconfigureEntryIDs == [viewState.id])
            #expect(viewState.diagnostics.insertedIDs.isEmpty)
            #expect(viewState.diagnostics.deletedIDs.isEmpty)
            #expect(!viewState.diagnostics.allowsDeleteInsertForDelayedResolve)
            #expect(!viewState.diagnostics.readMarkerChanged)
            #expect(!viewState.diagnostics.requiresNetworkWork)
            #expect(!viewState.diagnostics.requiresDBWork)
        }

        let repost = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "repost_target_pending_to_resolved")
        ))
        #expect(repost.sourceEventID != repost.subjectEventID)
        #expect(repost.subjectEventID != nil)
    }

    @Test("Resolve states map link media profile repost quote reply stats and publish placeholders")
    func resolveStatesMapRequiredRowStateModels() throws {
        let textOnly = try mappedViewState(for: projectedDraft(for: try fixture(named: "textOnly_author_visible")))
        #expect(textOnly.body.keepsSourceNoteVisible)
        #expect(textOnly.linkPreview == .absent)
        #expect(textOnly.media.isEmpty)
        #expect(textOnly.visibility.presentation == .visible)

        let ogpPending = try mappedViewState(for: linkPreviewDraft(
            from: try fixture(named: "ogp_pending_to_resolved"),
            state: .pending
        ))
        #expect(ogpPending.linkPreview == .pending)
        #expect(ogpPending.layoutContract.linkPreviewMode == .fixedCompactCard)

        let ogpResolved = try mappedViewState(for: projectedDraft(for: try fixture(named: "ogp_pending_to_resolved")))
        guard case .resolved(let resolvedPreview) = ogpResolved.linkPreview else {
            Issue.record("Expected resolved link preview")
            return
        }
        #expect(resolvedPreview.mode == .fixedCompactCard)

        let ogpFailed = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "ogp_pending_to_failed_urlOnlyFallback")
        ))
        guard case .failed(let linkFailure) = ogpFailed.linkPreview else {
            Issue.record("Expected failed link preview")
            return
        }
        #expect(linkFailure.fallbackMode == .urlOnly)
        #expect(ogpFailed.body.keepsSourceNoteVisible)

        let mediaResolved = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "media_imeta_present_aspect_reserved")
        ))
        let resolvedMediaState = try #require(mediaResolved.media.first)
        guard case .resolved(let resolvedMedia) = resolvedMediaState else {
            Issue.record("Expected resolved media")
            return
        }
        #expect(resolvedMedia.reservedAspectRatio == 4.0 / 3.0)
        #expect(resolvedMedia.reservedHeight == 240)

        let mediaPlaceholder = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "media_imeta_absent_fixed_placeholder")
        ))
        let failedMediaState = try #require(mediaPlaceholder.media.first)
        guard case .failed(let mediaFailure) = failedMediaState else {
            Issue.record("Expected failed placeholder media")
            return
        }
        #expect(mediaFailure.fallbackMode == .fixedMediaPlaceholder)
        #expect(mediaFailure.reservedAspectRatio == 16.0 / 9.0)
        #expect(mediaFailure.reservedHeight == 180)

        let profileFallback = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "profile_missing_to_failed_npubFallback")
        ))
        guard case .resolved(let fallbackProfile) = profileFallback.author else {
            Issue.record("Expected fallback profile")
            return
        }
        #expect(fallbackProfile.isFallback)
        #expect(fallbackProfile.avatar == .defaultAvatar)

        let profileResolved = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "profile_missing_to_resolved_headerOnly")
        ))
        guard case .resolved(let resolvedProfile) = profileResolved.author else {
            Issue.record("Expected resolved profile")
            return
        }
        #expect(!resolvedProfile.isFallback)
        #expect(profileResolved.diagnostics.reconfigureEntryIDs == [profileResolved.id])

        let repost = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "repost_target_pending_to_resolved")
        ))
        guard case .resolved(let resolvedRepost) = repost.repost else {
            Issue.record("Expected resolved repost")
            return
        }
        #expect(resolvedRepost.itemKey == repost.itemKey)

        let deletedRepost = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "repost_target_deleted_unavailable")
        ))
        guard case .unavailable(let repostUnavailable) = deletedRepost.repost else {
            Issue.record("Expected unavailable repost")
            return
        }
        #expect(repostUnavailable.itemKey == deletedRepost.itemKey)

        let quote = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "quote_target_pending_to_resolved")
        ))
        #expect(quote.quote != nil)
        #expect(quote.replyContext == nil)
        #expect(!quote.diagnostics.quoteCreatesReplyRelation)

        let reply = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "reply_parent_pending_to_resolved_headerOnly")
        ))
        #expect(reply.replyContext != nil)
        #expect(reply.layoutContract.replyHeaderMode == .oneLine)
        #expect(!reply.layoutContract.allowsInlineParentPreviewInHome)

        let stats = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "stats_resolving_to_resolved_reconfigureOnly")
        ))
        #expect(stats.stats != .absent)
        #expect(stats.id == stats.diagnostics.initialEntryID)
        #expect(!stats.diagnostics.requiresNetworkWork)

        let publish = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange")
        ))
        #expect(publish.publishState == .placeholder)
        #expect(!publish.diagnostics.requiresNetworkWork)
        #expect(!publish.diagnostics.requiresDBWork)
    }

    @Test("Fallback visibility pending new and layout contracts are preserved")
    func fallbackVisibilityPendingNewAndLayoutContractsArePreserved() throws {
        for name in [
            "ogp_pending_to_failed_urlOnlyFallback",
            "media_imeta_absent_fixed_placeholder",
            "profile_missing_to_failed_npubFallback",
            "repost_target_deleted_unavailable",
            "quote_target_blocked_unavailableCard"
        ] {
            let viewState = try mappedViewState(for: projectedDraft(for: try fixture(named: name)))

            #expect(viewState.visibility.keepsSourceNoteVisible, "Fallback hides source note for \(name)")
            #expect(!viewState.visibility.removesSourceNote, "Visibility removes source note for \(name)")
        }

        let deleted = try mappedViewState(for: projectedDraft(for: try fixture(named: "deleted_target_placeholder")))
        #expect(deleted.visibility.presentation == .deletedPlaceholder)
        #expect(deleted.visibility.unavailableReason == .deleted)

        let muted = try mappedViewState(for: projectedDraft(for: try fixture(named: "muted_target_collapsed_while_visible")))
        #expect(muted.visibility.presentation == .collapsed)
        #expect(muted.visibility.reason == .muted)
        #expect(muted.visibility.includedInVisibleSnapshot)

        let pendingNew = try mappedViewState(for: projectedDraft(
            for: try fixture(named: "pending_new_not_visible_until_user_action")
        ))
        #expect(!pendingNew.visibility.includedInVisibleSnapshot)
        #expect(!pendingNew.visibility.pendingNewVisible)
        #expect(!pendingNew.diagnostics.pendingNewVisible)

        for scenario in scenarios where scenario.hasDelayedResolveTransition {
            let viewState = try mappedViewState(for: projectedDraft(for: scenario))

            guard viewState.layoutContract.rowKind == .home,
                  viewState.visibility.includedInVisibleSnapshot
            else {
                continue
            }

            #expect(!viewState.layoutContract.canChangeHeightAfterFirstDisplay)
        }

        let media = try mappedViewState(for: projectedDraft(for: try fixture(named: "media_imeta_present_aspect_reserved")))
        #expect(media.layoutContract.reservedMediaAspectRatio == 4.0 / 3.0)
        #expect(media.layoutContract.reservedMediaHeight == 240)

        let linkPreview = try mappedViewState(for: projectedDraft(for: try fixture(named: "ogp_pending_to_resolved")))
        #expect(linkPreview.layoutContract.linkPreviewMode == .fixedCompactCard)
    }

    @Test("View state mapper models are codable equatable and sendable")
    func viewStateMapperModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineEntryViewState.self)
        assertSendable(ResolveState<ResolvedProfile>.self)
        assertSendable(ResolveFailure.self)
        assertSendable(VisibilityReason.self)
        assertSendable(UnavailableReason.self)
        assertSendable(TimelineSortKey.self)
        assertSendable(FeedItemReason.self)
        assertSendable(TimelineVisibilityState.self)
        assertSendable(ResolvedProfile.self)
        assertSendable(ResolvedBodyText.self)
        assertSendable(ResolvedMedia.self)
        assertSendable(ResolvedLinkPreview.self)
        assertSendable(ResolvedRepost.self)
        assertSendable(ResolvedQuote.self)
        assertSendable(ResolvedReplyContext.self)
        assertSendable(ResolvedStats.self)
        assertSendable(PublishState.self)
        assertSendable(TimelineEntryViewStateDiagnostics.self)
        assertSendable(TimelineEntryViewStateMappingInput.self)
        assertSendable(TimelineEntryViewStateMappingOutput.self)
        assertSendable(TimelineEntryViewStateMappingIssue.self)

        let draft = try projectedDraft(for: try fixture(named: "ogp_pending_to_resolved"))
        let input = TimelineEntryViewStateMappingInput(draft: draft)
        let output = mapper.map(input)
        let viewState = try #require(output.viewState)

        try assertCodableRoundTrip(input)
        try assertCodableRoundTrip(output)
        try assertCodableRoundTrip(viewState)
        try assertCodableRoundTrip(viewState.diagnostics)
    }

    @Test("Invalid row projection drafts produce typed mapping issues")
    func invalidRowProjectionDraftsProduceTypedMappingIssues() throws {
        var unstableIdentity = try projectedDraft(for: try fixture(named: "ogp_pending_to_resolved"))
        unstableIdentity.itemKey += ":different"
        expectIssue(.unstableIdentity, in: unstableIdentity)

        var sourceMismatch = try projectedDraft(for: try fixture(named: "textOnly_author_visible"))
        sourceMismatch.sourceEventID = EventID(hex: String(repeating: "9", count: 64))
        expectIssue(.sourceEventMismatch, in: sourceMismatch)

        var delayedResolveSnapshot = try projectedDraft(for: try fixture(named: "media_imeta_present_aspect_reserved"))
        delayedResolveSnapshot.mutationExpectation.style = .none
        expectIssue(.delayedResolveMustReconfigure, in: delayedResolveSnapshot)

        var deleteInsert = try projectedDraft(for: try fixture(named: "profile_missing_to_resolved_headerOnly"))
        deleteInsert.mutationExpectation.deletedIDs = [deleteInsert.id]
        expectIssue(.deleteInsertMutationIntroduced, in: deleteInsert)

        var readMarker = try projectedDraft(for: try fixture(named: "profile_missing_to_resolved_headerOnly"))
        readMarker.mutationExpectation.readMarkerChanged = true
        expectIssue(.readMarkerChanged, in: readMarker)

        var network = try projectedDraft(for: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange"))
        network.diagnostics.requiresNetworkWork = true
        expectIssue(.requiresNetworkWork, in: network)

        var database = try projectedDraft(for: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange"))
        database.diagnostics.requiresDBWork = true
        expectIssue(.requiresDBWork, in: database)

        var missingLayoutContract = try projectedDraft(for: try fixture(named: "textOnly_author_visible"))
        missingLayoutContract.layoutDecision.hasLayoutContract = false
        expectIssue(.missingLayoutContract, in: missingLayoutContract)

        var pendingNew = try projectedDraft(for: try fixture(named: "pending_new_not_visible_until_user_action"))
        pendingNew.visibilityDecision.pendingNewVisible = true
        pendingNew.visibilityDecision.includedInVisibleSnapshot = true
        expectIssue(.pendingNewVisibilityRequiresExplicitUserAction, in: pendingNew)

        var quoteReply = try projectedDraft(for: try fixture(named: "quote_target_pending_to_resolved"))
        quoteReply.mutationExpectation.quoteCreatesReplyRelation = true
        expectIssue(.quoteTargetBecameReplyParent, in: quoteReply)

        var replyInline = try projectedDraft(for: try fixture(named: "reply_parent_pending_to_resolved_headerOnly"))
        replyInline.layoutDecision.contract.replyHeaderMode = .inlineParentInDetail
        replyInline.layoutDecision.contract.allowsInlineParentPreviewInHome = true
        expectIssue(.homeReplyParentMustBeHeaderOnly, in: replyInline)
    }

    private func projectedDraft(for scenario: TimelineProjectionScenario) throws -> TimelineProjectedRowDraft {
        let adapterOutput = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
        let output = boundary.project(TimelineRowProjectionInput(adapterOutput: adapterOutput))

        #expect(output.issues.isEmpty, "Unexpected boundary issues for \(scenario.name): \(output.issues)")
        return try #require(output.draft, "Missing draft for \(scenario.name)")
    }

    private func linkPreviewDraft(
        from scenario: TimelineProjectionScenario,
        state: TimelineProjectionResolveState
    ) throws -> TimelineProjectedRowDraft {
        var draft = try projectedDraft(for: scenario)
        draft.resolveExpectations = [
            TimelineResolveExpectation(
                target: .linkPreviewOGP,
                initialState: state,
                expectedState: state
            )
        ]
        draft.mutationExpectation = TimelineProjectionMutationExpectation(
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
        return draft
    }

    private func mappedViewState(for draft: TimelineProjectedRowDraft) throws -> TimelineEntryViewState {
        let output = mapper.map(TimelineEntryViewStateMappingInput(draft: draft))

        #expect(output.issues.isEmpty, "Unexpected mapping issues for \(draft.diagnostics.scenarioName): \(output.issues)")
        return try #require(output.viewState, "Missing view state for \(draft.diagnostics.scenarioName)")
    }

    private func fixture(named name: String) throws -> TimelineProjectionScenario {
        try #require(TimelineProjectionFixtureBuilder.scenario(named: name))
    }

    private func expectIssue(
        _ kind: TimelineEntryViewStateMappingIssue.Kind,
        in draft: TimelineProjectedRowDraft
    ) {
        let output = mapper.map(TimelineEntryViewStateMappingInput(draft: draft))

        #expect(output.viewState == nil)
        #expect(output.issues.contains { $0.kind == kind }, "Expected \(kind), got \(output.issues)")
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }
}
