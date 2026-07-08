import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome startup smoke local gate report")
struct TimelineHomeStartupSmokeLocalGateReportTests {
    @Test
    func report_decodes_clean_evidence_bundle() throws {
        let bundle = try makeBundle()
        let consumer = try TimelineHomeStartupSmokeLocalGateReportConsumer.decodeFixtureJSON(encodedData(bundle))

        #expect(consumer.evidenceBundle == bundle)
        #expect(consumer.report.reportKind == TimelineHomeStartupSmokeLocalGateReport.currentReportKind)
        #expect(consumer.report.reportVersion == TimelineHomeStartupSmokeLocalGateReport.currentReportVersion)
        #expect(consumer.report.source == .startupSmokeEvidenceBundle)
        #expect(consumer.summary.source == .startupSmokeEvidenceBundle)
    }

    @Test
    func report_marks_pass_when_all_scans_and_suite_counts_are_clean() throws {
        let report = try makeReport()

        #expect(report.gateStatus == .pass)
        #expect(report.releaseGateFailures.isEmpty)
        #expect(report.blockingIssueKinds.isEmpty)
        #expect(report.nonBlockingIssueKinds.isEmpty)
        #expect(report.noNetworkDBReadMarkerRootApplySideEffects)
    }

    @Test
    func report_marks_fail_when_zero_selected_suite_exists() throws {
        let report = try makeReport(
            selectedSuiteCounts: [
                suiteCount("TimelineHomeStartupSmokeLocalGateReportTests", 0),
                suiteCount("TimelineHomeStartupSmokeEvidenceBundleTests", 15)
            ]
        )

        #expect(report.gateStatus == .fail)
        #expect(report.zeroSelectedSuiteCount)
        #expect(report.selectedSwiftTestingSuitesNonZero == false)
        #expect(report.issueKinds.contains("zeroSelectedSuiteCount"))
        #expect(report.blockingIssueKinds.contains("zeroSelectedSuiteCount"))
        #expect(report.releaseGateFailures.contains("zeroSelectedSuiteCount"))
    }

    @Test
    func report_marks_fail_when_startup_network_scan_dirty() throws {
        let report = try makeReport(startupNetworkScanStatus: .dirty)

        #expect(report.gateStatus == .fail)
        #expect(report.startupNetworkScanStatus == .dirty)
        #expect(report.issueKinds.contains("dirtyStartupNetworkScan"))
        #expect(report.blockingIssueKinds.contains("dirtyStartupNetworkScan"))
        #expect(report.releaseGateFailures.contains("dirtyStartupNetworkScan"))
    }

    @Test
    func report_marks_fail_when_privacy_scan_dirty() throws {
        let report = try makeReport(privacyScanStatus: .failed)

        #expect(report.gateStatus == .fail)
        #expect(report.privacyScanStatus == .failed)
        #expect(report.issueKinds.contains("privacyScanFailure"))
        #expect(report.blockingIssueKinds.contains("privacyScanFailure"))
        #expect(report.releaseGateFailures.contains("privacyScanFailure"))
    }

    @Test
    func report_preserves_fixed_result_bundle_path_summary() throws {
        let report = try makeReport(
            fixedResultBundlePath: nil,
            redactedResultBundlePathSummary: "fixed result bundle path recorded locally"
        )

        #expect(report.fixedResultBundlePathSummary == "fixed result bundle path recorded locally")
    }

    @Test
    func report_preserves_selected_suite_counts() throws {
        let report = try makeReport(selectedSuiteCounts: selectedSuiteCounts)

        #expect(report.selectedSuiteCounts == selectedSuiteCounts)
        #expect(report.totalSelectedTestCount == 98)
        #expect(report.zeroSelectedSuiteCount == false)
        #expect(report.selectedSwiftTestingSuitesNonZero)
    }

