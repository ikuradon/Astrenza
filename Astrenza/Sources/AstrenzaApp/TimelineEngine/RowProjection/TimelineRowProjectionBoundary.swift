import Foundation

protocol TimelineRowProjectionBoundaryProtocol: Sendable {
    func project(_ input: TimelineRowProjectionInput) -> TimelineRowProjectionOutput
}

struct TimelineRowProjectionInput: Equatable, Codable, Sendable {
    var adapterOutput: TimelineProjectionAdapterOutput
    var surface: TimelineProjectionAdapterSurface
    var userActionContext: TimelineRowProjectionUserActionContext

    init(
        adapterOutput: TimelineProjectionAdapterOutput,
        surface: TimelineProjectionAdapterSurface? = nil,
        userActionContext: TimelineRowProjectionUserActionContext = TimelineRowProjectionUserActionContext()
    ) {
        self.adapterOutput = adapterOutput
        self.surface = surface ?? adapterOutput.surface
        self.userActionContext = userActionContext
    }
}

struct TimelineRowProjectionUserActionContext: Equatable, Codable, Sendable {
    var pendingNewEntryIDs: [TimelineEntryID]
    var allowsPendingNewVisibility: Bool

    init(
        pendingNewEntryIDs: [TimelineEntryID] = [],
        allowsPendingNewVisibility: Bool = false
    ) {
        self.pendingNewEntryIDs = pendingNewEntryIDs
        self.allowsPendingNewVisibility = allowsPendingNewVisibility
    }
}

struct TimelineRowProjectionOutput: Equatable, Codable, Sendable {
    var scenarioName: String
    var surface: TimelineProjectionAdapterSurface
    var draft: TimelineProjectedRowDraft?
    var diagnostics: TimelineRowProjectionDiagnostics
    var issues: [TimelineRowProjectionIssue]

    var isProjected: Bool {
        draft != nil && issues.isEmpty
    }
}

struct TimelineRowProjectionIssue: Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case adapterIssue
        case missingEntryID
        case missingItemKey
        case missingSourceEventID
        case missingSortAt
        case missingTieBreakID
        case missingFeedItemReason
        case missingMutationExpectation
        case missingLayoutDecision
        case missingLayoutContract
        case missingVisibilityDecision
        case missingFallback
        case delayedResolveMustReconfigure
        case deleteInsertMutationIntroduced
        case pendingNewVisibilityRequiresExplicitUserAction
        case readMarkerChanged
        case requiresNetworkWork
        case requiresDBWork
        case quoteTargetBecameReplyParent
        case homeReplyParentMustBeHeaderOnly
    }

    var scenarioName: String
    var kind: Kind
    var adapterIssueKind: TimelineProjectionAdapterIssue.Kind?
    var adapterContractRule: TimelineProjectionValidationIssue.Rule?
}

struct TimelineRowProjectionDiagnostics: Equatable, Codable, Sendable {
    var scenarioName: String
    var adapterIssueCount: Int
    var rowProjectionIssueCount: Int
    var readMarkerChanged: Bool
    var pendingNewVisible: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
}

struct TimelineProjectedRowDraft: Equatable, Codable, Sendable {
    var id: TimelineEntryID
    var itemKey: String
    var sourceEventID: EventID
    var subjectEventID: EventID?
    var sortAt: Int64
    var tieBreakID: String
    var feedItemReason: TimelineProjectionFeedItemReason
    var resolveExpectations: [TimelineResolveExpectation]
    var layoutDecision: TimelineProjectionLayoutDecision
    var visibilityDecision: TimelineProjectionVisibilityDecision
    var fallback: TimelineFallbackExpectation
    var mutationExpectation: TimelineProjectionMutationExpectation
    var diagnostics: TimelineRowProjectionDiagnostics
}

