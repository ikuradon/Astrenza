import Foundation

protocol ResolveCoordinatorBoundaryProtocol: Sendable {
    func plan(_ requests: [ResolveRequest]) -> ResolveCoordinatorBoundaryPlan
    func result(
        for request: ResolveRequest,
        before initialViewState: TimelineEntryViewState?,
        after finalViewState: TimelineEntryViewState,
        existingIDs: [TimelineEntryID]
    ) -> ResolveResult
}

struct ResolveRequestID: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum ResolveTargetKind: String, CaseIterable, Codable, Sendable {
    case profile
    case bodyMentionProfile
    case mediaMetadata
    case mediaBytes
    case linkPreviewOGP
    case repostTarget
    case quoteTarget
    case replyParent
    case replyRoot
    case stats
    case publishStatePlaceholder
    case unsupported

    var delayedResolveTarget: TimelineDelayedResolveTarget? {
        switch self {
        case .profile:
            .profile
        case .bodyMentionProfile:
            .bodyMention
        case .mediaMetadata, .mediaBytes:
            .media
        case .linkPreviewOGP:
            .linkPreviewOGP
        case .repostTarget:
            .repostTarget
        case .quoteTarget:
            .quoteTarget
        case .replyParent, .replyRoot:
            .replyParentRoot
        case .stats:
            .stats
        case .publishStatePlaceholder:
            .publishStatePlaceholder
        case .unsupported:
            nil
        }
    }

    var resolveApplyReason: ResolveApplyReason {
        switch self {
        case .profile:
            .profile
        case .bodyMentionProfile:
            .bodyMention
        case .mediaMetadata, .mediaBytes:
            .media
        case .linkPreviewOGP:
            .linkPreview
        case .repostTarget:
            .repost
        case .quoteTarget:
            .quote
        case .replyParent, .replyRoot:
            .replyParent
        case .stats:
            .stats
        case .publishStatePlaceholder:
            .publishStatePlaceholder
        case .unsupported:
            .debug
        }
    }

    var isLocalOnly: Bool {
        switch self {
        case .stats, .publishStatePlaceholder:
            true
        case .profile,
             .bodyMentionProfile,
             .mediaMetadata,
             .mediaBytes,
             .linkPreviewOGP,
             .repostTarget,
             .quoteTarget,
             .replyParent,
             .replyRoot,
             .unsupported:
            false
        }
    }

    var requiresFutureNetworkWork: Bool {
        switch self {
        case .profile,
             .bodyMentionProfile,
             .mediaMetadata,
             .mediaBytes,
             .linkPreviewOGP,
             .repostTarget,
             .quoteTarget,
             .replyParent,
             .replyRoot:
            true
        case .stats, .publishStatePlaceholder, .unsupported:
            false
        }
    }

    var requiresFutureDBWork: Bool {
        switch self {
        case .profile,
             .bodyMentionProfile,
             .mediaMetadata,
             .linkPreviewOGP,
             .repostTarget,
             .quoteTarget,
             .replyParent,
             .replyRoot:
            true
        case .mediaBytes, .stats, .publishStatePlaceholder, .unsupported:
            false
        }
    }
}

struct ResolveTarget: Equatable, Codable, Sendable {
    var kind: ResolveTargetKind
    var entryID: TimelineEntryID?
    var isValid: Bool
    var payloadPreview: String?

    init(
        kind: ResolveTargetKind,
        entryID: TimelineEntryID?,
        isValid: Bool = true,
        payloadPreview: String? = nil
    ) {
        self.kind = kind
        self.entryID = entryID
        self.isValid = isValid
        self.payloadPreview = payloadPreview
    }

    var isLocalOnly: Bool {
        kind.isLocalOnly
    }

    var requiresFutureNetworkWork: Bool {
        kind.requiresFutureNetworkWork
    }

    var requiresFutureDBWork: Bool {
        kind.requiresFutureDBWork
    }

    var delayedResolveTarget: TimelineDelayedResolveTarget? {
        kind.delayedResolveTarget
    }