    @Test
    func report_preserves_attachment_artifactSummary() throws {
        let bundle = try makeBundle()
        let report = TimelineHomeStartupSmokeLocalGateReport.make(from: bundle)

        #expect(report.artifactSummary == bundle.artifactSummary)
        #expect(report.summary.artifactSummary == bundle.artifactSummary)
        #expect(report.summary.deterministicText.contains(
            "artifactSummary={\(bundle.artifactSummary.deterministicSummary)}"
        ))
    }

    @Test
    func report_preserves_default_legacy_result() throws {
        let report = try makeReport(
            selectedRoute: .legacy,
            renderedRoute: .legacy,
            usedCollectionViewFlag: false,
            issueKinds: [.explicitCollectionViewLaunchFlag]
        )

        #expect(report.selectedRoute == .legacy)
        #expect(report.renderedRoute == .legacy)
        #expect(report.usedCollectionViewFlag == false)
        #expect(report.gateStatus == .fail)
        #expect(report.issueKinds.contains("explicitCollectionViewLaunchFlag"))
    }

    @Test
    func report_preserves_flagged_collectionView_result() throws {
        let report = try makeReport()

        #expect(report.selectedRoute == .collectionView)
        #expect(report.renderedRoute == .collectionView)
        #expect(report.usedCollectionViewFlag)
        #expect(report.gateStatus == .pass)
    }

    @Test
    func report_marks_fail_when_usedCollectionViewFlag_false_even_if_other_fields_clean() throws {
        let report = try makeReport(usedCollectionViewFlag: false)

        #expect(report.gateStatus == .fail)
        #expect(report.usedCollectionViewFlag == false)
        #expect(report.issueKinds.contains("explicitCollectionViewLaunchFlag"))
        #expect(report.blockingIssueKinds.contains("explicitCollectionViewLaunchFlag"))
        #expect(report.releaseGateFailures.contains("explicitCollectionViewLaunchFlag"))
    }

    @Test
    func report_marks_fail_when_selectedRoute_is_legacy_even_if_other_fields_clean() throws {
        let report = try makeReport(selectedRoute: .legacy)

        #expect(report.gateStatus == .fail)
        #expect(report.selectedRoute == .legacy)
        #expect(report.issueKinds.contains("selectedRouteNotCollectionView"))
        #expect(report.blockingIssueKinds.contains("selectedRouteNotCollectionView"))
        #expect(report.releaseGateFailures.contains("selectedRouteNotCollectionView"))
    }

    @Test
    func report_marks_fail_when_renderedRoute_is_legacy_even_if_other_fields_clean() throws {
        let report = try makeReport(renderedRoute: .legacy)

        #expect(report.gateStatus == .fail)
        #expect(report.renderedRoute == .legacy)
        #expect(report.issueKinds.contains("renderedRouteNotCollectionView"))
        #expect(report.blockingIssueKinds.contains("renderedRouteNotCollectionView"))
        #expect(report.releaseGateFailures.contains("renderedRouteNotCollectionView"))
    }

    @Test
    func report_marks_fail_when_clean_looking_bundle_has_no_explicit_collectionView_startup() throws {
        let report = try makeReport(
            selectedRoute: .legacy,
            renderedRoute: .legacy,
            usedCollectionViewFlag: false
        )

        #expect(report.gateStatus == .fail)
        #expect(report.startupNetworkScanStatus == .clean)
        #expect(report.privacyScanStatus == .passed)
        #expect(report.selectedSwiftTestingSuitesNonZero)
        #expect(report.issueKinds.contains("explicitCollectionViewLaunchFlag"))
        #expect(report.issueKinds.contains("selectedRouteNotCollectionView"))
        #expect(report.issueKinds.contains("renderedRouteNotCollectionView"))
    }

    @Test
    func report_marks_fail_when_wiring_gate_evidence_dirty() throws {
        let report = try makeReport(cleanWiringGateRequired: false)

        #expect(report.gateStatus == .fail)
        #expect(report.issueKinds.contains("cleanRootBodyWiringGate"))
        #expect(report.blockingIssueKinds.contains("cleanRootBodyWiringGate"))
        #expect(report.releaseGateFailures.contains("cleanRootBodyWiringGate"))
    }

    @Test
    func report_does_not_encode_raw_bundle_lines() throws {
        let rawBundleLine = [
            "boot",
            ["URL", "Session", "Web", "Socket", "Task"].joined(),
            ["ws", "s://"].joined() + ["relay", ".", "example"].joined()
        ].joined(separator: " ")
        let report = try makeReport(
            startupNetworkScanStatus: .dirty,
            issueKinds: [.dirtyStartupNetworkScan]
        )
        let json = try encodedJSONString(report)

        #expect(!json.contains(rawBundleLine))
        #expect(!json.contains(["URL", "Session", "Web", "Socket", "Task"].joined()))
        #expect(!json.contains(["ws", "s://"].joined()))
        #expect(!json.contains(["relay", ".", "example"].joined()))
    }

    @Test
    func report_does_not_encode_raw_launchArguments() throws {
        let report = try makeReport()
        let json = try encodedJSONString(report)

        #expect(!json.contains("launch" + "Arguments"))
        #expect(!json.contains(["--timeline", "-engine=", "collection", "View"].joined()))
        #expect(!json.contains("[\"Astrenza\""))
    }

    @Test
    func report_does_not_encode_dirty_wss_relay_pubkey_event_secret_fragments() throws {
        let dirtyLine = [
            ["ws", "s://"].joined() + ["relay", ".", "example"].joined(),
            "pub" + "key=" + String(repeating: "a", count: 64),
            "event" + " id=" + String(repeating: "b", count: 64),
            ["n", "sec"].joined() + "1redactedfixture",
            ["private", "message", "content", "phrase"].joined(separator: " ")
        ].joined(separator: " ")
        let report = try makeReport(
            startupNetworkScanStatus: .dirty,
            privacyScanStatus: .passed,
            issueKinds: [.dirtyStartupNetworkScan]
        )
        let json = try encodedJSONString(report).lowercased()

        #expect(!json.contains(dirtyLine.lowercased()))
        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func report_reports_no_network_db_readMarker_pendingNew_rootApply_side_effects() throws {
        let clean = try makeReport()
        let dirty = try makeReport(pendingNewMutated: true)

        #expect(clean.noNetworkDBReadMarkerRootApplySideEffects)
        #expect(dirty.noNetworkDBReadMarkerRootApplySideEffects == false)
        #expect(dirty.gateStatus == .fail)
        #expect(dirty.issueKinds.contains("pendingNewMutated"))
        #expect(dirty.releaseGateFailures.contains("pendingNewMutated"))
    }

    @Test
    func report_marks_fail_for_each_startup_side_effect_sentinel_independently() throws {
        for sentinel in LocalGateSideEffectSentinel.allCases {
            let report = try makeReport(sideEffectSentinel: sentinel)

            #expect(report.gateStatus == .fail)
            #expect(report.noNetworkDBReadMarkerRootApplySideEffects == false)
            #expect(report.selectedSwiftTestingSuitesNonZero)
            #expect(report.zeroSelectedSuiteCount == false)
            #expect(report.usedCollectionViewFlag)
            #expect(report.selectedRoute == .collectionView)
            #expect(report.renderedRoute == .collectionView)
            #expect(Set(report.issueKinds) == [
                sentinel.expectedIssueKind,
                "unexpectedStartupSideEffects"
            ])
            #expect(report.blockingIssueKinds == report.issueKinds)
            #expect(report.releaseGateFailures == report.issueKinds)
            #expect(!report.issueKinds.contains("explicitCollectionViewLaunchFlag"))
            #expect(!report.issueKinds.contains("selectedRouteNotCollectionView"))
            #expect(!report.issueKinds.contains("renderedRouteNotCollectionView"))
            #expect(!report.issueKinds.contains("selectedSwiftTestingSuitesZero"))
            #expect(!report.issueKinds.contains("zeroSelectedSuiteCount"))
            try assertReportJSONPrivacySafe(report)
        }
    }

    @Test
    func report_is_codable_privacy_safe() throws {
        let report = try makeReport()
        let data = try encodedData(report)
        let decoded = try JSONDecoder().decode(TimelineHomeStartupSmokeLocalGateReport.self, from: data)
        let consumer = try TimelineHomeStartupSmokeLocalGateReportConsumer.decodeFixtureJSON(
            encodedData(try makeBundle())
        )
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let summaryJSON = try encodedJSONString(report.summary).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let source = try sourceFile(named: "TimelineHomeStartupSmokeLocalGateReport.swift")

        assertSendable(TimelineHomeStartupSmokeLocalGateReport.self)
        assertSendable(TimelineHomeStartupSmokeLocalGateReportConsumer.self)
        assertSendable(TimelineHomeStartupSmokeLocalGateReportSummary.self)
        assertSendable(TimelineHomeStartupSmokeLocalGateReportSource.self)
        assertSendable(TimelineHomeStartupSmokeLocalGateStatus.self)
        #expect(decoded == report)
        #expect(consumer.report == report)
        #expect(Set(payload.keys) == requiredReportKeys)
        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
            #expect(!summaryJSON.contains(fragment))
        }
        #expect(!source.contains("File" + "Manager"))
        #expect(!source.contains("write" + "(to:"))
        #expect(!source.contains("up" + "load"))
        #expect(!source.contains("tele" + "metry"))
        #expect(!source.contains("ana" + "lytics"))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("Resolve" + "Coordinator"))
        #expect(!source.contains("dataSource." + "apply"))
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        #expect(!selectedSuiteCounts.isEmpty)
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeStartupSmokeLocalGateReportTests", 22)))
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeStartupSmokeEvidenceBundleTests", 15)))
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeStartupSmokeDiagnosticsAttachmentTests", 20)))
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeCollectionViewSimulatorStartupSmokeTests", 16)))
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeFlaggedCollectionViewStartupSmokeTests", 25)))
        #expect(selectedSuiteCounts.allSatisfy { $0.executedTestCount > 0 })
    }
}

