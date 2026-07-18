import UIKit

final class TimelineFeedHostingCell: UITableViewCell {
    private var entryID: TimelineFeedEntry.ID?
    private var lastMeasuredHeight: CGFloat = 0
    private var onHeightChanged:
        ((TimelineFeedEntry.ID, CGFloat) -> Void)?

    func observeHeight(
        for entryID: TimelineFeedEntry.ID,
        onHeightChanged:
            @escaping (TimelineFeedEntry.ID, CGFloat) -> Void
    ) {
        if self.entryID != entryID {
            lastMeasuredHeight = 0
        }
        self.entryID = entryID
        self.onHeightChanged = onHeightChanged
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        guard let entryID,
              height > 0,
              abs(height - lastMeasuredHeight) > 0.5
        else { return }
        lastMeasuredHeight = height
        onHeightChanged?(entryID, height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        entryID = nil
        lastMeasuredHeight = 0
        onHeightChanged = nil
    }
}
