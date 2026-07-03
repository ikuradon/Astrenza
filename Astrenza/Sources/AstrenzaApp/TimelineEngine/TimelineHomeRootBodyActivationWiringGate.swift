import Foundation

struct TimelineHomeRootBodyActivationWiringInput: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var activationSwitchResult: TimelineHomeActivatedRouteDecision?
    var context: TimelineHomeRootBodyActivationWiringContext
    var createdAtMS: Int64
}

struct TimelineHomeRootBodyActivationWiringContext: Codable, Equatable, Sendable {
    var productionRootBodyChanged: Bool
    var legacyHomeRenderingPreserved: Bool
    var collectionViewRenderingActivated: Bool
    var mutatingLegacyAndCollectionViewInSameSession: Bool
    var dataSourceApplyFromRootCalled: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool

    static func defaultClean(
        productionRootBodyChanged: Bool = false,
        legacyHomeRenderingPreserved: Bool = true,
        collectionViewRenderingActivated: Bool = false,
        mutatingLegacyAndCollectionViewInSameSession: Bool = false,
        dataSourceApplyFromRootCalled: Bool = false,
        networkStarted: Bool = false,
        dbWriteAttempted: Bool = false,
        readMarkerAdvanced: Bool = false,
        extraNostrHomeTimelineStoreConstructed: Bool = false
    ) -> TimelineHomeRootBodyActivationWiringContext {
        TimelineHomeRootBodyActivationWiringContext(
            productionRootBodyChanged: productionRootBodyChanged,
            legacyHomeRenderingPreserved: legacyHomeRenderingPreserved,
            collectionViewRenderingActivated: collectionViewRenderingActivated,
            mutatingLegacyAndCollectionViewInSameSession: mutatingLegacyAndCollectionViewInSameSession,
            dataSourceApplyFromRootCalled: dataSourceApplyFromRootCalled,
            networkStarted: networkStarted,
            dbWriteAttempted: dbWriteAttempted,
            readMarkerAdvanced: readMarkerAdvanced,
            extraNostrHomeTimelineStoreConstructed: extraNostrHomeTimelineStoreConstructed
        )
    }
}

enum TimelineHomeRootBodyActivationWiringIssueKind: String, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case activationSwitchPresent
    case activationSwitchAllows
    case activationSwitchClean
    case productionRootBodyUnchanged
    case legacyHomeRenderingPreserved
    case collectionViewRenderingNotActivated
    case sameSessionDoubleMutationPrevented
    case rollbackRouteLegacy
    case manualFallbackRouteLegacy
    case dataSourceApplyFromRootNotCalled
    case networkNotStarted
    case dbWriteNotAttempted
    case readMarkerUnchanged
    case noExtraNostrHomeTimelineStore
}

struct TimelineHomeRootBodyActivationWiringArtifactSummary: Codable, Equatable, Sendable {
    var activationSwitchSummary: String
    var rootBodySummary: String
    var issueKinds: [TimelineHomeRootBodyActivationWiringIssueKind]
    var deterministicSummary: String

    static func make(
        activationSwitchResult: TimelineHomeActivatedRouteDecision?,
        result: TimelineHomeRootBodyActivationWiringResult
    ) -> TimelineHomeRootBodyActivationWiringArtifactSummary {
        let activationSwitchSummary = [
            "activationSwitchPresent=\(activationSwitchResult != nil)",
            "activationSwitchAllowed=\(activationSwitchResult?.activationWouldBeAllowed ?? false)",
            "activationSwitchRenderedRoute=\(activationSwitchResult?.renderedRoute.rawValue ?? "none")",
            "activationSwitchPerformed=\(activationSwitchResult?.activationPerformed ?? false)",
            "activationSwitchRenderSwitch=\(activationSwitchResult?.productionRenderSwitchPerformed ?? false)"
        ].joined(separator: " ")
        let rootBodySummary = [
            "rootBodyRenderedRoute=\(result.renderedRouteDecision.rawValue)",
            "productionRootBodyChanged=\(result.productionRootBodyChanged)",
            "legacyHomeRenderingPreserved=\(result.legacyHomeRenderingPreserved)",
            "collectionViewRenderingActivated=\(result.collectionViewRenderingActivated)",
            "sameSessionDoubleMutationPrevented=\(result.sameSessionDoubleMutationPrevented)"
        ].joined(separator: " ")
        let deterministicSummary = [
            "wiringGateEvaluated=\(result.wiringGateEvaluated)",
            "wiringAllowed=\(result.wiringAllowed)",
            "renderedRouteDecision=\(result.renderedRouteDecision.rawValue)",
            "activationPerformed=\(result.activationPerformed)",
            "productionRenderSwitchPerformed=\(result.productionRenderSwitchPerformed)",
            "issues=\(result.issueKinds.map(\.rawValue).debugList)",
            "activationSwitch={\(activationSwitchSummary)}",
            "rootBody={\(rootBodySummary)}"
        ].joined(separator: " ")

        return TimelineHomeRootBodyActivationWiringArtifactSummary(
            activationSwitchSummary: activationSwitchSummary,
            rootBodySummary: rootBodySummary,
            issueKinds: result.issueKinds,
            deterministicSummary: deterministicSummary
        )
    }
}

