import DesignSystem
import Foundation

struct TimelineEntryViewStateMappingInput: Equatable, Codable, Sendable {
    var draft: TimelineProjectedRowDraft
    var userActionContext: TimelineRowProjectionUserActionContext

    init(
        draft: TimelineProjectedRowDraft,
        userActionContext: TimelineRowProjectionUserActionContext = TimelineRowProjectionUserActionContext()
    ) {
        self.draft = draft
        self.userActionContext = userActionContext
    }
}

struct TimelineEntryViewStateMappingOutput: Equatable, Codable, Sendable {
    var viewState: TimelineEntryViewState?
    var diagnostics: TimelineEntryViewStateDiagnostics
    var issues: [TimelineEntryViewStateMappingIssue]

    var isMapped: Bool {
        viewState != nil && issues.isEmpty
    }
}

struct TimelineEntryViewStateMappingIssue: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case unstableIdentity
        case sourceEventMismatch
        case sortKeyMismatch
        case missingLayoutContract
        case delayedResolveMustReconfigure
        case deleteInsertMutationIntroduced
        case readMarkerChanged
        case requiresNetworkWork
        case requiresDBWork
        case pendingNewVisibilityRequiresExplicitUserAction
        case quoteTargetBecameReplyParent
        case homeReplyParentMustBeHeaderOnly
        case homeVisibleResolveMustNotChangeHeight
    }

    var scenarioName: String
    var kind: Kind
}

struct TimelineEntryViewStateMapper: Sendable {
    func map(_ input: TimelineEntryViewStateMappingInput) -> TimelineEntryViewStateMappingOutput {
        let draft = input.draft
        let diagnostics = makeDiagnostics(from: draft)
        let issues = validate(input)

        guard issues.isEmpty else {
            return TimelineEntryViewStateMappingOutput(
                viewState: nil,
                diagnostics: diagnostics,
                issues: issues
            )
        }

        let viewState = TimelineEntryViewState(
            id: draft.id,
            itemKey: draft.itemKey,
            sourceEventID: draft.sourceEventID,
            subjectEventID: draft.subjectEventID,
            sortKey: TimelineSortKey(sortAt: draft.sortAt, tieBreakID: draft.tieBreakID),
            reason: FeedItemReason(draft.feedItemReason),
            author: makeProfileState(from: draft),
            body: makeBody(from: draft),
            media: makeMediaStates(from: draft),
            linkPreview: makeLinkPreviewState(from: draft),
            repost: makeRepostState(from: draft),
            quote: makeQuoteState(from: draft),
            replyContext: makeReplyContextState(from: draft),
            stats: makeStatsState(from: draft),
            visibility: makeVisibilityState(from: draft),
            publishState: makePublishState(from: draft),
            layoutContract: draft.layoutDecision.contract,
            diagnostics: diagnostics
        )

        return TimelineEntryViewStateMappingOutput(
            viewState: viewState,
            diagnostics: diagnostics,
            issues: []
        )
    }

