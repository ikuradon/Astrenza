import Foundation

enum TimelineHomeStartupSmokeDiagnosticsSource: String, Codable, Equatable, Sendable {
    case flaggedStartupSmoke
}

enum TimelineHomeStartupSmokeDiagnosticsScanStatus: String, Codable, Equatable, Sendable {
    case clean
    case dirty
}

enum TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

enum TimelineHomeStartupSmokeDiagnosticsIssueKind: String, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case cleanRootBodyWiringGate
    case collectionViewRestorePlan
    case timelineAreaRestoreGateOnly
    case networkWaitedBeforeInteractiveScrollZero
    case readMarkerUnchanged
    case dbWriteNotAttempted
    case networkNotStarted
    case dataSourceApplyFromRootNotCalled
    case noExtraNostrHomeTimelineStore
    case sameSessionDoubleMutationPrevented
    case resultBundleScanClean
    case dirtyStartupNetworkScan
    case privacyScanFailure
    case zeroSelectedSuiteCount
}

struct TimelineHomeStartupSmokeSelectedSuiteCount: Codable, Equatable, Sendable {
    var suiteName: String
    var executedTestCount: Int
}

struct TimelineHomeStartupSmokeDiagnosticsAttachment: Codable, Equatable, Sendable {
    static let currentArtifactKind = "timeline_home_startup_smoke_diagnostics_attachment"
    static let currentArtifactVersion = 1

    var artifactKind: String
    var artifactVersion: Int
    var source: TimelineHomeStartupSmokeDiagnosticsSource
    var fixedResultBundlePath: String?
    var redactedResultBundlePathSummary: String
    var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount]
    var zeroSelectedSuiteCount: Bool
    var startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus
    var privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var usedCollectionViewFlag: Bool
    var cleanWiringGateRequired: Bool
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

    static func make(
        from result: TimelineHomeFlaggedStartupSmokeResult,
        fixedResultBundlePath: String?,
        selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount],
        privacyScanPassed: Bool
    ) -> TimelineHomeStartupSmokeDiagnosticsAttachment {
        let startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus =
            result.resultBundleScanPassed && result.startupNetworkPatternHits.isEmpty ? .clean : .dirty
        let zeroSelectedSuiteCount = selectedSuiteCounts.isEmpty
            || selectedSuiteCounts.contains { $0.executedTestCount <= 0 }
        let privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus =
            privacyScanPassed ? .passed : .failed
        let issueKinds = diagnosticsIssueKinds(
            resultIssueKinds: result.issueKinds,
            startupNetworkScanStatus: startupNetworkScanStatus,
            privacyScanStatus: privacyScanStatus,
            zeroSelectedSuiteCount: zeroSelectedSuiteCount
        )

        return TimelineHomeStartupSmokeDiagnosticsAttachment(
            artifactKind: currentArtifactKind,
            artifactVersion: currentArtifactVersion,
            source: .flaggedStartupSmoke,
            fixedResultBundlePath: fixedResultBundlePath,
            redactedResultBundlePathSummary: redactedResultBundlePathSummary(for: fixedResultBundlePath),
            selectedSuiteCounts: selectedSuiteCounts,
            zeroSelectedSuiteCount: zeroSelectedSuiteCount,
            startupNetworkScanStatus: startupNetworkScanStatus,
            privacyScanStatus: privacyScanStatus,
            selectedRoute: result.selectedRoute,
            renderedRoute: result.renderedRoute,
            usedCollectionViewFlag: result.usedCollectionViewFlag,
            cleanWiringGateRequired: true,
            networkWaitedBeforeInteractiveScrollMS: result.networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: result.readMarkerChanged,
            requiresNetworkWork: result.requiresNetworkWork,
            requiresDBWrite: result.requiresDBWrite,
            dataSourceApplyFromRootCalled: result.dataSourceApplyFromRootCalled,
            pendingNewMutated: result.pendingNewMutationAttempted || result.pendingNewVisibleMutationAttempted,
            dbWriteAttempted: result.dbWriteAttempted,
            readMarkerAdvanced: result.readMarkerAdvanced,
            extraNostrHomeTimelineStoreConstructed: result.extraNostrHomeTimelineStoreConstructed,
            issueKinds: issueKinds
        )
    }

    private static func redactedResultBundlePathSummary(for path: String?) -> String {
        guard path != nil else {
            return "fixed result bundle path unavailable"
        }
        return "fixed result bundle path recorded locally"
    }

    private static func diagnosticsIssueKinds(
        resultIssueKinds: [TimelineHomeFlaggedStartupSmokeIssueKind],
        startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus,
        privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus,
        zeroSelectedSuiteCount: Bool
    ) -> [TimelineHomeStartupSmokeDiagnosticsIssueKind] {
        var issueKinds = resultIssueKinds.map(TimelineHomeStartupSmokeDiagnosticsIssueKind.init)
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

struct TimelineHomeStartupSmokeDiagnosticsAttachmentReader: Codable, Equatable, Sendable {
    var attachment: TimelineHomeStartupSmokeDiagnosticsAttachment

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeStartupSmokeDiagnosticsAttachmentReader {
        TimelineHomeStartupSmokeDiagnosticsAttachmentReader(
            attachment: try decoder.decode(
                TimelineHomeStartupSmokeDiagnosticsAttachment.self,
                from: data
            )
        )
    }

    var consumer: TimelineHomeStartupSmokeDiagnosticsConsumer {
        TimelineHomeStartupSmokeDiagnosticsConsumer(attachment: attachment)
    }
}

struct TimelineHomeStartupSmokeDiagnosticsConsumer: Codable, Equatable, Sendable {
    var attachment: TimelineHomeStartupSmokeDiagnosticsAttachment

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeStartupSmokeDiagnosticsConsumer {
        try TimelineHomeStartupSmokeDiagnosticsAttachmentReader
            .decodeFixtureJSON(data, decoder: decoder)
            .consumer
    }

    var selectedRoute: TimelineHomeRootBodyRouteSelection {
        attachment.selectedRoute
    }

    var renderedRoute: TimelineHomeRootVisibleRouteDecision {
        attachment.renderedRoute
    }

    var usedCollectionViewFlag: Bool {
        attachment.usedCollectionViewFlag
    }

    var startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus {
        attachment.startupNetworkScanStatus
    }

    var privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus {
        attachment.privacyScanStatus
    }

    var zeroSelectedSuiteCount: Bool {
        attachment.zeroSelectedSuiteCount
    }

    var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] {
        attachment.selectedSuiteCounts
    }

    var hasSideEffects: Bool {
        attachment.requiresNetworkWork
            || attachment.requiresDBWrite
            || attachment.dataSourceApplyFromRootCalled
            || attachment.pendingNewMutated
            || attachment.dbWriteAttempted
            || attachment.readMarkerChanged
            || attachment.readMarkerAdvanced
            || attachment.extraNostrHomeTimelineStoreConstructed
    }

    var issueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind] {
        attachment.issueKinds
    }

    var debugSummary: TimelineHomeStartupSmokeDiagnosticsSummary {
        TimelineHomeStartupSmokeDiagnosticsSummary.make(from: attachment)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }
}

