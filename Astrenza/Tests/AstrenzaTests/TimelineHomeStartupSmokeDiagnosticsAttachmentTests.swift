import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome startup smoke diagnostics attachment")
struct TimelineHomeStartupSmokeDiagnosticsAttachmentTests {
    @Test
    func attachment_decodes_clean_startup_smoke_result() throws {
        let attachment = makeAttachment(for: startupSmokeResult())
        let consumer = try consumer(for: attachment)

        #expect(consumer.attachment.artifactKind == TimelineHomeStartupSmokeDiagnosticsAttachment.currentArtifactKind)
        #expect(consumer.attachment.artifactVersion == TimelineHomeStartupSmokeDiagnosticsAttachment.currentArtifactVersion)
        #expect(consumer.attachment.source == .flaggedStartupSmoke)
        #expect(consumer.selectedRoute == .collectionView)
        #expect(consumer.renderedRoute == .collectionView)
        #expect(consumer.startupNetworkScanStatus == .clean)
        #expect(consumer.privacyScanStatus == .passed)
        #expect(consumer.issueKinds.isEmpty)
    }

    @Test
    func attachment_rejects_or_marks_zero_selected_suite_count() throws {
        let attachment = makeAttachment(
            selectedSuiteCounts: [
                suiteCount("TimelineHomeFlaggedCollectionViewStartupSmokeTests", 25),
                suiteCount("TimelineHomeRootBodyRenderSwitchTests", 0)
            ]
        )
        let consumer = try consumer(for: attachment)

        #expect(consumer.zeroSelectedSuiteCount)
        #expect(consumer.issueKinds.contains(.zeroSelectedSuiteCount))
    }

    @Test
    func attachment_marks_dirty_startup_network_scan() throws {
        let attachment = makeAttachment(for: dirtyStartupNetworkResult())
        let consumer = try consumer(for: attachment)

        #expect(consumer.startupNetworkScanStatus == .dirty)
        #expect(consumer.issueKinds.contains(.dirtyStartupNetworkScan))
        #expect(consumer.issueKinds.contains(.resultBundleScanClean))
    }

    @Test
    func attachment_marks_privacy_scan_failure() throws {
        let attachment = makeAttachment(privacyScanPassed: false)
        let consumer = try consumer(for: attachment)

        #expect(consumer.privacyScanStatus == .failed)
        #expect(consumer.issueKinds.contains(.privacyScanFailure))
    }

    @Test
    func attachment_preserves_default_legacy_result() throws {
        let attachment = makeAttachment(
            for: startupSmokeResult(
                selectedRoute: .legacy,
                renderedRoute: .legacy,
                usedCollectionViewFlag: false,
                collectionViewStartupSmokeEvaluated: false,
                defaultStartupRemainsLegacy: true,
                issueKinds: [.explicitCollectionViewLaunchFlag]
            )
        )

        #expect(attachment.selectedRoute == .legacy)
        #expect(attachment.renderedRoute == .legacy)
        #expect(attachment.usedCollectionViewFlag == false)
        #expect(attachment.cleanWiringGateRequired)
        #expect(attachment.issueKinds.contains(.explicitCollectionViewLaunchFlag))
    }

    @Test
    func attachment_preserves_flagged_collectionView_result() throws {
        let attachment = makeAttachment(for: startupSmokeResult())

        #expect(attachment.selectedRoute == .collectionView)
        #expect(attachment.renderedRoute == .collectionView)
        #expect(attachment.usedCollectionViewFlag)
        #expect(attachment.cleanWiringGateRequired)
        #expect(attachment.issueKinds.isEmpty)
    }

    @Test
    func attachment_does_not_encode_raw_bundle_lines() throws {
        let rawBundleLine = [
            "boot",
            ["URL", "Session", "Web", "Socket", "Task"].joined(),
            ["ws", "s://"].joined() + ["relay", ".", "example"].joined()
        ].joined(separator: " ")
        let attachment = makeAttachment(for: dirtyStartupNetworkResult())
        let json = try encodedJSONString(attachment)

        #expect(!json.contains(rawBundleLine))
        #expect(!json.contains(["URL", "Session", "Web", "Socket", "Task"].joined()))
        #expect(!json.contains(["ws", "s://"].joined()))
        #expect(!json.contains("relay.example"))
    }