private func makeReport(
    fixedResultBundlePath: String? = "/tmp/timeline-home-startup-smoke.xcresult",
    redactedResultBundlePathSummary: String = "fixed result bundle path recorded locally",
    startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus = .clean,
    privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus = .passed,
    selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] = selectedSuiteCounts,
    selectedRoute: TimelineHomeRootBodyRouteSelection = .collectionView,
    renderedRoute: TimelineHomeRootVisibleRouteDecision = .collectionView,
    usedCollectionViewFlag: Bool = true,
    cleanWiringGateRequired: Bool = true,
    pendingNewMutated: Bool = false,
    sideEffectSentinel: LocalGateSideEffectSentinel? = nil,
    issueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind] = []
) throws -> TimelineHomeStartupSmokeLocalGateReport {
    TimelineHomeStartupSmokeLocalGateReport.make(
        from: try makeBundle(
            fixedResultBundlePath: fixedResultBundlePath,
            redactedResultBundlePathSummary: redactedResultBundlePathSummary,
            startupNetworkScanStatus: startupNetworkScanStatus,
            privacyScanStatus: privacyScanStatus,
            selectedSuiteCounts: selectedSuiteCounts,
            selectedRoute: selectedRoute,
            renderedRoute: renderedRoute,
            usedCollectionViewFlag: usedCollectionViewFlag,
            cleanWiringGateRequired: cleanWiringGateRequired,
            pendingNewMutated: pendingNewMutated,
            sideEffectSentinel: sideEffectSentinel,
            issueKinds: issueKinds
        )
    )
}

