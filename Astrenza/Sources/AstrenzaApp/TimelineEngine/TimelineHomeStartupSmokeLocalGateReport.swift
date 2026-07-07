import Foundation

enum TimelineHomeStartupSmokeLocalGateReportSource: String, Codable, Equatable, Sendable {
    case startupSmokeEvidenceBundle
}

enum TimelineHomeStartupSmokeLocalGateStatus: String, Codable, Equatable, Sendable {
    case pass
    case fail
}

struct TimelineHomeStartupSmokeLocalGateReport: Codable, Equatable, Sendable {
    static let currentReportKind = "timeline_home_startup_smoke_local_gate_report"
    static let currentReportVersion = 1

    var reportKind: String
    var reportVersion: Int
    var source: TimelineHomeStartupSmokeLocalGateReportSource
    var gateStatus: TimelineHomeStartupSmokeLocalGateStatus
    var fixedResultBundlePathSummary: String
    var startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus
    var privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus
    var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount]
    var totalSelectedTestCount: Int
    var zeroSelectedSuiteCount: Bool
    var selectedSwiftTestingSuitesNonZero: Bool
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var usedCollectionViewFlag: Bool
    var artifactSummary: TimelineHomeCollectionViewStartupSmokeArtifact
    var issueKinds: [String]
    var blockingIssueKinds: [String]
    var nonBlockingIssueKinds: [String]
    var releaseGateFailures: [String]
    var noNetworkDBReadMarkerRootApplySideEffects: Bool

    static func make(
        from bundle: TimelineHomeStartupSmokeEvidenceBundle
    ) -> TimelineHomeStartupSmokeLocalGateReport {
        let noSideEffects = noNetworkDBReadMarkerRootApplySideEffects(in: bundle)
        let explicitCollectionViewStartupEvidence = explicitCollectionViewStartupEvidence(in: bundle)
        let cleanRootBodyWiringGateEvidence = cleanRootBodyWiringGateEvidence(in: bundle)
        let issueKinds = localIssueKinds(from: bundle, noSideEffects: noSideEffects)
        let gateStatus: TimelineHomeStartupSmokeLocalGateStatus = issueKinds.isEmpty
            && explicitCollectionViewStartupEvidence
            && cleanRootBodyWiringGateEvidence
            && noSideEffects
            && bundle.startupNetworkScanStatus == .clean
            && bundle.privacyScanStatus == .passed
            && bundle.selectedSwiftTestingSuitesNonZero
            && !bundle.zeroSelectedSuiteCount
            ? .pass
            : .fail

        return TimelineHomeStartupSmokeLocalGateReport(
            reportKind: currentReportKind,
            reportVersion: currentReportVersion,
            source: .startupSmokeEvidenceBundle,
            gateStatus: gateStatus,
            fixedResultBundlePathSummary: bundle.fixedResultBundlePathSummary,
            startupNetworkScanStatus: bundle.startupNetworkScanStatus,
            privacyScanStatus: bundle.privacyScanStatus,
            selectedSuiteCounts: bundle.selectedSuiteCounts,
            totalSelectedTestCount: bundle.totalSelectedTestCount,
            zeroSelectedSuiteCount: bundle.zeroSelectedSuiteCount,
            selectedSwiftTestingSuitesNonZero: bundle.selectedSwiftTestingSuitesNonZero,
            selectedRoute: bundle.selectedRoute,
            renderedRoute: bundle.renderedRoute,
            usedCollectionViewFlag: bundle.usedCollectionViewFlag,
            artifactSummary: bundle.artifactSummary,
            issueKinds: issueKinds,
            blockingIssueKinds: issueKinds,
            nonBlockingIssueKinds: [],
            releaseGateFailures: issueKinds,
            noNetworkDBReadMarkerRootApplySideEffects: noSideEffects
        )
    }

    var summary: TimelineHomeStartupSmokeLocalGateReportSummary {
        TimelineHomeStartupSmokeLocalGateReportSummary.make(from: self)
    }

    private static func noNetworkDBReadMarkerRootApplySideEffects(
        in bundle: TimelineHomeStartupSmokeEvidenceBundle
    ) -> Bool {
        bundle.networkWaitedBeforeInteractiveScrollMS == 0
            && !bundle.readMarkerChanged
            && !bundle.requiresNetworkWork
            && !bundle.requiresDBWrite
            && !bundle.dataSourceApplyFromRootCalled
            && !bundle.pendingNewMutated
            && !bundle.dbWriteAttempted
            && !bundle.readMarkerAdvanced
            && !bundle.extraNostrHomeTimelineStoreConstructed
    }

    private static func explicitCollectionViewStartupEvidence(
        in bundle: TimelineHomeStartupSmokeEvidenceBundle
    ) -> Bool {
        bundle.usedCollectionViewFlag
            && bundle.selectedRoute == .collectionView
            && bundle.renderedRoute == .collectionView
    }

    private static func cleanRootBodyWiringGateEvidence(
        in bundle: TimelineHomeStartupSmokeEvidenceBundle
    ) -> Bool {
        bundle.startupSmokeAttachment.cleanWiringGateRequired
    }

    private static func localIssueKinds(
        from bundle: TimelineHomeStartupSmokeEvidenceBundle,
        noSideEffects: Bool
    ) -> [String] {
        var issueKinds = bundle.issueKinds.map(\.rawValue)
        append(
            TimelineHomeStartupSmokeDiagnosticsIssueKind.explicitCollectionViewLaunchFlag.rawValue,
            when: !bundle.usedCollectionViewFlag,
            to: &issueKinds
        )
        append(
            "selectedRouteNotCollectionView",
            when: bundle.selectedRoute != .collectionView,
            to: &issueKinds
        )
        append(
            "renderedRouteNotCollectionView",
            when: bundle.renderedRoute != .collectionView,
            to: &issueKinds
        )
        append(
            TimelineHomeStartupSmokeDiagnosticsIssueKind.cleanRootBodyWiringGate.rawValue,
            when: !cleanRootBodyWiringGateEvidence(in: bundle),
            to: &issueKinds
        )
        append("dirtyStartupNetworkScan", when: bundle.startupNetworkScanStatus == .dirty, to: &issueKinds)
        append("privacyScanFailure", when: bundle.privacyScanStatus == .failed, to: &issueKinds)
        append("zeroSelectedSuiteCount", when: bundle.zeroSelectedSuiteCount, to: &issueKinds)
        append(
            "selectedSwiftTestingSuitesZero",
            when: !bundle.selectedSwiftTestingSuitesNonZero,
            to: &issueKinds
        )
        append(
            "networkWaitedBeforeInteractiveScrollNonZero",
            when: bundle.networkWaitedBeforeInteractiveScrollMS != 0,
            to: &issueKinds
        )
        append("readMarkerChanged", when: bundle.readMarkerChanged, to: &issueKinds)
        append("requiresNetworkWork", when: bundle.requiresNetworkWork, to: &issueKinds)
        append("requiresDBWrite", when: bundle.requiresDBWrite, to: &issueKinds)
        append("dataSourceApplyFromRootCalled", when: bundle.dataSourceApplyFromRootCalled, to: &issueKinds)
        append("pendingNewMutated", when: bundle.pendingNewMutated, to: &issueKinds)
        append("dbWriteAttempted", when: bundle.dbWriteAttempted, to: &issueKinds)
        append("readMarkerAdvanced", when: bundle.readMarkerAdvanced, to: &issueKinds)
        append(
            "extraNostrHomeTimelineStoreConstructed",
            when: bundle.extraNostrHomeTimelineStoreConstructed,
            to: &issueKinds
        )
        append("unexpectedStartupSideEffects", when: !noSideEffects, to: &issueKinds)
        return issueKinds
    }

    private static func append(
        _ issueKind: String,
        when condition: Bool,
        to issueKinds: inout [String]
    ) {
        guard condition, !issueKinds.contains(issueKind) else { return }
        issueKinds.append(issueKind)
    }
}

