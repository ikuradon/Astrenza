import Foundation

struct TimelineResolveApplyUserAction: Equatable, Codable, Sendable {
    var pendingNewEntryIDs: [TimelineEntryID]
    var allowsPendingNewInsertion: Bool

    init(
        pendingNewEntryIDs: [TimelineEntryID] = [],
        allowsPendingNewInsertion: Bool = false
    ) {
        self.pendingNewEntryIDs = pendingNewEntryIDs
        self.allowsPendingNewInsertion = allowsPendingNewInsertion
    }

    func allowsInsertion(of entryID: TimelineEntryID) -> Bool {
        allowsPendingNewInsertion && pendingNewEntryIDs.contains(entryID)
    }
}

struct TimelineResolveApplyExpectationIssue: Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case identityChanged
        case readMarkerChanged
        case requiresNetworkWork
        case requiresDBWork
        case delayedResolveMustReconfigure
        case deleteInsertMutationIntroduced
        case pendingNewInsertRequiresExplicitUserAction
        case failedResolveRemovedSourceNote
        case quoteTargetBecameReplyParent
        case replyParentMustRemainHeaderOnly
        case homeVisibleResolveCanChangeHeight
    }

    var scenarioName: String
    var kind: Kind
}

struct TimelineResolveApplyExpectation: Equatable, Codable, Sendable {
    enum Style: String, Codable, Sendable {
        case none
        case reconfigure
        case insertOnlyForExplicitUserPendingNewAction
        case invalid
    }

    var style: Style
    var reason: ResolveApplyReason?
    var reconfigureIntent: TimelineResolveReconfigureIntent?
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
    var issues: [TimelineResolveApplyExpectationIssue]

    var isValid: Bool {
        issues.isEmpty
    }
}

struct TimelineResolveApplyExpectationBuilder: Sendable {
    func expectation(
        before initialViewState: TimelineEntryViewState?,
        after finalViewState: TimelineEntryViewState,
        existingIDs: [TimelineEntryID],
        userAction: TimelineResolveApplyUserAction = TimelineResolveApplyUserAction()
    ) -> TimelineResolveApplyExpectation {
        let diagnostics = finalViewState.diagnostics
        var issues: [TimelineResolveApplyExpectationIssue] = []
        appendValidationIssues(
            before: initialViewState,
            after: finalViewState,
            userAction: userAction,
            to: &issues
        )

        guard issues.isEmpty else {
            return TimelineResolveApplyExpectation(
                style: .invalid,
                reason: nil,
                reconfigureIntent: nil,
                insertedIDs: diagnostics.insertedIDs,
                deletedIDs: diagnostics.deletedIDs,
                readMarkerChanged: diagnostics.readMarkerChanged,
                requiresNetworkWork: diagnostics.requiresNetworkWork,
                requiresDBWork: diagnostics.requiresDBWork,
                issues: issues
            )
        }

        if isExplicitPendingNewInsert(finalViewState, userAction: userAction) {
            return TimelineResolveApplyExpectation(
                style: .insertOnlyForExplicitUserPendingNewAction,
                reason: nil,
                reconfigureIntent: nil,
                insertedIDs: [finalViewState.id],
                deletedIDs: [],
                readMarkerChanged: false,
                requiresNetworkWork: false,
                requiresDBWork: false,
                issues: []
            )
        }

        guard diagnostics.mutationStyle == .reconfigure else {
            return TimelineResolveApplyExpectation(
                style: .none,
                reason: nil,
                reconfigureIntent: nil,
                insertedIDs: [],
                deletedIDs: [],
                readMarkerChanged: false,
                requiresNetworkWork: false,
                requiresDBWork: false,
                issues: []
            )
        }

        let reason = resolveApplyReason(
            before: initialViewState,
            after: finalViewState
        )
        let intent = TimelineResolveApplyCoordinator().reconfigureIntent(
            resolvedIDs: [finalViewState.id],
            existingIDs: existingIDs,
            reason: reason
        )

        return TimelineResolveApplyExpectation(
            style: .reconfigure,
            reason: reason,
            reconfigureIntent: intent,
            insertedIDs: [],
            deletedIDs: [],
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresDBWork: false,
            issues: []
        )
    }