private func makeBundle(
    fixedResultBundlePath: String? = "/tmp/timeline-home-startup-smoke.xcresult",
    redactedResultBundlePathSummary: String = "fixed result bundle path recorded locally",
    startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus = .clean,
    privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus = .passed,
    selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] = selectedSuiteCounts,
    selectedRoute: TimelineHomeRootBodyRouteSelection = .collectionView,
    renderedRoute: TimelineHomeRootVisibleRouteDecision = .collectionView,
    usedCollectionViewFlag: Bool = true,
    cleanWiringGateRequired: Bool = true,
    pendingNewMutated: Bool = false,
    sideEffectSentinel: LocalGateSideEffectSentinel? = nil,
    issueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind] = []
) throws -> TimelineHomeStartupSmokeEvidenceBundle {
    var attachment = makeAttachment(
        fixedResultBundlePath: fixedResultBundlePath,
        redactedResultBundlePathSummary: redactedResultBundlePathSummary,
        selectedRoute: selectedRoute,
        renderedRoute: renderedRoute,
        usedCollectionViewFlag: usedCollectionViewFlag,
        cleanWiringGateRequired: cleanWiringGateRequired,
        startupNetworkScanStatus: startupNetworkScanStatus,
        privacyScanStatus: privacyScanStatus,
        selectedSuiteCounts: selectedSuiteCounts,
        pendingNewMutated: pendingNewMutated,
        issueKinds: issueKinds
    )
    sideEffectSentinel?.apply(to: &attachment)
    return try TimelineHomeStartupSmokeEvidenceBundle.make(
        attachment: attachment,
        fixedResultBundlePath: attachment.fixedResultBundlePath,
        redactedResultBundlePathSummary: attachment.redactedResultBundlePathSummary,
        selectedSuiteCounts: selectedSuiteCounts,
        startupNetworkScanStatus: startupNetworkScanStatus,
        privacyScanStatus: privacyScanStatus
    )
}

