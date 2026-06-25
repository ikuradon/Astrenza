import DesignSystem
import Foundation

struct TimelineProjectionValidationIssue: Equatable, Codable, Sendable {
    enum Rule: String, Codable, Sendable {
        case unstableIdentity
        case delayedResolveMustReconfigure
        case delayedResolveMustNotInsertOrDelete
        case readMarkerMustNotChange
        case failedResolveMustKeepSourceNoteVisible
        case quoteMustNotCreateReplyRelation
        case homeReplyParentMustBeHeaderOnly
        case homeVisibleResolveMustNotChangeHeight
        case pendingNewMustWaitForUserAction
    }

    var scenarioName: String
    var rule: Rule
}

struct TimelineProjectionContractValidator: Sendable {
    func validate(_ scenario: TimelineProjectionScenario) -> [TimelineProjectionValidationIssue] {
        var issues: [TimelineProjectionValidationIssue] = []

        if scenario.input.identity.entryID != scenario.expectedOutput.identity.entryID
            || scenario.input.identity.itemKey != scenario.expectedOutput.identity.itemKey {
            issues.append(issue(.unstableIdentity, in: scenario))
        }

        let output = scenario.expectedOutput
        if output.mutation.readMarkerChanged {
            issues.append(issue(.readMarkerMustNotChange, in: scenario))
        }

        if scenario.hasDelayedResolveTransition {
            if output.mutation.expectedMutationStyle != .reconfigure {
                issues.append(issue(.delayedResolveMustReconfigure, in: scenario))
            }

            if output.mutation.initialEntryID != output.mutation.finalEntryID {
                issues.append(issue(.unstableIdentity, in: scenario))
            }

            if !output.mutation.insertedIDs.isEmpty || !output.mutation.deletedIDs.isEmpty {
                issues.append(issue(.delayedResolveMustNotInsertOrDelete, in: scenario))
            }
        }

        let touchesDelayedResolveEnrichment = output.resolveExpectations.contains { expectation in
            Self.enrichmentTargets.contains(expectation.target)
        }
        if touchesDelayedResolveEnrichment {
            if output.mutation.expectedMutationStyle != .reconfigure {
                issues.append(issue(.delayedResolveMustReconfigure, in: scenario))
            }

            if !output.mutation.insertedIDs.isEmpty || !output.mutation.deletedIDs.isEmpty {
                issues.append(issue(.delayedResolveMustNotInsertOrDelete, in: scenario))
            }
        }

        if output.resolveExpectations.contains(where: \.requiresFallback) {
            if !output.fallback.keepsSourceNoteVisible || output.visibility.removesSourceNote {
                issues.append(issue(.failedResolveMustKeepSourceNoteVisible, in: scenario))
            }
        }

        if output.resolveExpectations.contains(where: { $0.target == .quoteTarget })
            && output.mutation.quoteCreatesReplyRelation {
            issues.append(issue(.quoteMustNotCreateReplyRelation, in: scenario))
        }

        if output.resolveExpectations.contains(where: { $0.target == .replyParentRoot })
            && output.layout.rowKind == .home {
            if output.layout.replyHeaderMode != .oneLine || output.layout.allowsInlineParentPreviewInHome {
                issues.append(issue(.homeReplyParentMustBeHeaderOnly, in: scenario))
            }
        }

        if scenario.hasDelayedResolveTransition
            && output.layout.rowKind == .home
            && output.visibility.isVisibleInHome
            && !output.layout.isDetailOnly {
            if output.layout.canChangeHeightAfterFirstDisplay
                || !output.layout.noUnlimitedHeightGrowthAfterResolve {
                issues.append(issue(.homeVisibleResolveMustNotChangeHeight, in: scenario))
            }
        }

        if scenario.input.isPendingNew && !scenario.input.userActionAllowsPendingNewInsertion {
            if output.visibility.includedInVisibleSnapshot
                || output.mutation.pendingNewInsertedIntoVisibleSnapshot {
                issues.append(issue(.pendingNewMustWaitForUserAction, in: scenario))
            }
        }

        return issues
    }

    private static let enrichmentTargets: Set<TimelineDelayedResolveTarget> = [
        .profile,
        .bodyMention,
        .media,
        .linkPreviewOGP,
        .repostTarget,
        .quoteTarget,
        .replyParentRoot
    ]

    private func issue(
        _ rule: TimelineProjectionValidationIssue.Rule,
        in scenario: TimelineProjectionScenario
    ) -> TimelineProjectionValidationIssue {
        TimelineProjectionValidationIssue(
            scenarioName: scenario.name,
            rule: rule
        )
    }
}
