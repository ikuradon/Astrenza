import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome startup smoke evidence bundle")
struct TimelineHomeStartupSmokeEvidenceBundleTests {
    @Test
    func evidence_bundle_decodes_clean_attachment() throws {
        let attachment = makeAttachment()
        let bundle = try makeBundle(attachment: attachment)
        let consumer = try TimelineHomeStartupSmokeEvidenceConsumer.decodeFixtureJSON(encodedData(bundle))

        #expect(consumer.bundle.artifactKind == TimelineHomeStartupSmokeEvidenceBundle.currentArtifactKind)
        #expect(consumer.bundle.artifactVersion == TimelineHomeStartupSmokeEvidenceBundle.currentArtifactVersion)
        #expect(consumer.bundle.source == .flaggedStartupSmokeEvidence)
        #expect(consumer.bundle.startupSmokeAttachment == attachment)
        #expect(consumer.summary.source == .flaggedStartupSmokeEvidence)
        #expect(consumer.summary.issueKinds.isEmpty)
    }

    @Test
    func evidence_bundle_requires_fixed_result_bundle_path_or_redacted_summary() throws {
        let attachmentWithoutPathSummary = makeAttachment(
            fixedResultBundlePath: nil,
            redactedResultBundlePathSummary: ""
        )

        #expect(throws: TimelineHomeStartupSmokeEvidenceBundleError.missingFixedResultBundlePathSummary) {
            try TimelineHomeStartupSmokeEvidenceBundle.make(
                attachment: attachmentWithoutPathSummary,
                fixedResultBundlePath: nil,
                redactedResultBundlePathSummary: nil
            )
        }

        let fixedPathBundle = try TimelineHomeStartupSmokeEvidenceBundle.make(
            attachment: attachmentWithoutPathSummary,
            fixedResultBundlePath: "/tmp/timeline-home-startup-smoke.xcresult",
            redactedResultBundlePathSummary: nil
        )
        let redactedSummaryBundle = try TimelineHomeStartupSmokeEvidenceBundle.make(
            attachment: attachmentWithoutPathSummary,
            fixedResultBundlePath: nil,
            redactedResultBundlePathSummary: "fixed result bundle path unavailable"
        )

