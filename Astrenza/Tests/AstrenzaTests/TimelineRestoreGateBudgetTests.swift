import Foundation
import Testing
@testable import Astrenza

@Suite("Timeline restore gate budget metrics")
struct TimelineRestoreGateBudgetTests {
    @Test("Gate duration at target is within budget")
    func gateDurationAtTargetIsWithinBudget() {
        let metric = TimelineRestoreGateMetricBuilder.metric(
            stage: .restoreGate,
            durationMS: 250,
            budget: .restoreGate,
            timestampMS: 1_735_000_000_000
        )

        #expect(metric.durationMS == 250)
        #expect(metric.budgetResult == .withinBudget)
        #expect(metric.exceededReason == nil)
        #expect(!metric.exceededBudget)
    }

    @Test("Gate duration over target and below hard limit is over target")
    func gateDurationOverTargetAndBelowHardLimitIsOverTarget() {
        let metric = TimelineRestoreGateMetricBuilder.metric(
            stage: .restoreGate,
            durationMS: 300,
            budget: .restoreGate,
            timestampMS: 1_735_000_000_000
        )

        #expect(metric.budgetResult == .overTarget)
        #expect(metric.exceededReason == nil)
        #expect(!metric.exceededBudget)
    }

    @Test("Gate duration beyond hard limit is exceeded budget")
    func gateDurationBeyondHardLimitIsExceededBudget() {
        let metric = TimelineRestoreGateMetricBuilder.metric(
            stage: .restoreGate,
            durationMS: 501,
            budget: .restoreGate,
            timestampMS: 1_735_000_000_000
        )

        #expect(metric.budgetResult == .exceededBudget)
        #expect(metric.exceededReason == .restoreGateDurationExceededHardLimit)
        #expect(metric.exceededBudget)
    }

    @Test("Restore work stages can be represented separately from first interactive scroll")
    func restoreWorkStagesCanBeRepresentedSeparatelyFromFirstInteractiveScroll() throws {
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            timestampMS: 1_735_000_000_000
        )

