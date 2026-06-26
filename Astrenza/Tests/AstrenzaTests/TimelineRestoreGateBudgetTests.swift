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
}