struct TimelineHomeRootBodyActivationWiringResult: Codable, Equatable, Sendable {
    var wiringGateEvaluated: Bool
    var wiringAllowed: Bool
    var renderedRouteDecision: TimelineHomeRootVisibleRouteDecision
    var productionRootBodyChanged: Bool
    var legacyHomeRenderingPreserved: Bool
    var collectionViewRenderingActivated: Bool
    var sameSessionDoubleMutationPrevented: Bool
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var activationPerformed: Bool
    var productionRenderSwitchPerformed: Bool
    var dataSourceApplyFromRootCalled: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var issueKinds: [TimelineHomeRootBodyActivationWiringIssueKind]
    var artifactSummary: TimelineHomeRootBodyActivationWiringArtifactSummary
    var createdAtMS: Int64

    fileprivate static func make(
        wiringAllowed: Bool,
        context: TimelineHomeRootBodyActivationWiringContext,
        activationSwitchResult: TimelineHomeActivatedRouteDecision?,
        issueKinds: [TimelineHomeRootBodyActivationWiringIssueKind],
        createdAtMS: Int64
    ) -> TimelineHomeRootBodyActivationWiringResult {
        let extraStoreConstructed = context.extraNostrHomeTimelineStoreConstructed
            || (activationSwitchResult.map { !$0.noExtraNostrHomeTimelineStore } ?? false)
        var result = TimelineHomeRootBodyActivationWiringResult(
            wiringGateEvaluated: true,
            wiringAllowed: wiringAllowed,
            renderedRouteDecision: .legacy,
            productionRootBodyChanged: context.productionRootBodyChanged,
            legacyHomeRenderingPreserved: context.legacyHomeRenderingPreserved,
            collectionViewRenderingActivated: context.collectionViewRenderingActivated,
            sameSessionDoubleMutationPrevented: !context.mutatingLegacyAndCollectionViewInSameSession
                && (activationSwitchResult?.preventsDualMutation ?? false),
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy,
            activationPerformed: false,
            productionRenderSwitchPerformed: false,
            dataSourceApplyFromRootCalled: context.dataSourceApplyFromRootCalled
                || (activationSwitchResult?.dataSourceApplyFromRootCalled ?? false),
            networkStarted: context.networkStarted || (activationSwitchResult?.networkStarted ?? false),
            dbWriteAttempted: context.dbWriteAttempted || (activationSwitchResult?.dbWriteAttempted ?? false),
            readMarkerAdvanced: context.readMarkerAdvanced || (activationSwitchResult?.readMarkerAdvanced ?? false),
            extraNostrHomeTimelineStoreConstructed: extraStoreConstructed,
            issueKinds: issueKinds,
            artifactSummary: TimelineHomeRootBodyActivationWiringArtifactSummary(
                activationSwitchSummary: "pending",
                rootBodySummary: "pending",
                issueKinds: issueKinds,
                deterministicSummary: "pending"
            ),
            createdAtMS: createdAtMS
        )
        result.artifactSummary = TimelineHomeRootBodyActivationWiringArtifactSummary.make(
            activationSwitchResult: activationSwitchResult,
            result: result
        )
        return result
    }
}

enum TimelineHomeRootBodyRenderSwitchGate: Sendable {
    static func allowsWiring(
        issueKinds: [TimelineHomeRootBodyActivationWiringIssueKind]
    ) -> Bool {
        issueKinds.isEmpty
    }
}