        #expect(diagnostics.metric(for: .localInitialWindowQuery)?.durationMS == 42)
        #expect(diagnostics.metric(for: .initialSnapshotApplying)?.durationMS == 61)
        #expect(diagnostics.metric(for: .anchorRestoring)?.durationMS == 12)
        #expect(diagnostics.metric(for: .restoreGate)?.durationMS == 180)
        #expect(diagnostics.firstInteractiveScrollAllowedAtMS == 1_735_000_000_180)
        #expect(diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(diagnostics.isValidForRelease)
    }

    @Test("Nonzero network wait before interactive scroll is release blocking")
    func nonzeroNetworkWaitBeforeInteractiveScrollIsReleaseBlocking() {
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 40,
            initialSnapshotApplyDurationMS: 60,
            anchorRestoreDurationMS: 10,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            networkWaitedBeforeInteractiveScrollMS: 1,
            timestampMS: 1_735_000_000_000
        )

        #expect(!diagnostics.isValidForRelease)
        #expect(diagnostics.releaseBlockingReasons == [.networkWaitedBeforeInteractiveScroll])
        #expect(diagnostics.networkWaitedBeforeInteractiveScrollMS == 1)
        #expect(diagnostics.metric(for: .localInitialWindowQuery)?.exceededReason == nil)
        #expect(diagnostics.metric(for: .restoreGate)?.budgetResult == .withinBudget)
    }

    @Test("Zero network wait before interactive scroll is valid")
    func zeroNetworkWaitBeforeInteractiveScrollIsValid() {
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 40,
            initialSnapshotApplyDurationMS: 60,
            anchorRestoreDurationMS: 10,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            networkWaitedBeforeInteractiveScrollMS: 0,
            timestampMS: 1_735_000_000_000
        )

        #expect(diagnostics.isValidForRelease)
        #expect(diagnostics.releaseBlockingReasons.isEmpty)
    }

    @Test("Read marker changed defaults false")
    func readMarkerChangedDefaultsFalse() {
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 40,
            initialSnapshotApplyDurationMS: 60,
            anchorRestoreDurationMS: 10,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            timestampMS: 1_735_000_000_000
        )

        #expect(!diagnostics.readMarkerChanged)
        #expect(diagnostics.releaseBlockingReasons.isEmpty)
    }

    @Test("Exceeded budget records inline fallback without continuing splash or network wait")
    func exceededBudgetRecordsInlineFallbackWithoutContinuingSplashOrNetworkWait() {
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 180,
            initialSnapshotApplyDurationMS: 120,
            anchorRestoreDurationMS: 44,
            restoreGateDurationMS: 501,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_501,
            networkWaitedBeforeInteractiveScrollMS: 0,
            fallbackPresentation: .inlineSkeleton,
            timestampMS: 1_735_000_000_000
        )

        #expect(diagnostics.budgetResult == .exceededBudget)
        #expect(diagnostics.exceededReasons == [.restoreGateDurationExceededHardLimit])
        #expect(diagnostics.fallbackPresentation == .inlineSkeleton)
        #expect(!diagnostics.continuesSplash)
        #expect(diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
    }

    @Test("Restore gate diagnostics are codable and offline")
    func restoreGateDiagnosticsAreCodableAndOffline() throws {
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            timestampMS: 1_735_000_000_000
        )

        #expect(!diagnostics.requiresNetworkWork)
        #expect(!diagnostics.requiresDBWork)

        let data = try JSONEncoder().encode(diagnostics)
        let decoded = try JSONDecoder().decode(TimelineRestoreGateDiagnostics.self, from: data)

        #expect(decoded == diagnostics)
    }

    @Test("Recorder exports within-budget restore gate diagnostics")
    func recorderExportsWithinBudgetRestoreGateDiagnostics() throws {
        let recorder = TimelineDiagnosticsRecorder()
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            networkWaitedBeforeInteractiveScrollMS: 0,
            timestampMS: 1_735_000_000_000
        )

        let recorded = recorder.recordRestoreGateDiagnostics(diagnostics)
        let export = recorder.export()
        let exported = try #require(export.restoreGateDiagnostics.first)
        let firstInteractiveMetric = try #require(exported.metric(for: .firstInteractiveScrollReady))

        #expect(recorded == diagnostics)
        #expect(export.restoreGateDiagnostics == [diagnostics])
        #expect(exported.metric(for: .localInitialWindowQuery)?.durationMS == 42)
        #expect(exported.metric(for: .initialSnapshotApplying)?.durationMS == 61)
        #expect(exported.metric(for: .anchorRestoring)?.durationMS == 12)
        #expect(exported.metric(for: .restoreGate)?.durationMS == 180)
        #expect(exported.firstInteractiveScrollAllowedAtMS == 1_735_000_000_180)
        #expect(firstInteractiveMetric.timestampMS == 1_735_000_000_180)
        #expect(firstInteractiveMetric.durationMS == 180)
        #expect(exported.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(exported.budgetResult == .withinBudget)
        #expect(exported.releaseBlockingReasons.isEmpty)
        #expect(!exported.readMarkerChanged)
        #expect(!exported.requiresNetworkWork)
        #expect(!exported.requiresDBWork)
        #expect(export.mutationRecords.isEmpty)

        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(TimelineDiagnosticsExport.self, from: data)

        #expect(decoded == export)
    }

    @Test("Recorder exports exceeded restore gate fallback reason")
    func recorderExportsExceededRestoreGateFallbackReason() throws {
        let recorder = TimelineDiagnosticsRecorder()
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 501,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_501,
            networkWaitedBeforeInteractiveScrollMS: 0,
            fallbackPresentation: .inlineSkeleton,
            timestampMS: 1_735_000_000_000
        )

        recorder.recordRestoreGateDiagnostics(diagnostics)
        let exported = try #require(recorder.export().restoreGateDiagnostics.first)
        let restoreGateMetric = try #require(exported.metric(for: .restoreGate))

        #expect(exported.budgetResult == .exceededBudget)
        #expect(exported.exceededReasons == [.restoreGateDurationExceededHardLimit])
        #expect(exported.fallbackPresentation == .inlineSkeleton)
        #expect(restoreGateMetric.budgetResult == .exceededBudget)
        #expect(restoreGateMetric.exceededBudget)
        #expect(restoreGateMetric.exceededReason == .restoreGateDurationExceededHardLimit)
        #expect(exported.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(exported.releaseBlockingReasons.isEmpty)
        #expect(!exported.readMarkerChanged)
    }

    @Test("Recorder keeps network wait release-blocking after export")
    func recorderKeepsNetworkWaitReleaseBlockingAfterExport() throws {
        let recorder = TimelineDiagnosticsRecorder()
        let diagnostics = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            networkWaitedBeforeInteractiveScrollMS: 1,
            timestampMS: 1_735_000_000_000
        )

        recorder.recordRestoreGateDiagnostics(diagnostics)
        let exported = try #require(recorder.export().restoreGateDiagnostics.first)

        #expect(!exported.isValidForRelease)
        #expect(exported.releaseBlockingReasons == [.networkWaitedBeforeInteractiveScroll])
        #expect(exported.networkWaitedBeforeInteractiveScrollMS == 1)
        #expect(!exported.readMarkerChanged)
    }

    @Test("Recorder exports standalone restore gate metric without private raw content")
    func recorderExportsStandaloneRestoreGateMetricWithoutPrivateRawContent() throws {
        let recorder = TimelineDiagnosticsRecorder()
        let metric = TimelineRestoreGateMetricBuilder.metric(
            stage: .localInitialWindowQuery,
            durationMS: 42,
            budget: .localInitialWindowQuery,
            timestampMS: 1_735_000_000_000
        )

        recorder.recordRestoreGateMetric(metric)
        let export = recorder.export()

        #expect(export.restoreGateMetrics == [metric])
        #expect(export.restoreGateDiagnostics.isEmpty)
        #expect(export.mutationRecords.isEmpty)

        let data = try JSONEncoder().encode(export)
        let encoded = try #require(String(data: data, encoding: .utf8))

        for forbiddenFragment in ["n" + "sec", "sec" + "ret", "priv" + "ate"] {
            #expect(!encoded.localizedCaseInsensitiveContains(forbiddenFragment))
        }
    }

    @Test("Recorder exports multiple standalone restore gate metrics in order")
    func recorderExportsMultipleStandaloneRestoreGateMetricsInOrder() {
        let recorder = TimelineDiagnosticsRecorder()
        let first = TimelineRestoreGateMetricBuilder.metric(
            stage: .localInitialWindowQuery,
            durationMS: 42,
            budget: .localInitialWindowQuery,
            timestampMS: 1_735_000_000_000
        )
        let second = TimelineRestoreGateMetricBuilder.metric(
            stage: .restoreGate,
            durationMS: 180,
            budget: .restoreGate,
            timestampMS: 1_735_000_000_180
        )

        recorder.recordRestoreGateMetric(first)
        recorder.recordRestoreGateMetric(second)

        #expect(recorder.export().restoreGateMetrics == [first, second])
    }

    @Test("Export summary aggregates multiple within-budget restore attempts")
    func exportSummaryAggregatesMultipleWithinBudgetRestoreAttempts() throws {
        let recorder = TimelineDiagnosticsRecorder()
        let first = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            timestampMS: 1_735_000_000_000
        )
        let second = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 48,
            initialSnapshotApplyDurationMS: 70,
            anchorRestoreDurationMS: 15,
            restoreGateDurationMS: 220,
            firstInteractiveScrollAllowedAtMS: 1_735_000_001_220,
            timestampMS: 1_735_000_001_000
        )

        recorder.recordRestoreGateDiagnostics(first)
        recorder.recordRestoreGateDiagnostics(second)
        let export = recorder.export()
        let summary = export.summary.restoreGateMetrics

        #expect(export.restoreGateDiagnostics == [first, second])
        #expect(summary.totalAttempts == 2)
        #expect(summary.withinBudgetCount == 2)
        #expect(summary.overTargetCount == 0)
        #expect(summary.exceededBudgetCount == 0)
        #expect(summary.releaseBlockingCount == 0)
        #expect(summary.networkWaitedBeforeInteractiveScrollViolationCount == 0)
        #expect(summary.maxRestoreGateDurationMS == 220)
        #expect(summary.maxLocalInitialWindowQueryMS == 48)
        #expect(summary.maxInitialSnapshotApplyMS == 70)
        #expect(summary.maxAnchorRestoreMS == 15)
        #expect(summary.maxNetworkWaitedBeforeInteractiveScrollMS == 0)
        #expect(summary.latestFallbackReason == nil)
        #expect(!summary.readMarkerChanged)
        #expect(!summary.continuesSplash)
        #expect(!summary.requiresNetworkWork)
        #expect(!summary.requiresDBWork)

        let data = try JSONEncoder().encode(export.summary)
        let decoded = try JSONDecoder().decode(TimelineDiagnosticsExportSummary.self, from: data)

        #expect(decoded == export.summary)
    }

    @Test("Export summary counts mixed budget and network release blockers")
    func exportSummaryCountsMixedBudgetAndNetworkReleaseBlockers() {
        let recorder = TimelineDiagnosticsRecorder()
        let withinBudget = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            timestampMS: 1_735_000_000_000
        )
        let overTarget = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 180,
            initialSnapshotApplyDurationMS: 120,
            anchorRestoreDurationMS: 44,
            restoreGateDurationMS: 300,
            firstInteractiveScrollAllowedAtMS: 1_735_000_001_300,
            timestampMS: 1_735_000_001_000
        )
        let exceededBudget = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 301,
            initialSnapshotApplyDurationMS: 201,
            anchorRestoreDurationMS: 51,
            restoreGateDurationMS: 501,
            firstInteractiveScrollAllowedAtMS: 1_735_000_002_501,
            networkWaitedBeforeInteractiveScrollMS: 7,
            fallbackPresentation: .inlineSkeleton,
            timestampMS: 1_735_000_002_000
        )

        recorder.recordRestoreGateDiagnostics(withinBudget)
        recorder.recordRestoreGateDiagnostics(overTarget)
        recorder.recordRestoreGateDiagnostics(exceededBudget)
        let summary = recorder.export().summary.restoreGateMetrics

        #expect(summary.totalAttempts == 3)
        #expect(summary.withinBudgetCount == 1)
        #expect(summary.overTargetCount == 1)
        #expect(summary.exceededBudgetCount == 1)
        #expect(summary.releaseBlockingCount == 1)
        #expect(summary.networkWaitedBeforeInteractiveScrollViolationCount == 1)
        #expect(summary.maxRestoreGateDurationMS == 501)
        #expect(summary.maxLocalInitialWindowQueryMS == 301)
        #expect(summary.maxInitialSnapshotApplyMS == 201)
        #expect(summary.maxAnchorRestoreMS == 51)
        #expect(summary.maxNetworkWaitedBeforeInteractiveScrollMS == 7)
        #expect(summary.latestFallbackReason == .restoreGateDurationExceededHardLimit)
        #expect(!summary.readMarkerChanged)
        #expect(!summary.continuesSplash)
        #expect(!summary.requiresNetworkWork)
        #expect(!summary.requiresDBWork)
    }

    @Test("Export summary keeps read marker unchanged unless a record says otherwise")
    func exportSummaryKeepsReadMarkerUnchangedUnlessARecordSaysOtherwise() {
        let recorder = TimelineDiagnosticsRecorder()
        let unchanged = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
            timestampMS: 1_735_000_000_000
        )

        recorder.recordRestoreGateDiagnostics(unchanged)
        #expect(!recorder.export().summary.restoreGateMetrics.readMarkerChanged)

        let changed = TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: 42,
            initialSnapshotApplyDurationMS: 61,
            anchorRestoreDurationMS: 12,
            restoreGateDurationMS: 180,
            firstInteractiveScrollAllowedAtMS: 1_735_000_001_180,
            readMarkerChanged: true,
            timestampMS: 1_735_000_001_000
        )

        recorder.recordRestoreGateDiagnostics(changed)
        let summary = recorder.export().summary.restoreGateMetrics

        #expect(summary.readMarkerChanged)
        #expect(summary.releaseBlockingCount == 1)
    }

    @Test("Fixture-backed export JSON has stable artifact shape")
    func fixtureBackedExportJSONHasStableArtifactShape() throws {
        let export = TimelineDiagnosticsExportJSONFixture.mixedRestoreGateExport()
        let data = try TimelineDiagnosticsExportJSONFixture.encode(export)
        let encoded = try #require(String(data: data, encoding: .utf8))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(json.keys) == [
            "mutationRecords",
            "restoreGateRecords",
            "restoreGateMetrics",
            "restoreGateDiagnostics",
            "summary"
        ])
        #expect(json["restoreGateRecords"] as? [String] == [
            "localInitialWindowQuery",
            "restoreGate"
        ])

        let diagnostics = try #require(json["restoreGateDiagnostics"] as? [[String: Any]])
        #expect(diagnostics.count == 3)
        #expect(diagnostics.allSatisfy { TimelineDiagnosticsExportJSONFixture.bool($0["readMarkerChanged"]) == false })

        let summary = try #require(json["summary"] as? [String: Any])
        let restoreGateSummary = try #require(summary["restoreGateMetrics"] as? [String: Any])
        #expect(Set(restoreGateSummary.keys) == [
            "totalAttempts",
            "withinBudgetCount",
            "overTargetCount",
            "exceededBudgetCount",
            "releaseBlockingCount",
            "networkWaitedBeforeInteractiveScrollViolationCount",
            "maxRestoreGateDurationMS",
            "maxLocalInitialWindowQueryMS",
            "maxInitialSnapshotApplyMS",
            "maxAnchorRestoreMS",
            "maxNetworkWaitedBeforeInteractiveScrollMS",
            "latestFallbackReason",
            "readMarkerChanged",
            "continuesSplash",
            "requiresNetworkWork",
            "requiresDBWork"
        ])
        #expect(TimelineDiagnosticsExportJSONFixture.int(restoreGateSummary["totalAttempts"]) == 3)
        #expect(TimelineDiagnosticsExportJSONFixture.int(restoreGateSummary["withinBudgetCount"]) == 1)
        #expect(TimelineDiagnosticsExportJSONFixture.int(restoreGateSummary["overTargetCount"]) == 1)
        #expect(TimelineDiagnosticsExportJSONFixture.int(restoreGateSummary["exceededBudgetCount"]) == 1)
        #expect(TimelineDiagnosticsExportJSONFixture.int(restoreGateSummary["releaseBlockingCount"]) == 1)
        #expect(
            TimelineDiagnosticsExportJSONFixture.int(
                restoreGateSummary["networkWaitedBeforeInteractiveScrollViolationCount"]
            ) == 1
        )
        #expect(TimelineDiagnosticsExportJSONFixture.double(restoreGateSummary["maxRestoreGateDurationMS"]) == 501)
        #expect(TimelineDiagnosticsExportJSONFixture.double(restoreGateSummary["maxLocalInitialWindowQueryMS"]) == 301)
        #expect(TimelineDiagnosticsExportJSONFixture.double(restoreGateSummary["maxInitialSnapshotApplyMS"]) == 201)
        #expect(TimelineDiagnosticsExportJSONFixture.double(restoreGateSummary["maxAnchorRestoreMS"]) == 51)
        #expect(
            TimelineDiagnosticsExportJSONFixture.double(
                restoreGateSummary["maxNetworkWaitedBeforeInteractiveScrollMS"]
            ) == 7
        )
        #expect(restoreGateSummary["latestFallbackReason"] as? String == "restoreGateDurationExceededHardLimit")
        #expect(TimelineDiagnosticsExportJSONFixture.bool(restoreGateSummary["readMarkerChanged"]) == false)

        let decoded = try JSONDecoder().decode(TimelineDiagnosticsExport.self, from: data)
        #expect(decoded == export)
        #expect(decoded.summary.restoreGateMetrics.releaseBlockingCount == 1)
        #expect(decoded.summary.restoreGateMetrics.networkWaitedBeforeInteractiveScrollViolationCount == 1)

        for forbiddenFragment in [
            ["n", "sec"].joined(),
            ["sec", "ret"].joined(),
            ["raw", " event JSON"].joined(),
            ["priv", "ate key material"].joined()
        ] {
            #expect(!encoded.localizedCaseInsensitiveContains(forbiddenFragment))
        }
    }
}