    var containsUnsafeSensitivePayload: Bool {
        guard let payloadPreview else {
            return false
        }

        let lowercased = payloadPreview.lowercased()
        let markers = [
            "n" + "sec",
            "se" + "cret",
            "sign" + "ing",
            "bear" + "er",
            "to" + "ken"
        ]
        return markers.contains { lowercased.contains($0) }
    }
}

enum ResolveScope: String, CaseIterable, Codable, Sendable {
    case visibleRows
    case nearViewport
    case openedDetailThread
    case backgroundCacheWarming
    case localOnly
    case manualTestFixture
    case invalid
}

enum ResolvePriority: String, CaseIterable, Codable, Sendable {
    case visibleRows
    case openedDetailThread
    case localOnly
    case manualTestFixture
    case nearViewport
    case backgroundCacheWarming
    case invalid

    var sortRank: Int {
        switch self {
        case .visibleRows:
            600
        case .openedDetailThread:
            500
        case .localOnly:
            400
        case .manualTestFixture:
            300
        case .nearViewport:
            200
        case .backgroundCacheWarming:
            100
        case .invalid:
            0
        }
    }
}

struct ResolveRequest: Equatable, Codable, Sendable {
    var id: ResolveRequestID
    var target: ResolveTarget
    var scope: ResolveScope
    var priority: ResolvePriority
    var allowsNetworkWork: Bool
    var allowsDBWork: Bool
    var requestsNetworkWork: Bool
    var requestsDBWork: Bool
    var attemptedInsertedIDs: [TimelineEntryID]
    var attemptedDeletedIDs: [TimelineEntryID]
    var attemptsReadMarkerAdvance: Bool
    var requiresProductionHomeRuntime: Bool

    init(
        id: ResolveRequestID,
        target: ResolveTarget,
        scope: ResolveScope,
        priority: ResolvePriority,
        allowsNetworkWork: Bool = false,
        allowsDBWork: Bool = false,
        requestsNetworkWork: Bool = false,
        requestsDBWork: Bool = false,
        attemptedInsertedIDs: [TimelineEntryID] = [],
        attemptedDeletedIDs: [TimelineEntryID] = [],
        attemptsReadMarkerAdvance: Bool = false,
        requiresProductionHomeRuntime: Bool = false
    ) {
        self.id = id
        self.target = target
        self.scope = scope
        self.priority = priority
        self.allowsNetworkWork = allowsNetworkWork
        self.allowsDBWork = allowsDBWork
        self.requestsNetworkWork = requestsNetworkWork
        self.requestsDBWork = requestsDBWork
        self.attemptedInsertedIDs = attemptedInsertedIDs
        self.attemptedDeletedIDs = attemptedDeletedIDs
        self.attemptsReadMarkerAdvance = attemptsReadMarkerAdvance
        self.requiresProductionHomeRuntime = requiresProductionHomeRuntime
    }
}

struct ResolveCoordinatorBoundaryIssue: Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case invalidTarget
        case missingTimelineEntryID
        case invalidScope
        case invalidPriority
        case unsupportedTargetKind
        case networkRequestedInNoNetworkMode
        case dbRequestedInNoDBMode
        case insertDeleteAttemptedForDelayedResolve
        case readMarkerAdvanceAttempted
        case requiresProductionHomeRuntime
        case unsafeSensitivePayload
    }

    var requestID: ResolveRequestID
    var kind: Kind
    var targetKind: ResolveTargetKind
    var payloadRedacted: Bool
}

struct ResolveCoordinatorBoundaryDiagnostics: Equatable, Codable, Sendable {
    var acceptedCount: Int
    var rejectedCount: Int
    var issueCount: Int
    var visibleRowResolveCount: Int
    var futureNetworkTargetCount: Int
    var futureDBTargetCount: Int
    var networkWorkStarted: Bool
    var dbWorkStarted: Bool
    var readMarkerChanged: Bool
    var pendingNewInserted: Bool
    var productionHomeRuntimeRequired: Bool