struct FixtureBackedTimelineRowProjectionBoundary: TimelineRowProjectionBoundaryProtocol {
    func project(_ input: TimelineRowProjectionInput) -> TimelineRowProjectionOutput {
        let adapterOutput = input.adapterOutput
        var issues = adapterOutput.issues.map(Self.issue)

        appendDiagnosticsIssues(
            from: adapterOutput,
            to: &issues
        )

        guard issues.isEmpty else {
            return output(
                for: input,
                draft: nil,
                issues: issues
            )
        }

        guard let entryID = adapterOutput.entryID else {
            return missingOutput(for: input, kind: .missingEntryID)
        }
        guard let itemKey = adapterOutput.itemKey else {
            return missingOutput(for: input, kind: .missingItemKey)
        }
        guard let sourceEventID = adapterOutput.sourceEventID else {
            return missingOutput(for: input, kind: .missingSourceEventID)
        }
        guard let sortAt = adapterOutput.sortAt else {
            return missingOutput(for: input, kind: .missingSortAt)
        }
        guard let tieBreakID = adapterOutput.tieBreakID else {
            return missingOutput(for: input, kind: .missingTieBreakID)
        }
        guard let feedItemReason = adapterOutput.feedItemReason else {
            return missingOutput(for: input, kind: .missingFeedItemReason)
        }
        guard let mutationExpectation = adapterOutput.mutationExpectation else {
            return missingOutput(for: input, kind: .missingMutationExpectation)
        }
        guard let layoutDecision = adapterOutput.layoutDecision else {
            return missingOutput(for: input, kind: .missingLayoutDecision)
        }
        guard let visibilityDecision = adapterOutput.visibilityDecision else {
            return missingOutput(for: input, kind: .missingVisibilityDecision)
        }
        guard let fallback = adapterOutput.fallback else {
            return missingOutput(for: input, kind: .missingFallback)
        }

        appendMutationIssues(
            from: adapterOutput,
            mutationExpectation: mutationExpectation,
            entryID: entryID,
            userActionContext: input.userActionContext,
            to: &issues
        )
        appendLayoutIssues(
            from: adapterOutput,
            layoutDecision: layoutDecision,
            to: &issues
        )

        guard issues.isEmpty else {
            return output(
                for: input,
                draft: nil,
                issues: issues
            )
        }

        let diagnostics = diagnostics(
            from: adapterOutput,
            issues: issues
        )
        let draft = TimelineProjectedRowDraft(
            id: entryID,
            itemKey: itemKey,
            sourceEventID: sourceEventID,
            subjectEventID: adapterOutput.subjectEventID,
            sortAt: sortAt,
            tieBreakID: tieBreakID,
            feedItemReason: feedItemReason,
            resolveExpectations: adapterOutput.resolveExpectations,
            layoutDecision: layoutDecision,
            visibilityDecision: visibilityDecision,
            fallback: fallback,
            mutationExpectation: mutationExpectation,
            diagnostics: diagnostics
        )

        return output(
            for: input,
            draft: draft,
            issues: []
        )
    }

    private func appendDiagnosticsIssues(
        from adapterOutput: TimelineProjectionAdapterOutput,
        to issues: inout [TimelineRowProjectionIssue]
    ) {
        if adapterOutput.diagnostics.readMarkerChanged {
            issues.append(issue(.readMarkerChanged, scenarioName: adapterOutput.scenarioName))
        }

        if adapterOutput.diagnostics.requiresNetworkWork
            || adapterOutput.resolveExpectations.contains(where: \.requiresRemoteWork) {
            issues.append(issue(.requiresNetworkWork, scenarioName: adapterOutput.scenarioName))
        }

        if adapterOutput.diagnostics.requiresDBWork {
            issues.append(issue(.requiresDBWork, scenarioName: adapterOutput.scenarioName))
        }
    }

    private func appendMutationIssues(
        from adapterOutput: TimelineProjectionAdapterOutput,
        mutationExpectation: TimelineProjectionMutationExpectation,
        entryID: TimelineEntryID,
        userActionContext: TimelineRowProjectionUserActionContext,
        to issues: inout [TimelineRowProjectionIssue]
    ) {
        let isExplicitPendingNewInsert = mutationExpectation.style == .insertOnlyForExplicitUserPendingNewAction
            && adapterOutput.diagnostics.pendingNewVisible
            && userActionContext.allowsPendingNewVisibility
            && userActionContext.pendingNewEntryIDs.contains(entryID)

        if adapterOutput.diagnostics.pendingNewVisible && !isExplicitPendingNewInsert {
            issues.append(issue(
                .pendingNewVisibilityRequiresExplicitUserAction,
                scenarioName: adapterOutput.scenarioName
            ))
        }

        if mutationExpectation.readMarkerChanged {
            issues.append(issue(.readMarkerChanged, scenarioName: adapterOutput.scenarioName))
        }

        if !mutationExpectation.deletedIDs.isEmpty
            || (!mutationExpectation.insertedIDs.isEmpty && !isExplicitPendingNewInsert) {
            issues.append(issue(.deleteInsertMutationIntroduced, scenarioName: adapterOutput.scenarioName))
        }

        if mutationExpectation.quoteCreatesReplyRelation
            && adapterOutput.resolveExpectations.contains(where: { $0.target == .quoteTarget }) {
            issues.append(issue(.quoteTargetBecameReplyParent, scenarioName: adapterOutput.scenarioName))
        }

        guard hasDelayedResolveTransition(adapterOutput) else {
            return
        }

        if mutationExpectation.style != .reconfigure
            || mutationExpectation.delayedResolveStyle != .neverDeleteInsertForDelayedResolve {
            issues.append(issue(.delayedResolveMustReconfigure, scenarioName: adapterOutput.scenarioName))
        }

        if !mutationExpectation.insertedIDs.isEmpty
            || !mutationExpectation.deletedIDs.isEmpty
            || mutationExpectation.allowsDeleteInsertForDelayedResolve {
            issues.append(issue(.deleteInsertMutationIntroduced, scenarioName: adapterOutput.scenarioName))
        }
    }