private func makeAttachment(
    fixedResultBundlePath: String?,
    redactedResultBundlePathSummary: String,
    selectedRoute: TimelineHomeRootBodyRouteSelection,
    renderedRoute: TimelineHomeRootVisibleRouteDecision,
    usedCollectionViewFlag: Bool,
    cleanWiringGateRequired: Bool,
    startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus,
    privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus,
    selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount],
    pendingNewMutated: Bool,
    issueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind]
) -> TimelineHomeStartupSmokeDiagnosticsAttachment {
    let launchArgumentSummary = TimelineHomeStartupLaunchArgumentSummary(
        hasCollectionViewFlag: usedCollectionViewFlag,
        requestedEngineMode: usedCollectionViewFlag ? "collectionView" : "legacy",
        knownFlags: usedCollectionViewFlag ? ["timeline-engine=collectionView"] : [],
        unknownArgumentCount: 0,
        redactedUnknownArguments: false
    )
    let artifactSummary = TimelineHomeCollectionViewStartupSmokeArtifact(
        launchArgumentSummary: launchArgumentSummary,
        routeDecisionSummary: "selectedRoute=\(selectedRoute.rawValue) renderedRoute=\(renderedRoute.rawValue)",
        initialRestoreSummary: "gate=initialRestore scope=timelineArea items=1 pendingExcluded=1 hiddenExcluded=0",
        sideEffectSummary: "network=false,dbWrite=false,readMarkerChanged=false,rootApply=false",
        resultBundleSummary: "scanPassed=\(startupNetworkScanStatus == .clean) hits=0",
        deterministicSummary: "startupSmokeLocalGateFixture selectedRoute=\(selectedRoute.rawValue)"
    )

    return TimelineHomeStartupSmokeDiagnosticsAttachment(
        artifactKind: TimelineHomeStartupSmokeDiagnosticsAttachment.currentArtifactKind,
        artifactVersion: TimelineHomeStartupSmokeDiagnosticsAttachment.currentArtifactVersion,
        source: .flaggedStartupSmoke,
        fixedResultBundlePath: fixedResultBundlePath,
        redactedResultBundlePathSummary: redactedResultBundlePathSummary,
        artifactSummary: artifactSummary,
        selectedSuiteCounts: selectedSuiteCounts,
        zeroSelectedSuiteCount: selectedSuiteCounts.isEmpty || selectedSuiteCounts.contains { $0.executedTestCount <= 0 },
        startupNetworkScanStatus: startupNetworkScanStatus,
        privacyScanStatus: privacyScanStatus,
        selectedRoute: selectedRoute,
        renderedRoute: renderedRoute,
        usedCollectionViewFlag: usedCollectionViewFlag,
        cleanWiringGateRequired: cleanWiringGateRequired,
        networkWaitedBeforeInteractiveScrollMS: 0,
        readMarkerChanged: false,
        requiresNetworkWork: false,
        requiresDBWrite: false,
        dataSourceApplyFromRootCalled: false,
        pendingNewMutated: pendingNewMutated,
        dbWriteAttempted: false,
        readMarkerAdvanced: false,
        extraNostrHomeTimelineStoreConstructed: false,
        issueKinds: issueKinds
    )
}

private var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] {
    [
        suiteCount("TimelineHomeStartupSmokeLocalGateReportTests", 22),
        suiteCount("TimelineHomeStartupSmokeEvidenceBundleTests", 15),
        suiteCount("TimelineHomeStartupSmokeDiagnosticsAttachmentTests", 20),
        suiteCount("TimelineHomeCollectionViewSimulatorStartupSmokeTests", 16),
        suiteCount("TimelineHomeFlaggedCollectionViewStartupSmokeTests", 25)
    ]
}

private enum LocalGateSideEffectSentinel: CaseIterable {
    case networkWaitedBeforeInteractiveScrollMS
    case readMarkerChanged
    case requiresNetworkWork
    case requiresDBWrite
    case dataSourceApplyFromRootCalled
    case pendingNewMutated
    case dbWriteAttempted
    case readMarkerAdvanced
    case extraNostrHomeTimelineStoreConstructed

    var expectedIssueKind: String {
        switch self {
        case .networkWaitedBeforeInteractiveScrollMS:
            "networkWaitedBeforeInteractiveScrollNonZero"
        case .readMarkerChanged:
            "readMarkerChanged"
        case .requiresNetworkWork:
            "requiresNetworkWork"
        case .requiresDBWrite:
            "requiresDBWrite"
        case .dataSourceApplyFromRootCalled:
            "dataSourceApplyFromRootCalled"
        case .pendingNewMutated:
            "pendingNewMutated"
        case .dbWriteAttempted:
            "dbWriteAttempted"
        case .readMarkerAdvanced:
            "readMarkerAdvanced"
        case .extraNostrHomeTimelineStoreConstructed:
            "extraNostrHomeTimelineStoreConstructed"
        }
    }