@Suite("Timeline diagnostics export consumer")
struct TimelineDiagnosticsExportConsumerTests {
    @Test("Consumer decodes fixture JSON and reads restore gate metrics summary")
    func consumerDecodesFixtureJSONAndReadsRestoreGateMetricsSummary() throws {
        let consumer = try TimelineDiagnosticsExportConsumer(data: TimelineDiagnosticsExportConsumerFixture.allWithinBudget)
        let metrics = consumer.restoreGateMetrics

        #expect(consumer.export.restoreGateDiagnostics.count == 1)
        #expect(metrics.totalAttempts == 1)
        #expect(metrics.withinBudgetCount == 1)
        #expect(metrics.overTargetCount == 0)
        #expect(metrics.exceededBudgetCount == 0)
        #expect(metrics.releaseBlockingCount == 0)
        #expect(metrics.networkWaitedBeforeInteractiveScrollViolationCount == 0)
        #expect(metrics.maxRestoreGateDurationMS == 180)
        #expect(metrics.latestFallbackReason == nil)
    }

    @Test("Consumer detects no release blockers for all-within-budget fixture")
    func consumerDetectsNoReleaseBlockersForAllWithinBudgetFixture() throws {
        let consumer = try TimelineDiagnosticsExportConsumer(data: TimelineDiagnosticsExportConsumerFixture.allWithinBudget)
        let summary = consumer.artifactSummary()

        #expect(!consumer.hasReleaseBlockers)
        #expect(summary.releaseBlockingCount == 0)
        #expect(summary.networkWaitedBeforeInteractiveScrollViolationCount == 0)
    }