    private func validate(_ input: TimelineEntryViewStateMappingInput) -> [TimelineEntryViewStateMappingIssue] {
        let draft = input.draft
        var issues: [TimelineEntryViewStateMappingIssue] = []

        if draft.id.rawValue != draft.itemKey
            || draft.mutationExpectation.initialEntryID != draft.id
            || draft.mutationExpectation.finalEntryID != draft.id {
            issues.append(issue(.unstableIdentity, in: draft))
        }

        if let entrySourceEventID = draft.id.sourceEventID,
           entrySourceEventID != draft.sourceEventID {
            issues.append(issue(.sourceEventMismatch, in: draft))
        }

        if let entrySortAt = draft.id.sortAt, entrySortAt != draft.sortAt {
            issues.append(issue(.sortKeyMismatch, in: draft))
        }

        if let entryTieBreakID = draft.id.tieBreakID, entryTieBreakID != draft.tieBreakID {
            issues.append(issue(.sortKeyMismatch, in: draft))
        }

        if !draft.layoutDecision.hasLayoutContract {
            issues.append(issue(.missingLayoutContract, in: draft))
        }

        let explicitPendingNewInsert = isExplicitPendingNewInsert(
            draft: draft,
            userActionContext: input.userActionContext
        )
        if draft.visibilityDecision.pendingNewVisible && !explicitPendingNewInsert {
            issues.append(issue(.pendingNewVisibilityRequiresExplicitUserAction, in: draft))
        }

        if draft.mutationExpectation.readMarkerChanged || draft.diagnostics.readMarkerChanged {
            issues.append(issue(.readMarkerChanged, in: draft))
        }

        if draft.diagnostics.requiresNetworkWork
            || draft.resolveExpectations.contains(where: \.requiresRemoteWork) {
            issues.append(issue(.requiresNetworkWork, in: draft))
        }

        if draft.diagnostics.requiresDBWork {
            issues.append(issue(.requiresDBWork, in: draft))
        }

        if !draft.mutationExpectation.deletedIDs.isEmpty
            || (!draft.mutationExpectation.insertedIDs.isEmpty && !explicitPendingNewInsert) {
            issues.append(issue(.deleteInsertMutationIntroduced, in: draft))
        }

        if draft.mutationExpectation.quoteCreatesReplyRelation
            && draft.resolveExpectations.contains(where: { $0.target == .quoteTarget }) {
            issues.append(issue(.quoteTargetBecameReplyParent, in: draft))
        }

        if hasDelayedResolveTransition(draft) {
            if draft.mutationExpectation.style != .reconfigure
                || draft.mutationExpectation.delayedResolveStyle != .neverDeleteInsertForDelayedResolve {
                issues.append(issue(.delayedResolveMustReconfigure, in: draft))
            }

            if !draft.mutationExpectation.insertedIDs.isEmpty
                || !draft.mutationExpectation.deletedIDs.isEmpty
                || draft.mutationExpectation.allowsDeleteInsertForDelayedResolve {
                issues.append(issue(.deleteInsertMutationIntroduced, in: draft))
            }
        }

        if draft.resolveExpectations.contains(where: { $0.target == .replyParentRoot })
            && draft.layoutDecision.contract.rowKind == .home {
            if draft.layoutDecision.contract.replyHeaderMode != .oneLine
                || draft.layoutDecision.contract.allowsInlineParentPreviewInHome {
                issues.append(issue(.homeReplyParentMustBeHeaderOnly, in: draft))
            }
        }

        if hasDelayedResolveTransition(draft)
            && draft.layoutDecision.contract.rowKind == .home
            && draft.visibilityDecision.includedInVisibleSnapshot
            && !draft.layoutDecision.isDetailOnly {
            if draft.layoutDecision.contract.canChangeHeightAfterFirstDisplay
                || !draft.layoutDecision.noUnlimitedHeightGrowthAfterResolve {
                issues.append(issue(.homeVisibleResolveMustNotChangeHeight, in: draft))
            }
        }

        return issues
    }

    private func makeDiagnostics(from draft: TimelineProjectedRowDraft) -> TimelineEntryViewStateDiagnostics {
        TimelineEntryViewStateDiagnostics(
            scenarioName: draft.diagnostics.scenarioName,
            initialEntryID: draft.mutationExpectation.initialEntryID,
            finalEntryID: draft.mutationExpectation.finalEntryID,
            mutationStyle: draft.mutationExpectation.style,
            delayedResolveMutationStyle: draft.mutationExpectation.delayedResolveStyle,
            reconfigureEntryIDs: draft.mutationExpectation.style == .reconfigure ? [draft.id] : [],
            insertedIDs: draft.mutationExpectation.insertedIDs,
            deletedIDs: draft.mutationExpectation.deletedIDs,
            allowsDeleteInsertForDelayedResolve: draft.mutationExpectation.allowsDeleteInsertForDelayedResolve,
            readMarkerChanged: draft.mutationExpectation.readMarkerChanged || draft.diagnostics.readMarkerChanged,
            pendingNewVisible: draft.visibilityDecision.pendingNewVisible || draft.diagnostics.pendingNewVisible,
            requiresNetworkWork: draft.diagnostics.requiresNetworkWork
                || draft.resolveExpectations.contains(where: \.requiresRemoteWork),
            requiresDBWork: draft.diagnostics.requiresDBWork,
            quoteCreatesReplyRelation: draft.mutationExpectation.quoteCreatesReplyRelation,
            fallbackMode: draft.fallback.mode,
            keepsSourceNoteVisible: draft.fallback.keepsSourceNoteVisible
        )
    }

    private func makeProfileState(from draft: TimelineProjectedRowDraft) -> ResolveState<ResolvedProfile> {
        let expectation = resolveExpectation(.profile, in: draft)
        let resolved = expectation?.expectedState == .resolved
        return .resolved(ResolvedProfile(
            pubkeyFallback: fallbackNpub(from: draft.sourceEventID),
            displayName: resolved ? "Resolved Profile" : fallbackNpub(from: draft.sourceEventID),
            handle: resolved ? "resolved.example" : fallbackNpub(from: draft.sourceEventID),
            avatar: resolved ? .remoteURL("https://example.invalid/avatar/\(draft.itemKey)") : .defaultAvatar,
            isFallback: !resolved
        ))
    }

    private func makeBody(from draft: TimelineProjectedRowDraft) -> ResolvedBodyText {
        ResolvedBodyText(
            text: "Offline fixture note \(draft.itemKey)",
            keepsSourceNoteVisible: draft.fallback.keepsSourceNoteVisible && !draft.visibilityDecision.removesSourceNote,
            mentionRendering: draft.layoutDecision.contract.bodyMentionRendering
        )
    }