    init(
        acceptedCount: Int = 0,
        rejectedCount: Int = 0,
        issueCount: Int = 0,
        visibleRowResolveCount: Int = 0,
        futureNetworkTargetCount: Int = 0,
        futureDBTargetCount: Int = 0,
        networkWorkStarted: Bool = false,
        dbWorkStarted: Bool = false,
        readMarkerChanged: Bool = false,
        pendingNewInserted: Bool = false,
        productionHomeRuntimeRequired: Bool = false
    ) {
        self.acceptedCount = acceptedCount
        self.rejectedCount = rejectedCount
        self.issueCount = issueCount
        self.visibleRowResolveCount = visibleRowResolveCount
        self.futureNetworkTargetCount = futureNetworkTargetCount
        self.futureDBTargetCount = futureDBTargetCount
        self.networkWorkStarted = networkWorkStarted
        self.dbWorkStarted = dbWorkStarted
        self.readMarkerChanged = readMarkerChanged
        self.pendingNewInserted = pendingNewInserted
        self.productionHomeRuntimeRequired = productionHomeRuntimeRequired
    }
}

struct ResolveCoordinatorBoundaryPlan: Equatable, Codable, Sendable {
    var acceptedRequests: [ResolveRequest]
    var rejectedRequests: [ResolveRequest]
    var orderedRequestIDs: [ResolveRequestID]
    var issues: [ResolveCoordinatorBoundaryIssue]
    var diagnostics: ResolveCoordinatorBoundaryDiagnostics
}

struct ResolveResult: Equatable, Codable, Sendable {
    enum State: String, Codable, Sendable {
        case resolved
        case failed
        case blocked
        case unavailable
    }

    var requestID: ResolveRequestID
    var target: ResolveTarget
    var state: State
    var applyExpectation: TimelineResolveApplyExpectation?
    var failure: ResolveFailure?
    var issues: [ResolveCoordinatorBoundaryIssue]
    var diagnostics: ResolveCoordinatorBoundaryDiagnostics
    var keepsSourceNoteVisible: Bool
    var fallbackMode: TimelineFallbackMode
}

struct FakeResolveCoordinatorBoundary: ResolveCoordinatorBoundaryProtocol, Equatable, Codable {
    enum ScriptedResult: String, Equatable, Codable, Sendable {
        case resolved
        case failed
        case blocked
        case unavailable

        var state: ResolveResult.State {
            switch self {
            case .resolved:
                .resolved
            case .failed:
                .failed
            case .blocked:
                .blocked
            case .unavailable:
                .unavailable
            }
        }
    }

    var scriptedResults: [ResolveRequestID: ScriptedResult]

    init(scriptedResults: [ResolveRequestID: ScriptedResult] = [:]) {
        self.scriptedResults = scriptedResults
    }

    func plan(_ requests: [ResolveRequest]) -> ResolveCoordinatorBoundaryPlan {
        let issuesByRequest = Dictionary(grouping: requests.flatMap(validate), by: \.requestID)
        let accepted = requests
            .filter { issuesByRequest[$0.id, default: []].isEmpty }
            .sorted(by: Self.prioritySort)
        let rejected = requests.filter { !issuesByRequest[$0.id, default: []].isEmpty }
        let issues = requests.flatMap { issuesByRequest[$0.id, default: []] }

        return ResolveCoordinatorBoundaryPlan(
            acceptedRequests: accepted,
            rejectedRequests: rejected,
            orderedRequestIDs: accepted.map(\.id),
            issues: issues,
            diagnostics: diagnostics(
                acceptedRequests: accepted,
                rejectedRequests: rejected,
                issues: issues
            )
        )
    }

