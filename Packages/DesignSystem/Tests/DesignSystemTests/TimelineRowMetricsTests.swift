import Testing
@testable import DesignSystem

@Suite("Timeline row metrics")
struct TimelineRowMetricsTests {
    @Test("Comfortable density matches v1 baseline metrics")
    func comfortableDensityMatchesBaselineMetrics() {
        let metrics = TimelineRowMetrics(density: .comfortable)

        #expect(metrics.horizontalPadding == 16)
        #expect(metrics.verticalPaddingTop == 12)
        #expect(metrics.verticalPaddingBottom == 10)
        #expect(metrics.avatarSize == 44)
        #expect(metrics.avatarToContentGap == 12)
        #expect(metrics.cardCornerRadius == 14)
        #expect(metrics.actionMetrics.visualIconSize == 22)
        #expect(metrics.actionMetrics.targetHeight >= 44)
    }
}
