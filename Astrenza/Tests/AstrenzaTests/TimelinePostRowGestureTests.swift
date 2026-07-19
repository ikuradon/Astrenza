import Testing
import UIKit
@testable import Astrenza

@Suite("Timeline row gesture arbitration")
struct TimelinePostRowGestureTests {
    @MainActor
    @Test("Action menus use system menu elements in stable semantic groups")
    func actionMenusUseSystemMenuElements() {
        let repostMenu = TimelinePostActionMenuBuilder.make(
            kind: .repost,
            onSelect: { _ in }
        )
        #expect(repostMenu.actionTitles == ["Repost", "Quoted Repost"])

        let favoriteMenu = TimelinePostActionMenuBuilder.make(
            kind: .favorite,
            onSelect: { _ in }
        )
        #expect(
            favoriteMenu.actionTitles == [
                "Favorite",
                "Custom Reaction",
                "Bookmark",
            ]
        )

        let moreMenu = TimelinePostActionMenuBuilder.make(
            kind: .more,
            onSelect: { _ in }
        )
        #expect(moreMenu.children.compactMap { $0 as? UIMenu }.count == 4)
        #expect(
            moreMenu.actionTitles == [
                "Report",
                "Mute",
                "Translate",
                "Bookmark",
                "Copy Link",
                "Share Link",
                "View Details",
            ]
        )
    }

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

private extension UIMenu {
    var actionTitles: [String] {
        children.flatMap { element -> [String] in
            if let action = element as? UIAction {
                return [action.title]
            }
            if let menu = element as? UIMenu {
                return menu.actionTitles
            }
            return []
        }
    }
}
