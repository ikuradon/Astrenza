import Testing
import UIKit
@testable import Astrenza

@Suite("Timeline row gesture arbitration")
struct TimelinePostRowGestureTests {
    @MainActor
    @Test("Rows share one directional recognizer without disabling feed scrolling")
    func rowSwipeRecognizerDoesNotOwnScrollAvailability() throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let firstCell = UICollectionViewCell(
            frame: CGRect(x: 0, y: 120, width: 390, height: 240)
        )
        let secondCell = UICollectionViewCell(
            frame: CGRect(x: 0, y: 360, width: 390, height: 240)
        )
        scrollView.addSubview(firstCell)
        scrollView.addSubview(secondCell)

        let firstMarker = TimelineRowPanGestureHost.MarkerView(
            frame: firstCell.contentView.bounds
        )
        let secondMarker = TimelineRowPanGestureHost.MarkerView(
            frame: secondCell.contentView.bounds
        )
        firstCell.contentView.addSubview(firstMarker)
        secondCell.contentView.addSubview(secondMarker)

        let host = TimelineRowPanGestureHost(
            isEnabled: true,
            onChanged: { _ in },
            onEnded: { _ in }
        )
        let firstCoordinator = TimelineRowPanGestureHost.Coordinator(parent: host)
        let secondCoordinator = TimelineRowPanGestureHost.Coordinator(parent: host)

        firstCoordinator.attachIfNeeded(from: firstMarker)
        secondCoordinator.attachIfNeeded(from: secondMarker)

        let recognizer = try #require(firstCoordinator.recognizer)
        #expect(recognizer.view === scrollView)
        #expect(secondCoordinator.recognizer === recognizer)
        #expect(scrollView.isScrollEnabled)

        firstCoordinator.detach()
        secondCoordinator.detach()

        #expect(recognizer.view === scrollView)
        #expect(scrollView.isScrollEnabled)
    }
}