struct TimelineHomeStartupSmokeLocalGateReportConsumer: Codable, Equatable, Sendable {
    var evidenceBundle: TimelineHomeStartupSmokeEvidenceBundle

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeStartupSmokeLocalGateReportConsumer {
        TimelineHomeStartupSmokeLocalGateReportConsumer(
            evidenceBundle: try decoder.decode(
                TimelineHomeStartupSmokeEvidenceBundle.self,
                from: data
            )
        )
    }

    var report: TimelineHomeStartupSmokeLocalGateReport {
        TimelineHomeStartupSmokeLocalGateReport.make(from: evidenceBundle)
    }

    var summary: TimelineHomeStartupSmokeLocalGateReportSummary {
        report.summary
    }

    var deterministicDebugSummary: String {
        summary.deterministicText
    }
}

struct TimelineHomeStartupSmokeLocalGateReportSummary: Codable, Equatable, Sendable {
    var reportKind: String
    var reportVersion: Int
    var source: TimelineHomeStartupSmokeLocalGateReportSource
    var gateStatus: TimelineHomeStartupSmokeLocalGateStatus
    var fixedResultBundlePathSummary: String
    var startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus
    var privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus
    var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount]
    var totalSelectedTestCount: Int
    var zeroSelectedSuiteCount: Bool
    var selectedSwiftTestingSuitesNonZero: Bool
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var usedCollectionViewFlag: Bool
    var artifactSummary: TimelineHomeCollectionViewStartupSmokeArtifact
    var issueKinds: [String]
    var blockingIssueKinds: [String]
    var nonBlockingIssueKinds: [String]
    var releaseGateFailures: [String]
    var noNetworkDBReadMarkerRootApplySideEffects: Bool

    static func make(
        from report: TimelineHomeStartupSmokeLocalGateReport
    ) -> TimelineHomeStartupSmokeLocalGateReportSummary {
        TimelineHomeStartupSmokeLocalGateReportSummary(
            reportKind: report.reportKind,
            reportVersion: report.reportVersion,
            source: report.source,
            gateStatus: report.gateStatus,
            fixedResultBundlePathSummary: report.fixedResultBundlePathSummary,
            startupNetworkScanStatus: report.startupNetworkScanStatus,
            privacyScanStatus: report.privacyScanStatus,
            selectedSuiteCounts: report.selectedSuiteCounts,
            totalSelectedTestCount: report.totalSelectedTestCount,
            zeroSelectedSuiteCount: report.zeroSelectedSuiteCount,
            selectedSwiftTestingSuitesNonZero: report.selectedSwiftTestingSuitesNonZero,
            selectedRoute: report.selectedRoute,
            renderedRoute: report.renderedRoute,
            usedCollectionViewFlag: report.usedCollectionViewFlag,
            artifactSummary: report.artifactSummary,
            issueKinds: report.issueKinds,
            blockingIssueKinds: report.blockingIssueKinds,
            nonBlockingIssueKinds: report.nonBlockingIssueKinds,
            releaseGateFailures: report.releaseGateFailures,
            noNetworkDBReadMarkerRootApplySideEffects: report.noNetworkDBReadMarkerRootApplySideEffects
        )
    }

    var deterministicText: String {
        [
            "kind=\(reportKind)",
            "version=\(reportVersion)",
            "source=\(source.rawValue)",
            "gateStatus=\(gateStatus.rawValue)",
            "fixedResultBundlePathSummary=\(fixedResultBundlePathSummary)",
            "startupNetworkScanStatus=\(startupNetworkScanStatus.rawValue)",
            "privacyScanStatus=\(privacyScanStatus.rawValue)",
            "selectedRoute=\(selectedRoute.rawValue)",
            "renderedRoute=\(renderedRoute.rawValue)",
            "usedCollectionViewFlag=\(usedCollectionViewFlag)",
            "totalSelectedTestCount=\(totalSelectedTestCount)",
            "zeroSelectedSuiteCount=\(zeroSelectedSuiteCount)",
            "selectedSwiftTestingSuitesNonZero=\(selectedSwiftTestingSuitesNonZero)",
            "noNetworkDBReadMarkerRootApplySideEffects=\(noNetworkDBReadMarkerRootApplySideEffects)",
            "artifactSummary={\(artifactSummary.deterministicSummary)}",
            "suiteCounts=\(selectedSuiteCounts.debugSummary)",
            "issueKinds=\(issueKinds.debugList)",
            "blockingIssueKinds=\(blockingIssueKinds.debugList)",
            "nonBlockingIssueKinds=\(nonBlockingIssueKinds.debugList)",
            "releaseGateFailures=\(releaseGateFailures.debugList)"
        ].joined(separator: " ")
    }
}

private extension Array where Element == TimelineHomeStartupSmokeSelectedSuiteCount {
    var debugSummary: String {
        map { "\($0.suiteName):\($0.executedTestCount)" }
            .joined(separator: ",")
            .wrappedForDebugList
    }
}

private extension Array where Element == String {
    var debugList: String {
        joined(separator: ",").wrappedForDebugList
    }
}

private extension String {
    var wrappedForDebugList: String {
        "[\(self)]"
    }
}