    func result(
        for request: ResolveRequest,
        before initialViewState: TimelineEntryViewState?,
        after finalViewState: TimelineEntryViewState,
        existingIDs: [TimelineEntryID]
    ) -> ResolveResult {
        let plan = plan([request])
        let rawApplyExpectation = plan.issues.isEmpty
            ? TimelineResolveApplyExpectationBuilder().expectation(
                before: initialViewState,
                after: finalViewState,
                existingIDs: existingIDs
            )
            : nil
        let applyIssues = boundaryIssues(
            for: rawApplyExpectation,
            request: request
        )
        let issues = plan.issues + applyIssues
        let state = issues.isEmpty
            ? scriptedResults[request.id, default: .resolved].state
            : ResolveResult.State.blocked
        let applyExpectation = issues.isEmpty ? rawApplyExpectation : nil
        let diagnostics = resultDiagnostics(
            from: plan,
            issues: issues
        )

        return ResolveResult(
            requestID: request.id,
            target: request.target,
            state: state,
            applyExpectation: applyExpectation,
            failure: failure(
                for: request.target.kind,
                state: state,
                finalViewState: finalViewState
            ),
            issues: issues,
            diagnostics: diagnostics,
            keepsSourceNoteVisible: finalViewState.body.keepsSourceNoteVisible
                && finalViewState.visibility.keepsSourceNoteVisible
                && !finalViewState.visibility.removesSourceNote,
            fallbackMode: finalViewState.visibility.fallbackMode
        )
    }

    private func validate(_ request: ResolveRequest) -> [ResolveCoordinatorBoundaryIssue] {
        var issues: [ResolveCoordinatorBoundaryIssue] = []

        if !request.target.isValid {
            issues.append(issue(.invalidTarget, request: request))
        }
        if request.target.entryID == nil {
            issues.append(issue(.missingTimelineEntryID, request: request))
        }
        if request.scope == .invalid {
            issues.append(issue(.invalidScope, request: request))
        }
        if request.priority == .invalid {
            issues.append(issue(.invalidPriority, request: request))
        }
        if request.target.kind == .unsupported {
            issues.append(issue(.unsupportedTargetKind, request: request))
        }
        if request.requestsNetworkWork && !request.allowsNetworkWork {
            issues.append(issue(.networkRequestedInNoNetworkMode, request: request))
        }
        if request.requestsDBWork && !request.allowsDBWork {
            issues.append(issue(.dbRequestedInNoDBMode, request: request))
        }
        if request.target.delayedResolveTarget != nil
            && (!request.attemptedInsertedIDs.isEmpty || !request.attemptedDeletedIDs.isEmpty) {
            issues.append(issue(.insertDeleteAttemptedForDelayedResolve, request: request))
        }
        if request.attemptsReadMarkerAdvance {
            issues.append(issue(.readMarkerAdvanceAttempted, request: request))
        }
        if request.requiresProductionHomeRuntime {
            issues.append(issue(.requiresProductionHomeRuntime, request: request))
        }
        if request.target.containsUnsafeSensitivePayload {
            issues.append(issue(.unsafeSensitivePayload, request: request, payloadRedacted: true))
        }

        return issues
    }

    private func issue(
        _ kind: ResolveCoordinatorBoundaryIssue.Kind,
        request: ResolveRequest,
        payloadRedacted: Bool = false
    ) -> ResolveCoordinatorBoundaryIssue {
        ResolveCoordinatorBoundaryIssue(
            requestID: request.id,
            kind: kind,
            targetKind: request.target.kind,
            payloadRedacted: payloadRedacted
        )
    }

    private func diagnostics(
        acceptedRequests: [ResolveRequest],
        rejectedRequests: [ResolveRequest],
        issues: [ResolveCoordinatorBoundaryIssue]
    ) -> ResolveCoordinatorBoundaryDiagnostics {
        ResolveCoordinatorBoundaryDiagnostics(
            acceptedCount: acceptedRequests.count,
            rejectedCount: rejectedRequests.count,
            issueCount: issues.count,
            visibleRowResolveCount: acceptedRequests.filter { $0.scope == .visibleRows }.count,
            futureNetworkTargetCount: acceptedRequests.filter { $0.target.requiresFutureNetworkWork }.count,
            futureDBTargetCount: acceptedRequests.filter { $0.target.requiresFutureDBWork }.count,
            networkWorkStarted: false,
            dbWorkStarted: false,
            readMarkerChanged: false,
            pendingNewInserted: false,
            productionHomeRuntimeRequired: acceptedRequests.contains(where: \.requiresProductionHomeRuntime)
        )
    }