    private func makeMediaStates(from draft: TimelineProjectedRowDraft) -> [ResolveState<ResolvedMedia>] {
        guard let expectation = resolveExpectation(.media, in: draft) else {
            return []
        }

        let media = ResolvedMedia(
            id: "\(draft.itemKey):media",
            reservedAspectRatio: draft.layoutDecision.contract.reservedMediaAspectRatio,
            reservedHeight: draft.layoutDecision.contract.reservedMediaHeight,
            isPlaceholder: expectation.expectedState != .resolved
        )
        return [
            resolveState(
                expectation: expectation,
                target: .media,
                value: media,
                draft: draft
            )
        ]
    }

    private func makeLinkPreviewState(from draft: TimelineProjectedRowDraft) -> ResolveState<ResolvedLinkPreview> {
        guard let expectation = resolveExpectation(.linkPreviewOGP, in: draft) else {
            return .absent
        }

        return resolveState(
            expectation: expectation,
            target: .linkPreviewOGP,
            value: ResolvedLinkPreview(
                urlString: "https://example.invalid/\(draft.itemKey)",
                title: "Offline link preview",
                mode: draft.layoutDecision.contract.linkPreviewMode,
                fallbackMode: draft.fallback.mode
            ),
            draft: draft
        )
    }

    private func makeRepostState(from draft: TimelineProjectedRowDraft) -> ResolveState<ResolvedRepost>? {
        guard let expectation = resolveExpectation(.repostTarget, in: draft) else {
            return nil
        }

        return resolveState(
            expectation: expectation,
            target: .repostTarget,
            value: ResolvedRepost(
                itemKey: draft.itemKey,
                sourceEventID: draft.sourceEventID,
                subjectEventID: draft.subjectEventID,
                isPlaceholder: expectation.expectedState != .resolved
            ),
            draft: draft
        )
    }

    private func makeQuoteState(from draft: TimelineProjectedRowDraft) -> ResolveState<ResolvedQuote>? {
        guard let expectation = resolveExpectation(.quoteTarget, in: draft) else {
            return nil
        }

        return resolveState(
            expectation: expectation,
            target: .quoteTarget,
            value: ResolvedQuote(
                itemKey: draft.itemKey,
                subjectEventID: draft.subjectEventID,
                mode: draft.layoutDecision.contract.quoteMode,
                maxLines: draft.layoutDecision.contract.maxQuoteLines,
                createsReplyRelation: false
            ),
            draft: draft
        )
    }

    private func makeReplyContextState(from draft: TimelineProjectedRowDraft) -> ResolveState<ResolvedReplyContext>? {
        guard let expectation = resolveExpectation(.replyParentRoot, in: draft) else {
            return nil
        }

        return resolveState(
            expectation: expectation,
            target: .replyParentRoot,
            value: ResolvedReplyContext(
                parentEventID: draft.subjectEventID,
                mode: draft.layoutDecision.contract.replyHeaderMode,
                allowsInlineParentPreviewInHome: draft.layoutDecision.contract.allowsInlineParentPreviewInHome
            ),
            draft: draft
        )
    }

    private func makeStatsState(from draft: TimelineProjectedRowDraft) -> ResolveState<ResolvedStats> {
        guard let expectation = resolveExpectation(.stats, in: draft) else {
            return .absent
        }

        return resolveState(
            expectation: expectation,
            target: .stats,
            value: ResolvedStats(replyCount: 0, repostCount: 0, reactionCount: 0),
            draft: draft
        )
    }

    private func makePublishState(from draft: TimelineProjectedRowDraft) -> PublishState? {
        guard resolveExpectation(.publishStatePlaceholder, in: draft) != nil else {
            return nil
        }

        return .placeholder
    }

    private func makeVisibilityState(from draft: TimelineProjectedRowDraft) -> TimelineVisibilityState {
        let visibility = draft.visibilityDecision
        return TimelineVisibilityState(
            mode: visibility.mode,
            presentation: presentation(for: visibility, fallback: draft.fallback),
            reason: visibilityReason(for: visibility, fallback: draft.fallback),
            unavailableReason: unavailableReason(for: visibility, fallback: draft.fallback),
            includedInVisibleSnapshot: visibility.includedInVisibleSnapshot,
            pendingNewVisible: visibility.pendingNewVisible,
            keepsSourceNoteVisible: draft.fallback.keepsSourceNoteVisible,
            removesSourceNote: visibility.removesSourceNote,
            fallbackMode: draft.fallback.mode
        )
    }