    @Test("Consumer detects release blockers for network-wait fixture")
    func consumerDetectsReleaseBlockersForNetworkWaitFixture() throws {
        let consumer = try TimelineDiagnosticsExportConsumer(data: TimelineDiagnosticsExportConsumerFixture.networkWaitReleaseBlocker)
        let summary = consumer.artifactSummary()

        #expect(consumer.hasReleaseBlockers)
        #expect(summary.releaseBlockingCount == 1)
        #expect(summary.networkWaitedBeforeInteractiveScrollViolationCount == 1)
        #expect(summary.exceededBudgetCount == 1)
        #expect(summary.latestFallbackReason == "restoreGateDurationExceededHardLimit")
    }

    @Test("Consumer builds deterministic artifact summary without runtime Timeline wiring")
    func consumerBuildsDeterministicArtifactSummaryWithoutRuntimeTimelineWiring() throws {
        let consumer = try TimelineDiagnosticsExportConsumer(data: TimelineDiagnosticsExportConsumerFixture.networkWaitReleaseBlocker)
        let summary = consumer.artifactSummary()

        #expect(summary == TimelineDiagnosticsArtifactSummary(
            totalAttempts: 1,
            withinBudgetCount: 0,
            overTargetCount: 0,
            exceededBudgetCount: 1,
            releaseBlockingCount: 1,
            networkWaitedBeforeInteractiveScrollViolationCount: 1,
            maxRestoreGateDurationMS: 501,
            latestFallbackReason: "restoreGateDurationExceededHardLimit",
            requiresNetworkWork: false,
            requiresDBWork: false
        ))
        #expect(summary.debugSummary == "attempts=1 within=0 overTarget=0 exceeded=1 releaseBlockers=1 networkWaitViolations=1 maxRestoreGateMS=501 latestFallback=restoreGateDurationExceededHardLimit")
    }

    @Test("Consumer fixture remains offline and sensitive-material-free")
    func consumerFixtureRemainsOfflineAndSensitiveMaterialFree() throws {
        let fixture = TimelineDiagnosticsExportConsumerFixture.networkWaitReleaseBlocker
        let consumer = try TimelineDiagnosticsExportConsumer(data: fixture)
        let encoded = try #require(String(data: fixture, encoding: .utf8))

        #expect(!consumer.restoreGateMetrics.requiresNetworkWork)
        #expect(!consumer.restoreGateMetrics.requiresDBWork)
        #expect(!consumer.restoreGateMetrics.continuesSplash)
        #expect(!consumer.restoreGateMetrics.readMarkerChanged)
        #expect(consumer.export.mutationRecords.isEmpty)

        for forbiddenFragment in TimelineDiagnosticsExportConsumerFixture.forbiddenRuntimeOrSensitiveFragments {
            #expect(!encoded.localizedCaseInsensitiveContains(forbiddenFragment))
        }
    }
}

