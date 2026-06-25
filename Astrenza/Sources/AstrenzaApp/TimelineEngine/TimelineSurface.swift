import DesignSystem
import SwiftUI

struct TimelineSurface: UIViewControllerRepresentable {
    var accountID: AccountID
    var feedID: FeedID
    var timelineKey: TimelineKey
    var itemIDs: [TimelineEntryID]
    var theme: AppTheme

    init(
        accountID: AccountID = .debug,
        feedID: FeedID = .debugHome,
        timelineKey: TimelineKey = .home,
        itemIDs: [TimelineEntryID] = TimelineEntryID.debugItems,
        theme: AppTheme = .system
    ) {
        self.accountID = accountID
        self.feedID = feedID
        self.timelineKey = timelineKey
        self.itemIDs = itemIDs
        self.theme = theme
    }

    func makeUIViewController(context: Context) -> TimelineCollectionViewController {
        TimelineCollectionViewController(
            accountID: accountID,
            feedID: feedID,
            timelineKey: timelineKey,
            initialItemIDs: itemIDs,
            theme: theme
        )
    }

    func updateUIViewController(
        _ uiViewController: TimelineCollectionViewController,
        context: Context
    ) {
        uiViewController.apply(
            itemIDs: itemIDs,
            reason: .debugReload,
            animatingDifferences: false
        )
    }
}