    private func appendLayoutIssues(
        from adapterOutput: TimelineProjectionAdapterOutput,
        layoutDecision: TimelineProjectionLayoutDecision,
        to issues: inout [TimelineRowProjectionIssue]
    ) {
        if adapterOutput.visibilityDecision?.includedInVisibleSnapshot == true
            && !layoutDecision.hasLayoutContract {
            issues.append(issue(.missingLayoutContract, scenarioName: adapterOutput.scenarioName))
        }

        guard adapterOutput.resolveExpectations.contains(where: { $0.target == .replyParentRoot }),
              layoutDecision.contract.rowKind == .home
        else {
            return
        }

        if layoutDecision.contract.replyHeaderMode != .oneLine
            || layoutDecision.contract.allowsInlineParentPreviewInHome {
            issues.append(issue(.homeReplyParentMustBeHeaderOnly, scenarioName: adapterOutput.scenarioName))
        }
    }

    private static func issue(
        from adapterIssue: TimelineProjectionAdapterIssue
    ) -> TimelineRowProjectionIssue {
        TimelineRowProjectionIssue(
            scenarioName: adapterIssue.scenarioName,
            kind: .adapterIssue,
            adapterIssueKind: adapterIssue.kind,
            adapterContractRule: adapterIssue.contractRule
        )
    }

    private func issue(
        _ kind: TimelineRowProjectionIssue.Kind,
        scenarioName: String
    ) -> TimelineRowProjectionIssue {
        TimelineRowProjectionIssue(
            scenarioName: scenarioName,
            kind: kind,
            adapterIssueKind: nil,
            adapterContractRule: nil
        )
    }

    private func missingOutput(
        for input: TimelineRowProjectionInput,
        kind: TimelineRowProjectionIssue.Kind
    ) -> TimelineRowProjectionOutput {
        output(
            for: input,
            draft: nil,
            issues: [issue(kind, scenarioName: input.adapterOutput.scenarioName)]
        )
    }

    private func output(
        for input: TimelineRowProjectionInput,
        draft: TimelineProjectedRowDraft?,
        issues: [TimelineRowProjectionIssue]
    ) -> TimelineRowProjectionOutput {
        TimelineRowProjectionOutput(
            scenarioName: input.adapterOutput.scenarioName,
            surface: input.surface,
            draft: draft,
            diagnostics: diagnostics(
                from: input.adapterOutput,
                issues: issues
            ),
            issues: issues
        )
    }

    private func diagnostics(
        from adapterOutput: TimelineProjectionAdapterOutput,
        issues: [TimelineRowProjectionIssue]
    ) -> TimelineRowProjectionDiagnostics {
        TimelineRowProjectionDiagnostics(
            scenarioName: adapterOutput.scenarioName,
            adapterIssueCount: adapterOutput.issues.count,
            rowProjectionIssueCount: issues.count,
            readMarkerChanged: adapterOutput.diagnostics.readMarkerChanged,
            pendingNewVisible: adapterOutput.diagnostics.pendingNewVisible,
            requiresNetworkWork: adapterOutput.diagnostics.requiresNetworkWork
                || adapterOutput.resolveExpectations.contains(where: \.requiresRemoteWork),
            requiresDBWork: adapterOutput.diagnostics.requiresDBWork
        )
    }

    private func hasDelayedResolveTransition(_ output: TimelineProjectionAdapterOutput) -> Bool {
        output.resolveExpectations.contains { $0.isDelayedResolveTransition }
    }
}