private struct TimelineDiagnosticsExportConsumer {
    let export: TimelineDiagnosticsExport

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        self.export = try decoder.decode(TimelineDiagnosticsExport.self, from: data)
    }

    var restoreGateMetrics: TimelineRestoreGateMetricsSummary {
        export.summary.restoreGateMetrics
    }

    var hasReleaseBlockers: Bool {
        restoreGateMetrics.releaseBlockingCount > 0
    }

    func artifactSummary() -> TimelineDiagnosticsArtifactSummary {
        TimelineDiagnosticsArtifactSummary(metrics: restoreGateMetrics)
    }
}

private struct TimelineDiagnosticsArtifactSummary: Equatable {
    var totalAttempts: Int
    var withinBudgetCount: Int
    var overTargetCount: Int
    var exceededBudgetCount: Int
    var releaseBlockingCount: Int
    var networkWaitedBeforeInteractiveScrollViolationCount: Int
    var maxRestoreGateDurationMS: Double?
    var latestFallbackReason: String?
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool

    init(
        totalAttempts: Int,
        withinBudgetCount: Int,
        overTargetCount: Int,
        exceededBudgetCount: Int,
        releaseBlockingCount: Int,
        networkWaitedBeforeInteractiveScrollViolationCount: Int,
        maxRestoreGateDurationMS: Double?,
        latestFallbackReason: String?,
        requiresNetworkWork: Bool,
        requiresDBWork: Bool
    ) {
        self.totalAttempts = totalAttempts
        self.withinBudgetCount = withinBudgetCount
        self.overTargetCount = overTargetCount
        self.exceededBudgetCount = exceededBudgetCount
        self.releaseBlockingCount = releaseBlockingCount
        self.networkWaitedBeforeInteractiveScrollViolationCount = networkWaitedBeforeInteractiveScrollViolationCount
        self.maxRestoreGateDurationMS = maxRestoreGateDurationMS
        self.latestFallbackReason = latestFallbackReason
        self.requiresNetworkWork = requiresNetworkWork
        self.requiresDBWork = requiresDBWork
    }

