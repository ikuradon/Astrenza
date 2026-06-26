import Foundation

struct TimelineResolveSnapshotDiagnosticsIssue: Equatable, Codable, Sendable {
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
        case invalidResolveApplyExpectation
        case missingReconfigureIntent
        case visibleIDsChangedForReconfigure
        case anchorIdentityChanged
        case fallbackReasonMustBeNil
        case pendingNewInsertMutationMismatch
        case networkWaitedBeforeInteractiveScroll
    }

    var scenarioName: String
    var kind: Kind
    var resolveApplyIssueKind: TimelineResolveApplyExpectationIssue.Kind?
}

struct TimelineResolveSnapshotMutationExpectation: Equatable, Sendable {
    var mutationReason: TimelineSnapshotReason?
    var mutationStyle: TimelineMutationStyle
    var reconfigureIDs: [TimelineEntryID]
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
    var visibleIDsBefore: [TimelineEntryID]
    var visibleIDsAfter: [TimelineEntryID]
    var anchorBefore: TimelineAnchorSnapshot?
    var anchorAfter: TimelineAnchorSnapshot?
    var fallbackReason: TimelineRestoreFallbackReason?
    var readMarkerChanged: Bool
    var pendingNewInsertedIntoVisibleSnapshot: Bool
    var networkWaitedBeforeInteractiveScroll: Bool
}

struct TimelineResolveSnapshotDiagnosticsExpectation: Equatable, Sendable {
    var scenarioName: String
    var resolveApplyExpectation: TimelineResolveApplyExpectation
    var mutationPlan: TimelineSnapshotMutationPlan?
    var mutationRecord: TimelineSnapshotMutationRecord?
    var mutationExpectation: TimelineResolveSnapshotMutationExpectation
    var issues: [TimelineResolveSnapshotDiagnosticsIssue]

    var isClean: Bool {
        issues.isEmpty
    }
}

struct TimelineResolveSnapshotDiagnosticsBuilder: Sendable {
    func expectation(
        scenarioName: String,
        resolveApplyExpectation: TimelineResolveApplyExpectation,
        visibleIDsBefore: [TimelineEntryID],
        visibleIDsAfter: [TimelineEntryID],
        anchorBefore: TimelineVisualAnchor? = nil,
        anchorAfter: TimelineVisualAnchor? = nil,
        fallbackReason: TimelineRestoreFallbackReason? = nil,
        readMarkerChanged explicitReadMarkerChanged: Bool? = nil,
        networkWaitedBeforeInteractiveScroll: Bool = false,
        timestampMS: Int64 = TimelinePositionRecorder.currentTimeMilliseconds()
    ) -> TimelineResolveSnapshotDiagnosticsExpectation {
        let readMarkerChanged = explicitReadMarkerChanged ?? resolveApplyExpectation.readMarkerChanged
        var issues = issues(from: resolveApplyExpectation, scenarioName: scenarioName)
        var mutationPlan: TimelineSnapshotMutationPlan?
        var mutationReason: TimelineSnapshotReason?
        var mutationStyle: TimelineMutationStyle = .snapshot
        var reconfigureIDs: [TimelineEntryID] = []
        var insertedIDs: [TimelineEntryID] = []
        var deletedIDs: [TimelineEntryID] = []
        var pendingNewInserted = false

        if resolveApplyExpectation.readMarkerChanged || readMarkerChanged {
            append(.readMarkerChanged, scenarioName: scenarioName, to: &issues)
        }
        if resolveApplyExpectation.requiresNetworkWork {
            append(.requiresNetworkWork, scenarioName: scenarioName, to: &issues)
        }
        if resolveApplyExpectation.requiresDBWork {
            append(.requiresDBWork, scenarioName: scenarioName, to: &issues)
        }
        if fallbackReason != nil {
            append(.fallbackReasonMustBeNil, scenarioName: scenarioName, to: &issues)
        }
        if networkWaitedBeforeInteractiveScroll {
            append(.networkWaitedBeforeInteractiveScroll, scenarioName: scenarioName, to: &issues)
        }
        if anchorIdentityChanged(before: anchorBefore, after: anchorAfter) {
            append(.anchorIdentityChanged, scenarioName: scenarioName, to: &issues)
        }

        switch resolveApplyExpectation.style {
        case .reconfigure:
            guard let intent = resolveApplyExpectation.reconfigureIntent else {
                append(.missingReconfigureIntent, scenarioName: scenarioName, to: &issues)
                break
            }

            mutationReason = intent.reason.snapshotReason
            mutationStyle = .reconfigure
            mutationPlan = TimelineSnapshotCoordinator.makeMutationPlan(
                currentIDs: visibleIDsBefore,
                proposedIDs: visibleIDsAfter,
                reconfigureIDs: intent.entryIDs,
                reason: intent.reason.snapshotReason
            )

            guard let plan = mutationPlan else {
                break
            }

            reconfigureIDs = plan.reconfigureIDs
            insertedIDs = plan.insertedIDs
            deletedIDs = plan.deletedIDs

            if !TimelineSnapshotCoordinator.isReconfigureOnlyMutation(plan) {
                append(.delayedResolveMustReconfigure, scenarioName: scenarioName, to: &issues)
            }
            if visibleIDsBefore != visibleIDsAfter {
                append(.visibleIDsChangedForReconfigure, scenarioName: scenarioName, to: &issues)
            }
            if !plan.insertedIDs.isEmpty
                || !plan.deletedIDs.isEmpty
                || !resolveApplyExpectation.insertedIDs.isEmpty
                || !resolveApplyExpectation.deletedIDs.isEmpty
                || !intent.insertedIDs.isEmpty
                || !intent.deletedIDs.isEmpty {
                append(.deleteInsertMutationIntroduced, scenarioName: scenarioName, to: &issues)
            }

        case .insertOnlyForExplicitUserPendingNewAction:
            mutationReason = .userInsertedPendingNew
            mutationStyle = .snapshot
            pendingNewInserted = true
            mutationPlan = TimelineSnapshotCoordinator.makeMutationPlan(
                currentIDs: visibleIDsBefore,
                proposedIDs: visibleIDsAfter,
                reason: .userInsertedPendingNew
            )

            guard let plan = mutationPlan else {
                break
            }

            insertedIDs = plan.insertedIDs
            deletedIDs = plan.deletedIDs

            let decision = TimelineSnapshotCoordinator.pendingNewInsertionDecision(
                pendingNewIDs: resolveApplyExpectation.insertedIDs,
                reason: .userInsertedPendingNew
            )
            if resolveApplyExpectation.insertedIDs.isEmpty
                || decision != .allowed
                || plan.insertedIDs != resolveApplyExpectation.insertedIDs
                || !plan.deletedIDs.isEmpty {
                append(.pendingNewInsertMutationMismatch, scenarioName: scenarioName, to: &issues)
            }

        case .none:
            mutationStyle = .snapshot

        case .invalid:
            append(.invalidResolveApplyExpectation, scenarioName: scenarioName, to: &issues)
        }

        let mutationExpectation = TimelineResolveSnapshotMutationExpectation(
            mutationReason: mutationReason,
            mutationStyle: mutationStyle,
            reconfigureIDs: reconfigureIDs,
            insertedIDs: insertedIDs,
            deletedIDs: deletedIDs,
            visibleIDsBefore: visibleIDsBefore,
            visibleIDsAfter: visibleIDsAfter,
            anchorBefore: anchorBefore.map(TimelineAnchorSnapshot.init(anchor:)),
            anchorAfter: anchorAfter.map(TimelineAnchorSnapshot.init(anchor:)),
            fallbackReason: fallbackReason,
            readMarkerChanged: readMarkerChanged,
            pendingNewInsertedIntoVisibleSnapshot: pendingNewInserted,
            networkWaitedBeforeInteractiveScroll: networkWaitedBeforeInteractiveScroll
        )

        let record: TimelineSnapshotMutationRecord?
        if issues.isEmpty, let mutationReason {
            record = TimelineSnapshotCoordinator.makeMutationRecord(
                reason: mutationReason,
                anchorBefore: anchorBefore,
                anchorAfter: anchorAfter,
                visibleIDsBefore: visibleIDsBefore,
                visibleIDsAfter: visibleIDsAfter,
                timestampMS: timestampMS,
                fallbackReason: fallbackReason,
                readMarkerChanged: readMarkerChanged
            )
        } else {
            record = nil
        }

        return TimelineResolveSnapshotDiagnosticsExpectation(
            scenarioName: scenarioName,
            resolveApplyExpectation: resolveApplyExpectation,
            mutationPlan: mutationPlan,
            mutationRecord: record,
            mutationExpectation: mutationExpectation,
            issues: issues
        )
    }