    func apply(to attachment: inout TimelineHomeStartupSmokeDiagnosticsAttachment) {
        switch self {
        case .networkWaitedBeforeInteractiveScrollMS:
            attachment.networkWaitedBeforeInteractiveScrollMS = 1
        case .readMarkerChanged:
            attachment.readMarkerChanged = true
        case .requiresNetworkWork:
            attachment.requiresNetworkWork = true
        case .requiresDBWrite:
            attachment.requiresDBWrite = true
        case .dataSourceApplyFromRootCalled:
            attachment.dataSourceApplyFromRootCalled = true
        case .pendingNewMutated:
            attachment.pendingNewMutated = true
        case .dbWriteAttempted:
            attachment.dbWriteAttempted = true
        case .readMarkerAdvanced:
            attachment.readMarkerAdvanced = true
        case .extraNostrHomeTimelineStoreConstructed:
            attachment.extraNostrHomeTimelineStoreConstructed = true
        }
    }
}

private func suiteCount(
    _ suiteName: String,
    _ executedTestCount: Int
) -> TimelineHomeStartupSmokeSelectedSuiteCount {
    TimelineHomeStartupSmokeSelectedSuiteCount(
        suiteName: suiteName,
        executedTestCount: executedTestCount
    )
}

private var requiredReportKeys: Set<String> {
    [
        "reportKind",
        "reportVersion",
        "source",
        "gateStatus",
        "fixedResultBundlePathSummary",
        "startupNetworkScanStatus",
        "privacyScanStatus",
        "selectedSuiteCounts",
        "totalSelectedTestCount",
        "zeroSelectedSuiteCount",
        "selectedSwiftTestingSuitesNonZero",
        "selectedRoute",
        "renderedRoute",
        "usedCollectionViewFlag",
        "artifactSummary",
        "issueKinds",
        "blockingIssueKinds",
        "nonBlockingIssueKinds",
        "releaseGateFailures",
        "noNetworkDBReadMarkerRootApplySideEffects"
    ]
}

private var forbiddenPrivacyFragments: [String] {
    [
        ["n", "sec"].joined(),
        ["sec", "ret"].joined(),
        ["private", "key"].joined(),
        ["private", "_", "key"].joined(),
        ["raw", "_", "json"].joined(),
        ["raw", "event"].joined(),
        ["raw", "_", "event"].joined(),
        ["mne", "monic"].joined(),
        ["key", "chain"].joined(),
        ["nostr", ["sec", "ret"].joined()].joined(separator: " "),
        ["relay", "url"].joined(separator: " "),
        ["pub", "key"].joined(),
        ["event", "id"].joined(separator: " "),
        ["event", "id"].joined(),
        ["event", "_", "id"].joined(),
        ["private", "message", "content", "phrase"].joined(separator: " ")
    ]
}

private func encodedData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    try #require(String(data: encodedData(value), encoding: .utf8))
}

private func assertReportJSONPrivacySafe(
    _ report: TimelineHomeStartupSmokeLocalGateReport
) throws {
    let data = try encodedData(report)
    let decoded = try JSONDecoder().decode(TimelineHomeStartupSmokeLocalGateReport.self, from: data)
    let json = try #require(String(data: data, encoding: .utf8))
    let lowercasedJSON = json.lowercased()
    let rawBundleLine = [
        "boot",
        ["URL", "Session", "Web", "Socket", "Task"].joined(),
        ["ws", "s://"].joined() + ["relay", ".", "example"].joined()
    ].joined(separator: " ")

    #expect(decoded == report)
    #expect(!json.contains(rawBundleLine))
    #expect(!json.contains(["URL", "Session", "Web", "Socket", "Task"].joined()))
    #expect(!json.contains(["ws", "s://"].joined()))
    #expect(!json.contains(["relay", ".", "example"].joined()))
    #expect(!json.contains("launch" + "Arguments"))
    #expect(!json.contains(["--timeline", "-engine=", "collection", "View"].joined()))
    #expect(!json.contains("[\"Astrenza\""))
    for fragment in forbiddenPrivacyFragments {
        #expect(!lowercasedJSON.contains(fragment))
    }
}

private func sourceFile(named fileName: String) throws -> String {
    let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/AstrenzaApp")
    return try String(
        contentsOf: appRoot.appendingPathComponent("TimelineEngine/\(fileName)"),
        encoding: .utf8
    )
}

private func assertSendable<T: Sendable>(_: T.Type) {}