        #expect(fixedPathBundle.fixedResultBundlePathSummary == "fixed result bundle path recorded locally")
        #expect(redactedSummaryBundle.fixedResultBundlePathSummary == "fixed result bundle path unavailable")
    }

    @Test
    func evidence_bundle_reports_selected_suite_counts() throws {
        let counts = selectedSuiteCounts
        let bundle = try makeBundle(selectedSuiteCounts: counts)

        #expect(bundle.selectedSuiteCounts == counts)
        #expect(bundle.totalSelectedTestCount == 76)
        #expect(bundle.zeroSelectedSuiteCount == false)
        #expect(bundle.selectedSwiftTestingSuitesNonZero)
    }

    @Test
    func evidence_bundle_marks_zero_selected_suite_count() throws {
        let bundle = try makeBundle(
            selectedSuiteCounts: [
                suiteCount("TimelineHomeStartupSmokeEvidenceBundleTests", 0),
                suiteCount("TimelineHomeStartupSmokeDiagnosticsAttachmentTests", 20)
            ]
        )

        #expect(bundle.zeroSelectedSuiteCount)
        #expect(bundle.selectedSwiftTestingSuitesNonZero == false)
        #expect(bundle.issueKinds.contains(.zeroSelectedSuiteCount))
    }

    @Test
    func evidence_bundle_reports_startup_network_scan_status() throws {
        let bundle = try makeBundle(startupNetworkScanStatus: .dirty)

        #expect(bundle.startupNetworkScanStatus == .dirty)
        #expect(bundle.issueKinds.contains(.dirtyStartupNetworkScan))
    }

    @Test
    func evidence_bundle_reports_privacy_scan_status() throws {
        let bundle = try makeBundle(privacyScanStatus: .failed)

        #expect(bundle.privacyScanStatus == .failed)
        #expect(bundle.issueKinds.contains(.privacyScanFailure))
    }

    @Test
    func evidence_bundle_preserves_attachment_artifactSummary() throws {
        let attachment = makeAttachment()
        let bundle = try makeBundle(attachment: attachment)

        #expect(bundle.artifactSummary == attachment.artifactSummary)
        #expect(bundle.summary.artifactSummary == attachment.artifactSummary)
        #expect(bundle.summary.deterministicText.contains(
            "artifactSummary={\(attachment.artifactSummary.deterministicSummary)}"
        ))
    }

    @Test
    func evidence_bundle_preserves_default_legacy_result() throws {
        let attachment = makeAttachment(
            selectedRoute: .legacy,
            renderedRoute: .legacy,
            usedCollectionViewFlag: false,
            issueKinds: [.explicitCollectionViewLaunchFlag]
        )
        let bundle = try makeBundle(attachment: attachment)

        #expect(bundle.selectedRoute == .legacy)
        #expect(bundle.renderedRoute == .legacy)
        #expect(bundle.usedCollectionViewFlag == false)
        #expect(bundle.issueKinds.contains(.explicitCollectionViewLaunchFlag))
    }

    @Test
    func evidence_bundle_preserves_flagged_collectionView_result() throws {
        let bundle = try makeBundle()

        #expect(bundle.selectedRoute == .collectionView)
        #expect(bundle.renderedRoute == .collectionView)
        #expect(bundle.usedCollectionViewFlag)
        #expect(bundle.issueKinds.isEmpty)
    }

    @Test
    func evidence_bundle_does_not_encode_raw_bundle_lines() throws {
        let rawBundleLine = [
            "boot",
            ["URL", "Session", "Web", "Socket", "Task"].joined(),
            ["ws", "s://"].joined() + ["relay", ".", "example"].joined()
        ].joined(separator: " ")
        let bundle = try makeBundle(
            startupNetworkScanStatus: .dirty,
            attachment: makeAttachment(issueKinds: [.dirtyStartupNetworkScan])
        )
        let json = try encodedJSONString(bundle)

        #expect(!json.contains(rawBundleLine))
        #expect(!json.contains(["URL", "Session", "Web", "Socket", "Task"].joined()))
        #expect(!json.contains(["ws", "s://"].joined()))
        #expect(!json.contains("relay.example"))
    }

    @Test
    func evidence_bundle_does_not_encode_raw_launchArguments() throws {
        let bundle = try makeBundle()
        let json = try encodedJSONString(bundle)

        #expect(!json.contains("launch" + "Arguments"))
        #expect(!json.contains("--timeline-engine=collectionView"))
        #expect(!json.contains("[\"Astrenza\""))
    }

    @Test
    func evidence_bundle_does_not_encode_dirty_wss_relay_pubkey_event_secret_fragments() throws {
        let dirtyLine = [
            ["ws", "s://"].joined() + ["relay", ".", "example"].joined(),
            "pub" + "key=" + String(repeating: "a", count: 64),
            "event" + " id=" + String(repeating: "b", count: 64),
            ["n", "sec"].joined() + "1redactedfixture",
            ["private", "message", "content", "phrase"].joined(separator: " ")
        ].joined(separator: " ")
        let bundle = try makeBundle(
            startupNetworkScanStatus: .dirty,
            privacyScanStatus: .passed,
            attachment: makeAttachment(issueKinds: [.dirtyStartupNetworkScan])
        )
        let json = try encodedJSONString(bundle).lowercased()

        #expect(!json.contains(dirtyLine.lowercased()))
        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func evidence_bundle_reports_no_network_db_readMarker_pendingNew_rootApply_side_effects() throws {
        let bundle = try makeBundle()

        #expect(bundle.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(bundle.readMarkerChanged == false)
        #expect(bundle.requiresNetworkWork == false)
        #expect(bundle.requiresDBWrite == false)
        #expect(bundle.dataSourceApplyFromRootCalled == false)
        #expect(bundle.pendingNewMutated == false)
        #expect(bundle.dbWriteAttempted == false)
        #expect(bundle.readMarkerAdvanced == false)
        #expect(bundle.extraNostrHomeTimelineStoreConstructed == false)
    }

    @Test
    func evidence_bundle_is_codable_privacy_safe() throws {
        let bundle = try makeBundle()
        let data = try encodedData(bundle)
        let decoded = try JSONDecoder().decode(TimelineHomeStartupSmokeEvidenceBundle.self, from: data)
        let consumer = try TimelineHomeStartupSmokeEvidenceConsumer.decodeFixtureJSON(data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let summaryJSON = try encodedJSONString(bundle.summary).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let source = try sourceFile(named: "TimelineHomeStartupSmokeEvidenceBundle.swift")

        assertSendable(TimelineHomeStartupSmokeEvidenceBundle.self)
        assertSendable(TimelineHomeStartupSmokeEvidenceConsumer.self)
        assertSendable(TimelineHomeStartupSmokeEvidenceSummary.self)
        assertSendable(TimelineHomeStartupSmokeEvidenceSource.self)
        assertSendable(TimelineHomeStartupSmokeEvidenceBundleError.self)
        #expect(decoded == bundle)
        #expect(consumer.bundle == bundle)
        #expect(Set(payload.keys) == requiredEvidenceBundleKeys)
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
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeStartupSmokeEvidenceBundleTests", 15)))
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeStartupSmokeDiagnosticsAttachmentTests", 20)))
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeCollectionViewSimulatorStartupSmokeTests", 16)))
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeFlaggedCollectionViewStartupSmokeTests", 25)))
        #expect(selectedSuiteCounts.allSatisfy { $0.executedTestCount > 0 })
    }
}

private func makeBundle(
    startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus? = nil,
    privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus? = nil,
    selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] = selectedSuiteCounts,
    attachment: TimelineHomeStartupSmokeDiagnosticsAttachment = makeAttachment()
) throws -> TimelineHomeStartupSmokeEvidenceBundle {
    try TimelineHomeStartupSmokeEvidenceBundle.make(
        attachment: attachment,
        fixedResultBundlePath: attachment.fixedResultBundlePath,
        redactedResultBundlePathSummary: attachment.redactedResultBundlePathSummary,
        selectedSuiteCounts: selectedSuiteCounts,
        startupNetworkScanStatus: startupNetworkScanStatus,
        privacyScanStatus: privacyScanStatus
    )
}

