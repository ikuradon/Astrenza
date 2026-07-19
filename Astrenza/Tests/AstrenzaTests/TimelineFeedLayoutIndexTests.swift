import CoreGraphics
import Testing
import UIKit
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

    @MainActor
    @Test("Measured height is applied directly through the layout index")
    func measuredHeightUpdatesLayoutWithoutSelfSizingInvalidation() throws {
        let layout = TimelineFeedCollectionLayout(anchorLineY: 72)
        layout.configure(
            items: [
                TimelineFeedLayoutItem(
                    id: "post-0",
                    estimatedHeight: 100
                ),
            ],
            topPadding: 72
        )
        #expect(layout.updateProjectedHeights(["post-0": 150]))
        #expect(layout.layoutAttributesForItem(
            at: IndexPath(item: 0, section: 0)
        )?.size.height == 150)
        #expect(!layout.updateProjectedHeights(["post-0": 150]))
    }

    @MainActor
    @Test("Projected height batch updates rows in one layout transaction")
    func projectedHeightBatchUpdatesRowsTogether() {
        let layout = TimelineFeedCollectionLayout(anchorLineY: 72)
        layout.configure(
            items: items([100, 100, 100]),
            topPadding: 72
        )

        #expect(layout.updateProjectedHeights([
            "post-0": 140,
            "post-1": 80,
        ]))
        #expect(layout.layoutAttributesForItem(
            at: IndexPath(item: 0, section: 0)
        )?.size.height == 140)
        #expect(layout.layoutAttributesForItem(
            at: IndexPath(item: 1, section: 0)
        )?.frame.minY == 212)
        #expect(layout.layoutAttributesForItem(
            at: IndexPath(item: 2, section: 0)
        )?.frame.minY == 292)
    }

    @MainActor
    @Test("Row height projection stays immutable during user scrolling")
    func rowHeightProjectionDefersMeasurementsDuringScroll() async throws {
        let coordinator = TimelineFeedRowLayoutProjectionCoordinator()
        var committedBatches: [[TimelineFeedEntry.ID: CGFloat]] = []
        coordinator.configure(
            onLayoutCacheChanged: { _ in },
            onProjectedHeightsChanged: {
                committedBatches.append($0)
            }
        )
        coordinator.reset(layoutCache: TimelineLayoutCache())
        coordinator.setScrollActive(true)

        coordinator.stageMeasuredHeight(180, for: "post-0")
        coordinator.stageMeasuredHeight(220, for: "post-1")
        try await Task.sleep(for: .milliseconds(50))

        #expect(committedBatches.isEmpty)
        #expect(coordinator.layoutCache.measuredHeights.isEmpty)

        coordinator.setScrollActive(false)
        try await Task.sleep(for: .milliseconds(50))

        #expect(committedBatches == [[
            "post-0": 180,
            "post-1": 220,
        ]])
        #expect(coordinator.layoutCache.measuredHeights == [
            "post-0": 180,
            "post-1": 220,
        ])
    }

    @MainActor
    @Test("Restore protection keeps staged row geometry uncommitted")
    func rowHeightProjectionDefersMeasurementsDuringRestore() async throws {
        let coordinator = TimelineFeedRowLayoutProjectionCoordinator()
        var committedBatches: [[TimelineFeedEntry.ID: CGFloat]] = []
        coordinator.configure(
            onLayoutCacheChanged: { _ in },
            onProjectedHeightsChanged: {
                committedBatches.append($0)
            }
        )
        coordinator.reset(layoutCache: TimelineLayoutCache())
        coordinator.setProjectionMutationSuspended(true)
        coordinator.stageMeasuredHeight(180, for: "post-0")
        try await Task.sleep(for: .milliseconds(50))

        #expect(committedBatches.isEmpty)
        coordinator.setProjectionMutationSuspended(false)
        try await Task.sleep(for: .milliseconds(50))

        #expect(committedBatches == [["post-0": 180]])
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