    init(metrics: TimelineRestoreGateMetricsSummary) {
        self.init(
            totalAttempts: metrics.totalAttempts,
            withinBudgetCount: metrics.withinBudgetCount,
            overTargetCount: metrics.overTargetCount,
            exceededBudgetCount: metrics.exceededBudgetCount,
            releaseBlockingCount: metrics.releaseBlockingCount,
            networkWaitedBeforeInteractiveScrollViolationCount: metrics.networkWaitedBeforeInteractiveScrollViolationCount,
            maxRestoreGateDurationMS: metrics.maxRestoreGateDurationMS,
            latestFallbackReason: metrics.latestFallbackReason?.rawValue,
            requiresNetworkWork: metrics.requiresNetworkWork,
            requiresDBWork: metrics.requiresDBWork
        )
    }

    var debugSummary: String {
        [
            "attempts=\(totalAttempts)",
            "within=\(withinBudgetCount)",
            "overTarget=\(overTargetCount)",
            "exceeded=\(exceededBudgetCount)",
            "releaseBlockers=\(releaseBlockingCount)",
            "networkWaitViolations=\(networkWaitedBeforeInteractiveScrollViolationCount)",
            "maxRestoreGateMS=\(Self.format(maxRestoreGateDurationMS))",
            "latestFallback=\(latestFallbackReason ?? "none")"
        ].joined(separator: " ")
    }