enum TimelineHomeRootBodyActivationDecision: Sendable {
    static func decide(
        _ input: TimelineHomeRootBodyActivationWiringInput
    ) -> TimelineHomeRootBodyActivationWiringResult {
        let activation = input.activationSwitchResult
        let context = input.context
        var issues: [TimelineHomeRootBodyActivationWiringIssueKind] = []

        append(.explicitCollectionViewLaunchFlag, when: !hasExplicitCollectionViewLaunchFlag(input), to: &issues)
        append(.activationSwitchPresent, when: activation == nil, to: &issues)
        if let activation {
            append(.activationSwitchAllows, when: !activation.activationWouldBeAllowed, to: &issues)
            append(.activationSwitchClean, when: !activationSwitchClean(activation), to: &issues)
            append(.rollbackRouteLegacy, when: activation.rollbackRoute != .legacy, to: &issues)
            append(.manualFallbackRouteLegacy, when: activation.manualFallbackRoute != .legacy, to: &issues)
            append(.networkNotStarted, when: activation.networkStarted, to: &issues)
            append(.dbWriteNotAttempted, when: activation.dbWriteAttempted, to: &issues)
            append(
                .readMarkerUnchanged,
                when: activation.readMarkerChanged || activation.readMarkerAdvanced,
                to: &issues
            )
            append(
                .dataSourceApplyFromRootNotCalled,
                when: activation.dataSourceApplyFromRootCalled
                    || activation.forbiddenDataSourceApplyOutsideCoordinatorCalled,
                to: &issues
            )
            append(.noExtraNostrHomeTimelineStore, when: !activation.noExtraNostrHomeTimelineStore, to: &issues)
            append(.sameSessionDoubleMutationPrevented, when: !activation.preventsDualMutation, to: &issues)
        }

        append(.productionRootBodyUnchanged, when: context.productionRootBodyChanged, to: &issues)
        append(.legacyHomeRenderingPreserved, when: !context.legacyHomeRenderingPreserved, to: &issues)
        append(
            .collectionViewRenderingNotActivated,
            when: context.collectionViewRenderingActivated,
            to: &issues
        )
        append(
            .sameSessionDoubleMutationPrevented,
            when: context.mutatingLegacyAndCollectionViewInSameSession,
            to: &issues
        )
        append(
            .dataSourceApplyFromRootNotCalled,
            when: context.dataSourceApplyFromRootCalled,
            to: &issues
        )
        append(.networkNotStarted, when: context.networkStarted, to: &issues)
        append(.dbWriteNotAttempted, when: context.dbWriteAttempted, to: &issues)
        append(.readMarkerUnchanged, when: context.readMarkerAdvanced, to: &issues)
        append(
            .noExtraNostrHomeTimelineStore,
            when: context.extraNostrHomeTimelineStoreConstructed,
            to: &issues
        )

        return TimelineHomeRootBodyActivationWiringResult.make(
            wiringAllowed: TimelineHomeRootBodyRenderSwitchGate.allowsWiring(issueKinds: issues),
            context: context,
            activationSwitchResult: activation,
            issueKinds: issues,
            createdAtMS: input.createdAtMS
        )
    }

    private static func hasExplicitCollectionViewLaunchFlag(
        _ input: TimelineHomeRootBodyActivationWiringInput
    ) -> Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: input.launchArguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func activationSwitchClean(
        _ result: TimelineHomeActivatedRouteDecision
    ) -> Bool {
        result.activationWouldBeAllowed
            && result.activationPerformed
            && result.productionRenderSwitchPerformed
            && result.renderedRoute == .collectionView
            && result.rollbackRoute == .legacy
            && result.manualFallbackRoute == .legacy
            && result.issueKinds.isEmpty
            && result.routeDiagnosticsRecorded
            && result.activationArtifactChainRecorded
            && result.constructionArtifactChainRecorded
            && result.timelineRestoreGateScope == .timelineArea
            && !result.timelineGateCoversRootShell
            && !result.timelineGateCoversTabBar
            && !result.timelineGateContinuesGlobalSplash
            && !result.networkStarted
            && result.networkWaitedBeforeInteractiveScrollMS == 0
            && !result.readMarkerChanged
            && !result.readMarkerAdvanced
            && !result.dbWriteAttempted
            && !result.requiresNetworkWork
            && !result.requiresDBWrite
            && !result.dataSourceApplyFromRootCalled
            && !result.forbiddenDataSourceApplyOutsideCoordinatorCalled
            && result.coordinatorOwnedDataSourceApplyAllowed
            && result.noExtraNostrHomeTimelineStore
            && result.preventsDualMutation
    }

    private static func append(
        _ issue: TimelineHomeRootBodyActivationWiringIssueKind,
        when condition: Bool,
        to issues: inout [TimelineHomeRootBodyActivationWiringIssueKind]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }
}

enum TimelineHomeRootBodyActivationWiringGate: Sendable {
    static func evaluate(
        _ input: TimelineHomeRootBodyActivationWiringInput
    ) -> TimelineHomeRootBodyActivationWiringResult {
        TimelineHomeRootBodyActivationDecision.decide(input)
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
