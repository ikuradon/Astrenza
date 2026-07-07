import Foundation

enum TimelineHomeStartupSmokeEvidenceSource: String, Codable, Equatable, Sendable {
    case flaggedStartupSmokeEvidence
}

enum TimelineHomeStartupSmokeEvidenceBundleError: Error, Equatable, Sendable {
    case missingFixedResultBundlePathSummary
}

struct TimelineHomeStartupSmokeEvidenceBundle: Codable, Equatable, Sendable {
    static let currentArtifactKind = "timeline_home_startup_smoke_evidence_bundle"
    static let currentArtifactVersion = 1

    var artifactKind: String
    var artifactVersion: Int
    var source: TimelineHomeStartupSmokeEvidenceSource
    var fixedResultBundlePathSummary: String
    var startupSmokeAttachment: TimelineHomeStartupSmokeDiagnosticsAttachment
    var startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus
    var privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus
    var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount]
    var totalSelectedTestCount: Int
    var zeroSelectedSuiteCount: Bool
    var selectedSwiftTestingSuitesNonZero: Bool
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var usedCollectionViewFlag: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var pendingNewMutated: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var issueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind]
    var artifactSummary: TimelineHomeCollectionViewStartupSmokeArtifact

    static func make(
        attachment: TimelineHomeStartupSmokeDiagnosticsAttachment,
        fixedResultBundlePath: String? = nil,
        redactedResultBundlePathSummary: String? = nil,
        selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount]? = nil,
        startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus? = nil,
        privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus? = nil
    ) throws -> TimelineHomeStartupSmokeEvidenceBundle {
        let fixedResultBundlePathSummary = try fixedResultBundlePathSummary(
            fixedResultBundlePath: fixedResultBundlePath,
            attachmentFixedResultBundlePath: attachment.fixedResultBundlePath,
            redactedResultBundlePathSummary: redactedResultBundlePathSummary,
            attachmentRedactedResultBundlePathSummary: attachment.redactedResultBundlePathSummary
        )
        let resolvedSelectedSuiteCounts = selectedSuiteCounts ?? attachment.selectedSuiteCounts
        let totalSelectedTestCount = resolvedSelectedSuiteCounts.reduce(0) {
            $0 + max(0, $1.executedTestCount)
        }
        let zeroSelectedSuiteCount = resolvedSelectedSuiteCounts.isEmpty ||
            resolvedSelectedSuiteCounts.contains { $0.executedTestCount <= 0 }
        let selectedSwiftTestingSuitesNonZero = !zeroSelectedSuiteCount
        let resolvedStartupNetworkScanStatus = startupNetworkScanStatus ?? attachment.startupNetworkScanStatus
        let resolvedPrivacyScanStatus = privacyScanStatus ?? attachment.privacyScanStatus
        let issueKinds = evidenceIssueKinds(
            attachmentIssueKinds: attachment.issueKinds,
            startupNetworkScanStatus: resolvedStartupNetworkScanStatus,
            privacyScanStatus: resolvedPrivacyScanStatus,
            zeroSelectedSuiteCount: zeroSelectedSuiteCount
        )

        return TimelineHomeStartupSmokeEvidenceBundle(
            artifactKind: currentArtifactKind,
            artifactVersion: currentArtifactVersion,
            source: .flaggedStartupSmokeEvidence,
            fixedResultBundlePathSummary: fixedResultBundlePathSummary,
            startupSmokeAttachment: attachment,
            startupNetworkScanStatus: resolvedStartupNetworkScanStatus,
            privacyScanStatus: resolvedPrivacyScanStatus,
            selectedSuiteCounts: resolvedSelectedSuiteCounts,
            totalSelectedTestCount: totalSelectedTestCount,
            zeroSelectedSuiteCount: zeroSelectedSuiteCount,
            selectedSwiftTestingSuitesNonZero: selectedSwiftTestingSuitesNonZero,
            selectedRoute: attachment.selectedRoute,
            renderedRoute: attachment.renderedRoute,
            usedCollectionViewFlag: attachment.usedCollectionViewFlag,
            networkWaitedBeforeInteractiveScrollMS: attachment.networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: attachment.readMarkerChanged,
            requiresNetworkWork: attachment.requiresNetworkWork,
            requiresDBWrite: attachment.requiresDBWrite,
            dataSourceApplyFromRootCalled: attachment.dataSourceApplyFromRootCalled,
            pendingNewMutated: attachment.pendingNewMutated,
            dbWriteAttempted: attachment.dbWriteAttempted,
            readMarkerAdvanced: attachment.readMarkerAdvanced,
            extraNostrHomeTimelineStoreConstructed: attachment.extraNostrHomeTimelineStoreConstructed,
            issueKinds: issueKinds,
            artifactSummary: attachment.artifactSummary
        )
    }

    var summary: TimelineHomeStartupSmokeEvidenceSummary {
        TimelineHomeStartupSmokeEvidenceSummary.make(from: self)
    }

    private static func fixedResultBundlePathSummary(
        fixedResultBundlePath: String?,
        attachmentFixedResultBundlePath: String?,
        redactedResultBundlePathSummary: String?,
        attachmentRedactedResultBundlePathSummary: String
    ) throws -> String {
        if fixedResultBundlePath?.isEmpty == false || attachmentFixedResultBundlePath?.isEmpty == false {
            return "fixed result bundle path recorded locally"
        }

        if let redactedResultBundlePathSummary,
           !redactedResultBundlePathSummary.isEmpty {
            return redactedResultBundlePathSummary
        }

        guard !attachmentRedactedResultBundlePathSummary.isEmpty else {
            throw TimelineHomeStartupSmokeEvidenceBundleError.missingFixedResultBundlePathSummary
        }
        return attachmentRedactedResultBundlePathSummary
    }

    private static func evidenceIssueKinds(
        attachmentIssueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind],
        startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus,
        privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus,
        zeroSelectedSuiteCount: Bool
    ) -> [TimelineHomeStartupSmokeDiagnosticsIssueKind] {
        var issueKinds = attachmentIssueKinds
        append(.dirtyStartupNetworkScan, when: startupNetworkScanStatus == .dirty, to: &issueKinds)
        append(.privacyScanFailure, when: privacyScanStatus == .failed, to: &issueKinds)
        append(.zeroSelectedSuiteCount, when: zeroSelectedSuiteCount, to: &issueKinds)
        return issueKinds
    }

    private static func append(
        _ issueKind: TimelineHomeStartupSmokeDiagnosticsIssueKind,
        when condition: Bool,
        to issueKinds: inout [TimelineHomeStartupSmokeDiagnosticsIssueKind]
    ) {
        guard condition, !issueKinds.contains(issueKind) else { return }
        issueKinds.append(issueKind)
    }
}