    private static func format(_ value: Double?) -> String {
        guard let value else {
            return "none"
        }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}

private enum TimelineDiagnosticsExportConsumerFixture {
    static let allWithinBudget = Data("""
    {
      "mutationRecords": [],
      "restoreGateRecords": [
        "restoreGate"
      ],
      "restoreGateMetrics": [],
      "restoreGateDiagnostics": [
        {
          "metrics": [
            {
              "stage": "restoreGate",
              "durationMS": 180,
              "timestampMS": 1735000000000,
              "exceededBudget": false,
              "budget": {
                "targetDurationMS": 250,
                "hardLimitDurationMS": 500
              },
              "budgetResult": "withinBudget"
            }
          ],
          "firstInteractiveScrollAllowedAtMS": 1735000000180,
          "networkWaitedBeforeInteractiveScrollMS": 0,
          "readMarkerChanged": false,
          "continuesSplash": false,
          "requiresNetworkWork": false,
          "requiresDBWork": false
        }
      ]
    }
    """.utf8)

    static let networkWaitReleaseBlocker = Data("""
    {
      "mutationRecords": [],
      "restoreGateRecords": [
        "restoreGate"
      ],
      "restoreGateMetrics": [],
      "restoreGateDiagnostics": [
        {
          "metrics": [
            {
              "stage": "restoreGate",
              "durationMS": 501,
              "timestampMS": 1735000002000,
              "exceededBudget": true,
              "budget": {
                "targetDurationMS": 250,
                "hardLimitDurationMS": 500
              },
              "budgetResult": "exceededBudget",
              "exceededReason": "restoreGateDurationExceededHardLimit"
            }
          ],
          "firstInteractiveScrollAllowedAtMS": 1735000002501,
          "networkWaitedBeforeInteractiveScrollMS": 7,
          "readMarkerChanged": false,
          "fallbackPresentation": "inlineSkeleton",
          "continuesSplash": false,
          "requiresNetworkWork": false,
          "requiresDBWork": false
        }
      ]
    }
    """.utf8)

