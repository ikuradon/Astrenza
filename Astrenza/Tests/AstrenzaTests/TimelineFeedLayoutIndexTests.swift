import CoreGraphics
import Testing
@testable import Astrenza

@Suite("Timeline feed layout index")
struct TimelineFeedLayoutIndexTests {
    @Test("Frames include top padding and exact item heights")
    func framesIncludeTopPadding() {
        let index = TimelineFeedLayoutIndex(
            items: items([80, 120, 60]),
            topPadding: 72
        )

        #expect(index.frame(at: 0, width: 390) == CGRect(
            x: 0,
            y: 72,
            width: 390,
            height: 80
        ))
        #expect(index.frame(at: 2, width: 390)?.minY == 272)
        #expect(index.contentHeight == 332)
    }

    @Test("One measured height shifts only downstream offsets")
    func measuredHeightShiftsDownstreamOffsets() {
        var index = TimelineFeedLayoutIndex(
            items: items([80, 120, 60]),
            topPadding: 72
        )

        let delta = index.updateHeight(150, at: 1)

        #expect(delta == 30)
        #expect(index.frame(at: 1, width: 390)?.minY == 152)
        #expect(index.frame(at: 2, width: 390)?.minY == 302)
        #expect(index.contentHeight == 362)
    }

    @Test("Fractional measured heights are not rounded between rows")
    func fractionalHeightsRemainExact() {
        var index = TimelineFeedLayoutIndex(
            items: items([100, 100]),
            topPadding: 72
        )

        #expect(index.updateHeight(100.75, at: 0) == 0.75)
        #expect(index.frame(at: 1, width: 390)?.minY == 172.75)
    }

    @Test("Visible lookup excludes rows outside the query rect")
    func visibleLookupUsesRowIntersections() {
        let index = TimelineFeedLayoutIndex(
            items: items([80, 120, 60, 100]),
            topPadding: 72
        )

        #expect(
            index.itemIndexes(
                intersecting: CGRect(x: 0, y: 160, width: 390, height: 150)
            ) == 1..<3
        )
    }

    @Test("Ten thousand row update preserves logarithmic geometry results")
    func largeIndexUpdatesDownstreamGeometry() {
        var index = TimelineFeedLayoutIndex(
            items: items(Array(repeating: 80, count: 10_000)),
            topPadding: 72
        )

        #expect(index.updateHeight(180, at: 0) == 100)
        #expect(index.frame(at: 9_876, width: 390)?.minY ==
            CGFloat(72 + 9_876 * 80 + 100))
        #expect(index.itemIndexes(
            intersecting: CGRect(
                x: 0,
                y: CGFloat(72 + 9_876 * 80 + 100),
                width: 390,
                height: 800
            )
        ).lowerBound == 9_876)
    }

    private func items(_ heights: [CGFloat]) -> [TimelineFeedLayoutItem] {
        heights.enumerated().map {
            TimelineFeedLayoutItem(
                id: "post-\($0.offset)",
                estimatedHeight: $0.element
            )
        }
    }
}