    private func appendValidationIssues(
        before initialViewState: TimelineEntryViewState?,
        after finalViewState: TimelineEntryViewState,
        userAction: TimelineResolveApplyUserAction,
        to issues: inout [TimelineResolveApplyExpectationIssue]
    ) {
        let diagnostics = finalViewState.diagnostics
        let hasDelayedResolve = !diagnostics.delayedResolveTargets.isEmpty
            || diagnostics.delayedResolveMutationStyle != nil

        if let initialViewState, initialViewState.id != finalViewState.id {
            append(.identityChanged, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        if finalViewState.id.rawValue != finalViewState.itemKey
            || diagnostics.initialEntryID != diagnostics.finalEntryID
            || diagnostics.finalEntryID != finalViewState.id {
            append(.identityChanged, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        if diagnostics.readMarkerChanged {
            append(.readMarkerChanged, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        if diagnostics.requiresNetworkWork {
            append(.requiresNetworkWork, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        if diagnostics.requiresDBWork {
            append(.requiresDBWork, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        let explicitPendingNewInsert = isExplicitPendingNewInsert(finalViewState, userAction: userAction)
        if finalViewState.visibility.pendingNewVisible && !explicitPendingNewInsert {
            append(.pendingNewInsertRequiresExplicitUserAction, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        if hasDelayedResolve {
            if diagnostics.mutationStyle != .reconfigure
                || diagnostics.delayedResolveMutationStyle != .neverDeleteInsertForDelayedResolve {
                append(.delayedResolveMustReconfigure, scenarioName: diagnostics.scenarioName, to: &issues)
            }

            if !diagnostics.insertedIDs.isEmpty
                || !diagnostics.deletedIDs.isEmpty
                || diagnostics.allowsDeleteInsertForDelayedResolve {
                append(.deleteInsertMutationIntroduced, scenarioName: diagnostics.scenarioName, to: &issues)
            }
        } else if (!diagnostics.insertedIDs.isEmpty || !diagnostics.deletedIDs.isEmpty)
            && !explicitPendingNewInsert {
            append(.deleteInsertMutationIntroduced, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        if !diagnostics.keepsSourceNoteVisible
            || !finalViewState.visibility.keepsSourceNoteVisible
            || finalViewState.visibility.removesSourceNote {
            append(.failedResolveRemovedSourceNote, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        if diagnostics.delayedResolveTargets.contains(.quoteTarget)
            && diagnostics.quoteCreatesReplyRelation {
            append(.quoteTargetBecameReplyParent, scenarioName: diagnostics.scenarioName, to: &issues)
        }

        if diagnostics.delayedResolveTargets.contains(.replyParentRoot)
            && finalViewState.layoutContract.rowKind == .home {
            if finalViewState.layoutContract.replyHeaderMode != .oneLine
                || finalViewState.layoutContract.allowsInlineParentPreviewInHome {
                append(.replyParentMustRemainHeaderOnly, scenarioName: diagnostics.scenarioName, to: &issues)
            }
        }

        if hasDelayedResolve
            && finalViewState.layoutContract.rowKind == .home
            && finalViewState.visibility.includedInVisibleSnapshot
            && finalViewState.layoutContract.canChangeHeightAfterFirstDisplay {
            append(.homeVisibleResolveCanChangeHeight, scenarioName: diagnostics.scenarioName, to: &issues)
        }
    }

    private func isExplicitPendingNewInsert(
        _ viewState: TimelineEntryViewState,
        userAction: TimelineResolveApplyUserAction
    ) -> Bool {
        viewState.visibility.pendingNewVisible
            && viewState.visibility.includedInVisibleSnapshot
            && userAction.allowsInsertion(of: viewState.id)
    }

    private func resolveApplyReason(
        before initialViewState: TimelineEntryViewState?,
        after finalViewState: TimelineEntryViewState
    ) -> ResolveApplyReason {
        if let target = finalViewState.diagnostics.delayedResolveTargets.first {
            return resolveApplyReason(for: target)
        }

        guard let initialViewState else {
            return fallbackResolveApplyReason(for: finalViewState)
        }

        if initialViewState.author != finalViewState.author {
            return .profile
        }
        if initialViewState.body != finalViewState.body {
            return .bodyMention
        }
        if initialViewState.media != finalViewState.media {
            return .media
        }
        if initialViewState.linkPreview != finalViewState.linkPreview {
            return .linkPreview
        }
        if initialViewState.repost != finalViewState.repost {
            return .repost
        }
        if initialViewState.quote != finalViewState.quote {
            return .quote
        }
        if initialViewState.replyContext != finalViewState.replyContext {
            return .replyParent
        }
        if initialViewState.stats != finalViewState.stats {
            return .stats
        }
        if initialViewState.publishState != finalViewState.publishState {
            return .publishStatePlaceholder
        }
        if initialViewState.visibility != finalViewState.visibility {
            return .visibility
        }

        return fallbackResolveApplyReason(for: finalViewState)
    }

    private func resolveApplyReason(for target: TimelineDelayedResolveTarget) -> ResolveApplyReason {
        switch target {
        case .profile:
            .profile
        case .bodyMention:
            .bodyMention
        case .media:
            .media
        case .linkPreviewOGP:
            .linkPreview
        case .repostTarget:
            .repost
        case .quoteTarget:
            .quote
        case .replyParentRoot:
            .replyParent
        case .stats:
            .stats
        case .publishStatePlaceholder:
            .publishStatePlaceholder
        }
    }

    private func fallbackResolveApplyReason(for viewState: TimelineEntryViewState) -> ResolveApplyReason {
        if !viewState.media.isEmpty {
            return .media
        }
        if viewState.linkPreview != .absent {
            return .linkPreview
        }
        if viewState.repost != nil {
            return .repost
        }
        if viewState.quote != nil {
            return .quote
        }
        if viewState.replyContext != nil {
            return .replyParent
        }
        if viewState.stats != .absent {
            return .stats
        }
        if viewState.publishState != nil {
            return .publishStatePlaceholder
        }

        return .profile
    }

    private func append(
        _ kind: TimelineResolveApplyExpectationIssue.Kind,
        scenarioName: String,
        to issues: inout [TimelineResolveApplyExpectationIssue]
    ) {
        guard !issues.contains(where: { $0.kind == kind }) else {
            return
        }

        issues.append(TimelineResolveApplyExpectationIssue(
            scenarioName: scenarioName,
            kind: kind
        ))
    }
}