    static let forbiddenRuntimeOrSensitiveFragments: [String] = [
        ["n", "sec"].joined(),
        ["sec", "ret"].joined(),
        ["priv", "ate key material"].joined(),
        ["raw", " event JSON"].joined(),
        ["URL", "Session"].joined(),
        ["Web", "Socket"].joined(),
        ["Re", "lay"].joined(),
        ["GR", "DB"].joined(),
        ["Data", "base"].joined(),
        ["Timeline", "CollectionViewController"].joined(),
        ["Home", "Timeline"].joined(),
        ["Root", "Shell"].joined(),
        ["Resolve", "Coordinator"].joined(),
        ["data", "Source.apply"].joined(),
        ["delete", "Items"].joined(),
        ["insert", "Items"].joined()
    ]
}

private enum TimelineDiagnosticsExportJSONFixture {
    static func mixedRestoreGateExport() -> TimelineDiagnosticsExport {
        let recorder = TimelineDiagnosticsRecorder()
        recorder.recordRestoreGate(.localInitialWindowQuery)
        recorder.recordRestoreGate(.restoreGate)
        recorder.recordRestoreGateMetric(
            TimelineRestoreGateMetricBuilder.metric(
                stage: .localInitialWindowQuery,
                durationMS: 42,
                budget: .localInitialWindowQuery,
                timestampMS: 1_735_000_000_000
            )
        )
        recorder.recordRestoreGateDiagnostics(
            TimelineRestoreGateMetricBuilder.diagnostics(
                localInitialWindowQueryDurationMS: 42,
                initialSnapshotApplyDurationMS: 61,
                anchorRestoreDurationMS: 12,
                restoreGateDurationMS: 180,
                firstInteractiveScrollAllowedAtMS: 1_735_000_000_180,
                timestampMS: 1_735_000_000_000
            )
        )
        recorder.recordRestoreGateDiagnostics(
            TimelineRestoreGateMetricBuilder.diagnostics(
                localInitialWindowQueryDurationMS: 180,
                initialSnapshotApplyDurationMS: 120,
                anchorRestoreDurationMS: 44,
                restoreGateDurationMS: 300,
                firstInteractiveScrollAllowedAtMS: 1_735_000_001_300,
                timestampMS: 1_735_000_001_000
            )
        )
        recorder.recordRestoreGateDiagnostics(
            TimelineRestoreGateMetricBuilder.diagnostics(
                localInitialWindowQueryDurationMS: 301,
                initialSnapshotApplyDurationMS: 201,
                anchorRestoreDurationMS: 51,
                restoreGateDurationMS: 501,
                firstInteractiveScrollAllowedAtMS: 1_735_000_002_501,
                networkWaitedBeforeInteractiveScrollMS: 7,
                fallbackPresentation: .inlineSkeleton,
                timestampMS: 1_735_000_002_000
            )
        )
        return recorder.export()
    }

    static func encode(_ export: TimelineDiagnosticsExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(export)
    }

    static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        return (value as? NSNumber)?.boolValue
    }
}