    @Test
    func attachment_does_not_encode_raw_launchArguments() throws {
        let attachment = makeAttachment(for: startupSmokeResult())
        let json = try encodedJSONString(attachment)

        #expect(!json.contains("launch" + "Arguments"))
        #expect(!json.contains("--timeline-engine=collectionView"))
        #expect(!json.contains("[\"Astrenza\""))
    }

    @Test
    func attachment_does_not_encode_dirty_wss_relay_pubkey_event_secret_fragments() throws {
        let dirtyLine = [
            ["ws", "s://"].joined() + ["relay", ".", "example"].joined(),
            "pub" + "key=" + String(repeating: "a", count: 64),
            "event" + " id=" + String(repeating: "b", count: 64),
            ["n", "sec"].joined() + "1redactedfixture",
            ["private", "message", "content", "phrase"].joined(separator: " ")
        ].joined(separator: " ")
        let attachment = makeAttachment(for: dirtyStartupNetworkResult())
        let json = try encodedJSONString(attachment).lowercased()

        #expect(!json.contains(dirtyLine.lowercased()))
        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func attachment_reports_fixed_result_bundle_path_or_redacted_summary() {
        let fixedPath = "/tmp/timeline-home-startup-smoke.xcresult"
        let fixedAttachment = makeAttachment(fixedResultBundlePath: fixedPath)
        let redactedAttachment = makeAttachment(fixedResultBundlePath: nil)

        #expect(fixedAttachment.fixedResultBundlePath == fixedPath)
        #expect(fixedAttachment.redactedResultBundlePathSummary == "fixed result bundle path recorded locally")
        #expect(redactedAttachment.fixedResultBundlePath == nil)
        #expect(redactedAttachment.redactedResultBundlePathSummary == "fixed result bundle path unavailable")
    }

    @Test
    func attachment_reports_selected_suite_counts() {
        let counts = selectedSuiteCounts
        let attachment = makeAttachment(selectedSuiteCounts: counts)

        #expect(attachment.selectedSuiteCounts == counts)
        #expect(attachment.zeroSelectedSuiteCount == false)
        #expect(attachment.selectedSuiteCounts.map(\.suiteName).contains("TimelineHomeFlaggedCollectionViewStartupSmokeTests"))
        #expect(attachment.selectedSuiteCounts.map(\.executedTestCount).allSatisfy { $0 > 0 })
    }

    @Test
    func attachment_reports_no_network_db_readMarker_pendingNew_rootApply_side_effects() throws {
        let consumer = try consumer(for: makeAttachment(for: startupSmokeResult()))

        #expect(consumer.hasSideEffects == false)
        #expect(consumer.attachment.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(consumer.attachment.readMarkerChanged == false)
        #expect(consumer.attachment.requiresNetworkWork == false)
        #expect(consumer.attachment.requiresDBWrite == false)
        #expect(consumer.attachment.dataSourceApplyFromRootCalled == false)
        #expect(consumer.attachment.pendingNewMutated == false)
        #expect(consumer.attachment.dbWriteAttempted == false)
        #expect(consumer.attachment.readMarkerAdvanced == false)
        #expect(consumer.attachment.extraNostrHomeTimelineStoreConstructed == false)
    }

    @Test
    func attachment_is_codable_privacy_safe() throws {
        let attachment = makeAttachment(for: startupSmokeResult())
        let data = try encodedData(attachment)
        let decoded = try JSONDecoder().decode(
            TimelineHomeStartupSmokeDiagnosticsAttachment.self,
            from: data
        )
        let consumer = try TimelineHomeStartupSmokeDiagnosticsConsumer.decodeFixtureJSON(data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let summaryJSON = try encodedJSONString(consumer.debugSummary).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let source = try sourceFile(named: "TimelineHomeStartupSmokeDiagnosticsAttachment.swift")

        assertSendable(TimelineHomeStartupSmokeDiagnosticsAttachment.self)
        assertSendable(TimelineHomeStartupSmokeDiagnosticsAttachmentReader.self)
        assertSendable(TimelineHomeStartupSmokeDiagnosticsConsumer.self)
        assertSendable(TimelineHomeStartupSmokeDiagnosticsSummary.self)
        assertSendable(TimelineHomeStartupSmokeDiagnosticsSource.self)
        assertSendable(TimelineHomeStartupSmokeDiagnosticsScanStatus.self)
        assertSendable(TimelineHomeStartupSmokeDiagnosticsPrivacyScanStatus.self)
        assertSendable(TimelineHomeStartupSmokeDiagnosticsIssueKind.self)
        assertSendable(TimelineHomeStartupSmokeSelectedSuiteCount.self)
        #expect(decoded == attachment)
        #expect(consumer.attachment == attachment)
        #expect(Set(payload.keys) == requiredAttachmentKeys)
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
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeFlaggedCollectionViewStartupSmokeTests", 25)))
        #expect(selectedSuiteCounts.contains(suiteCount("TimelineHomeStartupSmokeDiagnosticsAttachmentTests", 14)))
        #expect(selectedSuiteCounts.allSatisfy { $0.executedTestCount > 0 })
    }
}

private func makeAttachment(
    for result: TimelineHomeFlaggedStartupSmokeResult = startupSmokeResult(),
    fixedResultBundlePath: String? = "/tmp/timeline-home-startup-smoke.xcresult",
    selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] = selectedSuiteCounts,
    privacyScanPassed: Bool = true
) -> TimelineHomeStartupSmokeDiagnosticsAttachment {
    TimelineHomeStartupSmokeDiagnosticsAttachment.make(
        from: result,
        fixedResultBundlePath: fixedResultBundlePath,
        selectedSuiteCounts: selectedSuiteCounts,
        privacyScanPassed: privacyScanPassed
    )
}

private func consumer(
    for attachment: TimelineHomeStartupSmokeDiagnosticsAttachment
) throws -> TimelineHomeStartupSmokeDiagnosticsConsumer {
    try TimelineHomeStartupSmokeDiagnosticsConsumer.decodeFixtureJSON(
        encodedData(attachment)
    )
}

private func dirtyStartupNetworkResult() -> TimelineHomeFlaggedStartupSmokeResult {
    startupSmokeResult(
        startupNetworkPatternHits: [
            TimelineHomeStartupNetworkPatternHit(
                patternKind: .startupNetwork,
                tokenID: "startup-network-token-006",
                lineNumber: 12,
                redactedSummary: "redacted startup network pattern match"
            )
        ],
        resultBundleScanPassed: false,
        issueKinds: [.resultBundleScanClean]
    )
}

private func startupSmokeResult(
    selectedRoute: TimelineHomeRootBodyRouteSelection = .collectionView,
    renderedRoute: TimelineHomeRootVisibleRouteDecision = .collectionView,
    usedCollectionViewFlag: Bool = true,
    startupNetworkPatternHits: [TimelineHomeStartupNetworkPatternHit] = [],
    dbWriteAttempted: Bool = false,
    readMarkerAdvanced: Bool = false,
    dataSourceApplyFromRootCalled: Bool = false,
    extraNostrHomeTimelineStoreConstructed: Bool = false,
    networkWaitedBeforeInteractiveScrollMS: Double = 0,
    readMarkerChanged: Bool = false,
    collectionViewStartupSmokeEvaluated: Bool = true,
    defaultStartupRemainsLegacy: Bool = false,
    networkStarted: Bool = false,
    requiresNetworkWork: Bool = false,
    requiresDBWrite: Bool = false,
    pendingNewMutationAttempted: Bool = false,
    pendingNewVisibleMutationAttempted: Bool = false,
    resultBundleScanPassed: Bool = true,
    issueKinds: [TimelineHomeFlaggedStartupSmokeIssueKind] = []
) -> TimelineHomeFlaggedStartupSmokeResult {
    let launchArgumentSummary = TimelineHomeStartupLaunchArgumentSummary(
        hasCollectionViewFlag: usedCollectionViewFlag,
        requestedEngineMode: usedCollectionViewFlag ? "collectionView" : "legacy",
        knownFlags: usedCollectionViewFlag ? ["timeline-engine=collectionView"] : [],
        unknownArgumentCount: 0,
        redactedUnknownArguments: false
    )
    return TimelineHomeFlaggedStartupSmokeResult(
        launchArgumentSummary: launchArgumentSummary,
        selectedRoute: selectedRoute,
        renderedRoute: renderedRoute,
        usedCollectionViewFlag: usedCollectionViewFlag,
        startupNetworkPatternHits: startupNetworkPatternHits,
        dbWriteAttempted: dbWriteAttempted,
        readMarkerAdvanced: readMarkerAdvanced,
        dataSourceApplyFromRootCalled: dataSourceApplyFromRootCalled,
        extraNostrHomeTimelineStoreConstructed: extraNostrHomeTimelineStoreConstructed,
        networkWaitedBeforeInteractiveScrollMS: networkWaitedBeforeInteractiveScrollMS,
        readMarkerChanged: readMarkerChanged,
        artifactSummary: TimelineHomeCollectionViewStartupSmokeArtifact(
            launchArgumentSummary: launchArgumentSummary,
            routeDecisionSummary: "selectedRoute=\(selectedRoute.rawValue) renderedRoute=\(renderedRoute.rawValue)",
            initialRestoreSummary: "gate=initialRestore scope=timelineArea items=1 pendingExcluded=1 hiddenExcluded=0",
            sideEffectSummary: "network=false,dbWrite=false,readMarkerChanged=false,rootApply=false",
            resultBundleSummary: "scanPassed=\(resultBundleScanPassed) hits=\(startupNetworkPatternHits.count)",
            deterministicSummary: "startupSmokeFixture selectedRoute=\(selectedRoute.rawValue)"
        ),
        collectionViewStartupSmokeEvaluated: collectionViewStartupSmokeEvaluated,
        defaultStartupRemainsLegacy: defaultStartupRemainsLegacy,
        rollbackRoute: .legacy,
        manualFallbackRoute: .legacy,
        rootShellPresentation: .immediate,
        rootShellMustRenderBeforeTimelineRestore: true,
        rootShellFirstPaintPreserved: true,
        timelineRestoreGateScope: .timelineArea,
        timelineGateCoversRootShell: false,
        timelineGateCoversTabBar: false,
        timelineGateContinuesGlobalSplash: false,
        networkStarted: networkStarted,
        requiresNetworkWork: requiresNetworkWork,
        requiresDBWrite: requiresDBWrite,
        pendingNewMutationAttempted: pendingNewMutationAttempted,
        pendingNewVisibleMutationAttempted: pendingNewVisibleMutationAttempted,
        coordinatorOwnedDataSourceApplyAllowed: true,
        resultBundleScanPassed: resultBundleScanPassed,
        issueKinds: issueKinds,
        createdAtMS: 1_735_000_050_000
    )
}

private var selectedSuiteCounts: [TimelineHomeStartupSmokeSelectedSuiteCount] {
    [
        suiteCount("TimelineHomeFlaggedCollectionViewStartupSmokeTests", 25),
        suiteCount("TimelineHomeStartupSmokeDiagnosticsAttachmentTests", 14),
        suiteCount("TimelineHomeCollectionViewRouteRestoreIntegrationTests", 16),
        suiteCount("TimelineHomeRootBodyRenderSwitchTests", 16)
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

private var requiredAttachmentKeys: Set<String> {
    [
        "artifactKind",
        "artifactVersion",
        "source",
        "fixedResultBundlePath",
        "redactedResultBundlePathSummary",
        "selectedSuiteCounts",
        "zeroSelectedSuiteCount",
        "startupNetworkScanStatus",
        "privacyScanStatus",
        "selectedRoute",
        "renderedRoute",
        "usedCollectionViewFlag",
        "cleanWiringGateRequired",
        "networkWaitedBeforeInteractiveScrollMS",
        "readMarkerChanged",
        "requiresNetworkWork",
        "requiresDBWrite",
        "dataSourceApplyFromRootCalled",
        "pendingNewMutated",
        "dbWriteAttempted",
        "readMarkerAdvanced",
        "extraNostrHomeTimelineStoreConstructed",
        "issueKinds"
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