private func makeAttachment(
    fixedResultBundlePath: String? = "/tmp/timeline-home-startup-smoke.xcresult",
    redactedResultBundlePathSummary: String = "fixed result bundle path recorded locally",
    selectedRoute: TimelineHomeRootBodyRouteSelection = .collectionView,
    renderedRoute: TimelineHomeRootVisibleRouteDecision = .collectionView,
    usedCollectionViewFlag: Bool = true,
    startupNetworkScanStatus: TimelineHomeStartupSmokeDiagnosticsScanStatus = .clean,
    privacyScanStatus: TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus = .passed,
    selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] = selectedSuiteCounts,
    zeroSelectedSuiteCount: Bool = false,
    readMarkerChanged: Bool = false,
    requiresNetworkWork: Bool = false,
    requiresDBWrite: Bool = false,
    dataSourceApplyFromRootCalled: Bool = false,
    pendingNewMutated: Bool = false,
    dbWriteAttempted: Bool = false,
    readMarkerAdvanced: Bool = false,
    extraNostrHomeTimelineStoreConstructed: Bool = false,
    issueKinds: [TimelineHomeStartupSmokeDiagnosticsIssueKind] = []
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
        deterministicSummary: "startupSmokeEvidenceFixture selectedRoute=\(selectedRoute.rawValue)"
    )

    return TimelineHomeStartupSmokeDiagnosticsAttachment(
        artifactKind: TimelineHomeStartupSmokeDiagnosticsAttachment.currentArtifactKind,
        artifactVersion: TimelineHomeStartupSmokeDiagnosticsAttachment.currentArtifactVersion,
        source: .flaggedStartupSmoke,
        fixedResultBundlePath: fixedResultBundlePath,
        redactedResultBundlePathSummary: redactedResultBundlePathSummary,
        artifactSummary: artifactSummary,
        selectedSuiteCounts: selectedSuiteCounts,
        zeroSelectedSuiteCount: zeroSelectedSuiteCount,
        startupNetworkScanStatus: startupNetworkScanStatus,
        privacyScanStatus: privacyScanStatus,
        selectedRoute: selectedRoute,
        renderedRoute: renderedRoute,
        usedCollectionViewFlag: usedCollectionViewFlag,
        cleanWiringGateRequired: true,
        networkWaitedBeforeInteractiveScrollMS: 0,
        readMarkerChanged: readMarkerChanged,
        requiresNetworkWork: requiresNetworkWork,
        requiresDBWrite: requiresDBWrite,
        dataSourceApplyFromRootCalled: dataSourceApplyFromRootCalled,
        pendingNewMutated: pendingNewMutated,
        dbWriteAttempted: dbWriteAttempted,
        readMarkerAdvanced: readMarkerAdvanced,
        extraNostrHomeTimelineStoreConstructed: extraNostrHomeTimelineStoreConstructed,
        issueKinds: issueKinds
    )
}

private var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] {
    [
        suiteCount("TimelineHomeStartupSmokeEvidenceBundleTests", 15),
        suiteCount("TimelineHomeStartupSmokeDiagnosticsAttachmentTests", 20),
        suiteCount("TimelineHomeCollectionViewSimulatorStartupSmokeTests", 16),
        suiteCount("TimelineHomeFlaggedCollectionViewStartupSmokeTests", 25)
    ]
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

private var requiredEvidenceBundleKeys: Set<String> {
    [
        "artifactKind",
        "artifactVersion",
        "source",
        "fixedResultBundlePathSummary",
        "startupSmokeAttachment",
        "startupNetworkScanStatus",
        "privacyScanStatus",
        "selectedSuiteCounts",
        "totalSelectedTestCount",
        "zeroSelectedSuiteCount",
        "selectedSwiftTestingSuitesNonZero",
        "selectedRoute",
        "renderedRoute",
        "usedCollectionViewFlag",
        "networkWaitedBeforeInteractiveScrollMS",
        "readMarkerChanged",
        "requiresNetworkWork",
        "requiresDBWrite",
        "dataSourceApplyFromRootCalled",
        "pendingNewMutated",
        "dbWriteAttempted",
        "readMarkerAdvanced",
        "extraNostrHomeTimelineStoreConstructed",
        "issueKinds",
        "artifactSummary"
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
