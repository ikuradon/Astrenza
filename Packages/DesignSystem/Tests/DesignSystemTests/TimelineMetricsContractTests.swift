import Testing
@testable import DesignSystem

@Suite("Timeline metrics contracts")
struct TimelineMetricsContractTests {
    @Test("Link preview metrics preserve v1 aspect and height limits")
    func linkPreviewMetricsPreserveAspectAndHeightLimits() {
        let metrics = DSMediaMetrics.timeline.linkPreview

        #expect(metrics.imageAspectRatio == 1.91)
        #expect(metrics.imageAspectRatio == DSMediaMetrics.timeline.linkPreviewImageAspectRatio)
        #expect(metrics.imageMaxHeight == 180)
        #expect(metrics.textAreaMinHeight == 92)
        #expect(metrics.textAreaMaxHeight == 118)
        #expect(metrics.totalMaxHeight == 306)
        #expect(metrics.compactImageHeight <= metrics.imageMaxHeight)
        #expect(metrics.compactImageHeight == metrics.textAreaMinHeight)
        #expect(metrics.compactImageWidth == metrics.compactImageHeight * metrics.imageAspectRatio)
    }

    @Test("Compact repost context chip is visual-only and below interactive hit target")
    func compactRepostContextChipIsVisualOnlyAndBelowInteractiveHitTarget() {
        let metrics = TimelineContextChipMetrics.repostCompact

        #expect(metrics.interaction == .noninteractive)
        #expect(metrics.visualHeight == 28)
        #expect(metrics.visualHeight < DSControlSize.minimumHitTarget)
        #expect(metrics.avatarSize == 20)
        #expect(metrics.iconSize == DSIcon.repost.visualSize(for: .compactBadge))
        #expect(metrics.maxWidth == nil)
        #expect(metrics.hitTargetWidth == nil)
        #expect(metrics.hitTargetHeight == nil)
    }

    @Test("Interactive context chip metrics keep hit target separate from compact visual height")
    func interactiveContextChipMetricsKeepHitTargetSeparateFromVisualHeight() {
        let metrics = TimelineContextChipMetrics.repostInteractive

        #expect(metrics.interaction == .interactive)
        #expect(metrics.visualHeight == 28)
        #expect(metrics.visualHeight < DSControlSize.minimumHitTarget)
        #expect(metrics.hitTargetWidth == DSControlSize.minimumHitTarget)
        #expect(metrics.hitTargetHeight == DSControlSize.minimumHitTarget)
    }
}