    private func issues(
        from resolveApplyExpectation: TimelineResolveApplyExpectation,
        scenarioName: String
    ) -> [TimelineResolveSnapshotDiagnosticsIssue] {
        var issues: [TimelineResolveSnapshotDiagnosticsIssue] = []
        for applyIssue in resolveApplyExpectation.issues {
            append(
                kind(for: applyIssue.kind),
                scenarioName: applyIssue.scenarioName.isEmpty ? scenarioName : applyIssue.scenarioName,
                resolveApplyIssueKind: applyIssue.kind,
                to: &issues
            )
        }
        return issues
    }

    private func kind(
        for applyIssueKind: TimelineResolveApplyExpectationIssue.Kind
    ) -> TimelineResolveSnapshotDiagnosticsIssue.Kind {
        switch applyIssueKind {
        case .identityChanged:
            .identityChanged
        case .readMarkerChanged:
            .readMarkerChanged
        case .requiresNetworkWork:
            .requiresNetworkWork
        case .requiresDBWork:
            .requiresDBWork
        case .delayedResolveMustReconfigure:
            .delayedResolveMustReconfigure
        case .deleteInsertMutationIntroduced:
            .deleteInsertMutationIntroduced
        case .pendingNewInsertRequiresExplicitUserAction:
            .pendingNewInsertRequiresExplicitUserAction
        case .failedResolveRemovedSourceNote:
            .failedResolveRemovedSourceNote
        case .quoteTargetBecameReplyParent:
            .quoteTargetBecameReplyParent
        case .replyParentMustRemainHeaderOnly:
            .replyParentMustRemainHeaderOnly
        case .homeVisibleResolveCanChangeHeight:
            .homeVisibleResolveCanChangeHeight
        }
    }

    private func anchorIdentityChanged(
        before: TimelineVisualAnchor?,
        after: TimelineVisualAnchor?
    ) -> Bool {
        guard let before, let after else {
            return false
        }

        return before.anchorItemKey != after.anchorItemKey
    }

    private func append(
        _ kind: TimelineResolveSnapshotDiagnosticsIssue.Kind,
        scenarioName: String,
        resolveApplyIssueKind: TimelineResolveApplyExpectationIssue.Kind? = nil,
        to issues: inout [TimelineResolveSnapshotDiagnosticsIssue]
    ) {
        guard !issues.contains(where: { $0.kind == kind }) else {
            return
        }

        issues.append(TimelineResolveSnapshotDiagnosticsIssue(
            scenarioName: scenarioName,
            kind: kind,
            resolveApplyIssueKind: resolveApplyIssueKind
        ))
    }
}
