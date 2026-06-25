import Testing
@testable import DesignSystem

@Suite("Timeline action metrics")
struct TimelineActionMetricsTests {
    @Test("Default action metrics keep visual icon size separate from 44pt hit target")
    func defaultActionMetricsKeepVisualAndHitTargetSeparate() {
        let metrics = TimelineActionMetrics.default

        #expect(metrics.visualIconSize == 22)
        #expect(metrics.targetWidth >= 44)
        #expect(metrics.targetHeight >= 44)
        #expect(metrics.visualIconSize < metrics.targetHeight)
    }

    @Test("Action target width uses at least 44pt even when the slot is narrower")
    func actionTargetWidthKeepsMinimumTapTarget() {
        let metrics = TimelineActionMetrics.default

        #expect(metrics.targetWidth(forContentWidth: 120) == 44)
        #expect(metrics.targetWidth(forContentWidth: 300) == 60)
    }

    @Test("Custom action metrics clamp interactive targets to at least 44pt")
    func customActionMetricsClampInteractiveTargetsToMinimumHitTarget() {
        let metrics = TimelineActionMetrics(
            visualIconSize: 18,
            targetWidth: 20,
            targetHeight: 24
        )

        #expect(metrics.targetWidth == DSControlSize.minimumHitTarget)
        #expect(metrics.targetHeight == DSControlSize.minimumHitTarget)
        #expect(metrics.visualIconSize < metrics.targetHeight)
    }
}