struct TimelineHomeStartupSmokeEvidenceConsumer: Codable, Equatable, Sendable {
    var bundle: TimelineHomeStartupSmokeEvidenceBundle

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeStartupSmokeEvidenceConsumer {
        TimelineHomeStartupSmokeEvidenceConsumer(
            bundle: try decoder.decode(
                TimelineHomeStartupSmokeEvidenceBundle.self,
                from: data
            )
        )
    }

    var summary: TimelineHomeStartupSmokeEvidenceSummary {
        bundle.summary
    }

    var deterministicDebugSummary: String {
        summary.deterministicText
    }
}

struct TimelineHomeStartupSmokeEvidenceSummary: Codable, Equatable, Sendable {
    var artifactKind: String
    var artifactVersion: Int
    var source: TimelineHomeStartupSmokeEvidenceSource
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
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var pendingNewMutated: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var issueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind]
    var artifactSummary: TimelineHomeCollectionViewStartupSmokeArtifact

    static func make(
        from bundle: TimelineHomeStartupSmokeEvidenceBundle
    ) -> TimelineHomeStartupSmokeEvidenceSummary {
        TimelineHomeStartupSmokeEvidenceSummary(
            artifactKind: bundle.artifactKind,
            artifactVersion: bundle.artifactVersion,
            source: bundle.source,
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
            networkWaitedBeforeInteractiveScrollMS: bundle.networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: bundle.readMarkerChanged,
            requiresNetworkWork: bundle.requiresNetworkWork,
            requiresDBWrite: bundle.requiresDBWrite,
            dataSourceApplyFromRootCalled: bundle.dataSourceApplyFromRootCalled,
            pendingNewMutated: bundle.pendingNewMutated,
            dbWriteAttempted: bundle.dbWriteAttempted,
            readMarkerAdvanced: bundle.readMarkerAdvanced,
            extraNostrHomeTimelineStoreConstructed: bundle.extraNostrHomeTimelineStoreConstructed,
            issueKinds: bundle.issueKinds,
            artifactSummary: bundle.artifactSummary
        )
    }

    var deterministicText: String {
        [
            "kind=\(artifactKind)",
            "version=\(artifactVersion)",
            "source=\(source.rawValue)",
            "fixedResultBundlePathSummary=\(fixedResultBundlePathSummary)",
            "startupNetworkScanStatus=\(startupNetworkScanStatus.rawValue)",
            "privacyScanStatus=\(privacyScanStatus.rawValue)",
            "selectedRoute=\(selectedRoute.rawValue)",
            "renderedRoute=\(renderedRoute.rawValue)",
            "usedCollectionViewFlag=\(usedCollectionViewFlag)",
            "totalSelectedTestCount=\(totalSelectedTestCount)",
            "zeroSelectedSuiteCount=\(zeroSelectedSuiteCount)",
            "selectedSwiftTestingSuitesNonZero=\(selectedSwiftTestingSuitesNonZero)",
            "networkWaitMS=\(networkWaitedBeforeInteractiveScrollMS)",
            "sideEffects(\(sideEffectSummary))",
            "artifactSummary={\(artifactSummary.deterministicSummary)}",
            "suiteCounts=\(selectedSuiteCounts.debugSummary)",
            "issueKinds=\(issueKinds.map(\.rawValue).debugList)"
        ].joined(separator: " ")
    }

    private var sideEffectSummary: String {
        [
            "readMarkerChanged=\(readMarkerChanged)",
            "requiresNetworkWork=\(requiresNetworkWork)",
            "requiresDBWrite=\(requiresDBWrite)",
            "dataSourceApplyFromRoot=\(dataSourceApplyFromRootCalled)",
            "pendingNewMutated=\(pendingNewMutated)",
            "dbWriteAttempted=\(dbWriteAttempted)",
            "readMarkerAdvanced=\(readMarkerAdvanced)",
            "extraNostrHomeTimelineStore=\(extraNostrHomeTimelineStoreConstructed)"
        ].joined(separator: ",")
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