    private func resolveState<Value: Codable & Equatable & Sendable>(
        expectation: TimelineResolveExpectation,
        target: TimelineDelayedResolveTarget,
        value: Value,
        draft: TimelineProjectedRowDraft
    ) -> ResolveState<Value> {
        switch expectation.expectedState {
        case .absent:
            .absent
        case .pending:
            .pending
        case .resolving:
            .resolving
        case .resolved:
            .resolved(value)
        case .failed:
            .failed(resolveFailure(target: target, draft: draft))
        case .blocked:
            .blocked(.blocked)
        case .unavailable:
            .unavailable(
                unavailableReason(for: draft.visibilityDecision, fallback: draft.fallback, itemKey: draft.itemKey)
                    ?? UnavailableReason(kind: .unavailable, itemKey: draft.itemKey, fallbackMode: draft.fallback.mode)
            )
        }
    }

    private func resolveFailure(
        target: TimelineDelayedResolveTarget,
        draft: TimelineProjectedRowDraft
    ) -> ResolveFailure {
        ResolveFailure(
            target: target,
            fallbackMode: draft.fallback.mode,
            keepsSourceNoteVisible: draft.fallback.keepsSourceNoteVisible,
            message: "Offline \(target.rawValue) fallback",
            reservedAspectRatio: draft.layoutDecision.contract.reservedMediaAspectRatio,
            reservedHeight: draft.layoutDecision.contract.reservedMediaHeight
        )
    }

    private func presentation(
        for visibility: TimelineProjectionVisibilityDecision,
        fallback: TimelineFallbackExpectation
    ) -> TimelineVisibilityPresentation {
        switch visibility.mode {
        case .visible:
            .visible
        case .collapsed:
            .collapsed
        case .deletedPlaceholder:
            .deletedPlaceholder
        case .mutedPlaceholder:
            .collapsed
        case .blockedPlaceholder:
            .blockedPlaceholder
        case .unavailablePlaceholder:
            fallback.mode == .deletedPlaceholder ? .deletedPlaceholder : .unavailablePlaceholder
        }
    }

    private func visibilityReason(
        for visibility: TimelineProjectionVisibilityDecision,
        fallback: TimelineFallbackExpectation
    ) -> VisibilityReason? {
        switch visibility.mode {
        case .visible:
            nil
        case .collapsed:
            .localFilter
        case .deletedPlaceholder:
            .deleted
        case .mutedPlaceholder:
            .muted
        case .blockedPlaceholder:
            .blocked
        case .unavailablePlaceholder:
            fallback.mode == .blockedPlaceholder ? .blocked : .unavailable
        }
    }

    private func unavailableReason(
        for visibility: TimelineProjectionVisibilityDecision,
        fallback: TimelineFallbackExpectation,
        itemKey: String? = nil
    ) -> UnavailableReason? {
        switch visibility.mode {
        case .deletedPlaceholder:
            .deleted
        case .blockedPlaceholder:
            UnavailableReason(kind: .blocked, itemKey: itemKey, fallbackMode: fallback.mode)
        case .mutedPlaceholder:
            UnavailableReason(kind: .muted, itemKey: itemKey, fallbackMode: fallback.mode)
        case .unavailablePlaceholder:
            fallback.mode == .deletedPlaceholder
                ? .deleted
                : UnavailableReason(kind: .targetUnavailable, itemKey: itemKey, fallbackMode: fallback.mode)
        case .visible, .collapsed:
            fallback.mode == .deletedPlaceholder ? .deleted : nil
        }
    }

    private func resolveExpectation(
        _ target: TimelineDelayedResolveTarget,
        in draft: TimelineProjectedRowDraft
    ) -> TimelineResolveExpectation? {
        draft.resolveExpectations.first { $0.target == target }
    }

    private func hasDelayedResolveTransition(_ draft: TimelineProjectedRowDraft) -> Bool {
        draft.resolveExpectations.contains { $0.isDelayedResolveTransition }
    }

    private func isExplicitPendingNewInsert(
        draft: TimelineProjectedRowDraft,
        userActionContext: TimelineRowProjectionUserActionContext
    ) -> Bool {
        draft.mutationExpectation.style == .insertOnlyForExplicitUserPendingNewAction
            && draft.visibilityDecision.pendingNewVisible
            && userActionContext.allowsPendingNewVisibility
            && userActionContext.pendingNewEntryIDs.contains(draft.id)
    }

    private func fallbackNpub(from eventID: EventID) -> String {
        "npub:" + String(eventID.hex.prefix(12))
    }

    private func issue(
        _ kind: TimelineEntryViewStateMappingIssue.Kind,
        in draft: TimelineProjectedRowDraft
    ) -> TimelineEntryViewStateMappingIssue {
        TimelineEntryViewStateMappingIssue(
            scenarioName: draft.diagnostics.scenarioName,
            kind: kind
        )
    }
}