    private func resultDiagnostics(
        from plan: ResolveCoordinatorBoundaryPlan,
        issues: [ResolveCoordinatorBoundaryIssue]
    ) -> ResolveCoordinatorBoundaryDiagnostics {
        ResolveCoordinatorBoundaryDiagnostics(
            acceptedCount: plan.diagnostics.acceptedCount,
            rejectedCount: plan.diagnostics.rejectedCount,
            issueCount: issues.count,
            visibleRowResolveCount: plan.diagnostics.visibleRowResolveCount,
            futureNetworkTargetCount: plan.diagnostics.futureNetworkTargetCount,
            futureDBTargetCount: plan.diagnostics.futureDBTargetCount,
            networkWorkStarted: false,
            dbWorkStarted: false,
            readMarkerChanged: false,
            pendingNewInserted: false,
            productionHomeRuntimeRequired: plan.diagnostics.productionHomeRuntimeRequired
        )
    }

    private func boundaryIssues(
        for applyExpectation: TimelineResolveApplyExpectation?,
        request: ResolveRequest
    ) -> [ResolveCoordinatorBoundaryIssue] {
        guard let applyExpectation else {
            return []
        }

        var issues: [ResolveCoordinatorBoundaryIssue] = []
        let hasDeleteInsert = !applyExpectation.insertedIDs.isEmpty
            || !applyExpectation.deletedIDs.isEmpty
            || applyExpectation.issues.contains { $0.kind == .deleteInsertMutationIntroduced }

        if request.target.delayedResolveTarget != nil && hasDeleteInsert {
            issues.append(issue(.insertDeleteAttemptedForDelayedResolve, request: request))
        }

        let hasReadMarkerChange = applyExpectation.readMarkerChanged
            || applyExpectation.issues.contains { $0.kind == .readMarkerChanged }
        if hasReadMarkerChange {
            issues.append(issue(.readMarkerAdvanceAttempted, request: request))
        }

        return issues
    }

    private func failure(
        for kind: ResolveTargetKind,
        state: ResolveResult.State,
        finalViewState: TimelineEntryViewState
    ) -> ResolveFailure? {
        guard state == .failed, let target = kind.delayedResolveTarget else {
            return nil
        }

        switch kind {
        case .profile:
            if case .failed(let failure) = finalViewState.author {
                return failure
            }
        case .mediaMetadata, .mediaBytes:
            if case .failed(let failure) = finalViewState.media.first {
                return failure
            }
        case .linkPreviewOGP:
            if case .failed(let failure) = finalViewState.linkPreview {
                return failure
            }
        case .repostTarget:
            if case .failed(let failure) = finalViewState.repost {
                return failure
            }
        case .quoteTarget:
            if case .failed(let failure) = finalViewState.quote {
                return failure
            }
        case .replyParent, .replyRoot:
            if case .failed(let failure) = finalViewState.replyContext {
                return failure
            }
        case .bodyMentionProfile, .stats, .publishStatePlaceholder, .unsupported:
            break
        }

        return ResolveFailure(
            target: target,
            fallbackMode: finalViewState.visibility.fallbackMode,
            keepsSourceNoteVisible: finalViewState.visibility.keepsSourceNoteVisible,
            message: "Offline resolve fallback",
            reservedAspectRatio: finalViewState.layoutContract.reservedMediaAspectRatio,
            reservedHeight: finalViewState.layoutContract.reservedMediaHeight
        )
    }

    private static func prioritySort(_ lhs: ResolveRequest, _ rhs: ResolveRequest) -> Bool {
        if lhs.priority.sortRank == rhs.priority.sortRank {
            return lhs.id.rawValue < rhs.id.rawValue
        }
        return lhs.priority.sortRank > rhs.priority.sortRank
    }
}