struct TimelineHomeStartupSmokeDiagnosticsSummary: Codable, Equatable, Sendable {
    var artifactKind: String
    var artifactVersion: Int
    var source: TimelineHomeStartupSmokeDiagnosticsSource
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var usedCollectionViewFlag: Bool
    var zeroSelectedSuiteCount: Bool
    var startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus
    var privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus
    var cleanWiringGateRequired: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var pendingNewMutated: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount]
    var issueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind]

    static func make(
        from attachment: TimelineHomeStartupSmokeDiagnosticsAttachment
    ) -> TimelineHomeStartupSmokeDiagnosticsSummary {
        TimelineHomeStartupSmokeDiagnosticsSummary(
            artifactKind: attachment.artifactKind,
            artifactVersion: attachment.artifactVersion,
            source: attachment.source,
            selectedRoute: attachment.selectedRoute,
            renderedRoute: attachment.renderedRoute,
            usedCollectionViewFlag: attachment.usedCollectionViewFlag,
            zeroSelectedSuiteCount: attachment.zeroSelectedSuiteCount,
            startupNetworkScanStatus: attachment.startupNetworkScanStatus,
            privacyScanStatus: attachment.privacyScanStatus,
            cleanWiringGateRequired: attachment.cleanWiringGateRequired,
            networkWaitedBeforeInteractiveScrollMS: attachment.networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: attachment.readMarkerChanged,
            requiresNetworkWork: attachment.requiresNetworkWork,
            requiresDBWrite: attachment.requiresDBWrite,
            dataSourceApplyFromRootCalled: attachment.dataSourceApplyFromRootCalled,
            pendingNewMutated: attachment.pendingNewMutated,
            dbWriteAttempted: attachment.dbWriteAttempted,
            readMarkerAdvanced: attachment.readMarkerAdvanced,
            extraNostrHomeTimelineStoreConstructed: attachment.extraNostrHomeTimelineStoreConstructed,
            selectedSuiteCounts: attachment.selectedSuiteCounts,
            issueKinds: attachment.issueKinds
        )
    }

    var deterministicText: String {
        [
            "kind=\(artifactKind)",
            "version=\(artifactVersion)",
            "source=\(source.rawValue)",
            "selectedRoute=\(selectedRoute.rawValue)",
            "renderedRoute=\(renderedRoute.rawValue)",
            "usedCollectionViewFlag=\(usedCollectionViewFlag)",
            "zeroSelectedSuiteCount=\(zeroSelectedSuiteCount)",
            "startupNetworkScanStatus=\(startupNetworkScanStatus.rawValue)",
            "privacyScanStatus=\(privacyScanStatus.rawValue)",
            "cleanWiringGateRequired=\(cleanWiringGateRequired)",
            "networkWaitMS=\(networkWaitedBeforeInteractiveScrollMS)",
            "sideEffects(\(sideEffectSummary))",
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

private extension TimelineHomeStartupSmokeDiagnosticsIssueKind {
    init(_ issueKind: TimelineHomeFlaggedStartupSmokeIssueKind) {
        switch issueKind {
        case .explicitCollectionViewLaunchFlag:
            self = .explicitCollectionViewLaunchFlag
        case .cleanRootBodyWiringGate:
            self = .cleanRootBodyWiringGate
        case .collectionViewRestorePlan:
            self = .collectionViewRestorePlan
        case .timelineAreaRestoreGateOnly:
            self = .timelineAreaRestoreGateOnly
        case .networkWaitedBeforeInteractiveScrollZero:
            self = .networkWaitedBeforeInteractiveScrollZero
        case .readMarkerUnchanged:
            self = .readMarkerUnchanged
        case .dbWriteNotAttempted:
            self = .dbWriteNotAttempted
        case .networkNotStarted:
            self = .networkNotStarted
        case .dataSourceApplyFromRootNotCalled:
            self = .dataSourceApplyFromRootNotCalled
        case .noExtraNostrHomeTimelineStore:
            self = .noExtraNostrHomeTimelineStore
        case .sameSessionDoubleMutationPrevented:
            self = .sameSessionDoubleMutationPrevented
        case .resultBundleScanClean:
            self = .resultBundleScanClean
        }
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
