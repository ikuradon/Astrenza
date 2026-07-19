import UIKit

struct TimelineFeedCellSizingIdentity: Hashable {
    let entryID: TimelineFeedEntry.ID
    let geometryFingerprint: Int
    let swipeSettings: TimelineSwipeSettings
    let isActionMenuPresented: Bool
    let gapDirection: TimelineGapFillDirection
    let isFetchingGap: Bool
}

final class TimelineFeedHostingCollectionCell: UICollectionViewCell {
    private struct Measurement {
        let width: CGFloat
        let contentSizeCategory: UIContentSizeCategory
        let height: CGFloat
    }

    private var sizingIdentity: TimelineFeedCellSizingIdentity?
    private var measurement: Measurement?

    func configure(
        contentConfiguration: UIContentConfiguration,
        sizingIdentity: TimelineFeedCellSizingIdentity
    ) {
        if self.sizingIdentity != sizingIdentity {
            measurement = nil
        }
        self.sizingIdentity = sizingIdentity
        self.contentConfiguration = contentConfiguration
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        sizingIdentity = nil
        measurement = nil
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributes
    }

    func measuredHeight(fittingWidth width: CGFloat) -> CGFloat {
        let contentSizeCategory = traitCollection.preferredContentSizeCategory
        if let measurement,
           abs(measurement.width - width) <= 0.5,
           measurement.contentSizeCategory == contentSizeCategory {
            return measurement.height
        }

        bounds.size = CGSize(width: width, height: 180)
        contentView.bounds.size = bounds.size
        setNeedsLayout()
        layoutIfNeeded()
        let proposedAttributes = UICollectionViewLayoutAttributes(
            forCellWith: IndexPath(item: 0, section: 0)
        )
        proposedAttributes.size = CGSize(width: width, height: 180)
        _ = super.preferredLayoutAttributesFitting(
            proposedAttributes
        )
        let fittedSize = contentView.systemLayoutSizeFitting(
            CGSize(
                width: width,
                height: UIView.layoutFittingCompressedSize.height
            ),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let displayScale = max(1, traitCollection.displayScale)
        let height = max(
            1,
            ceil(fittedSize.height * displayScale) / displayScale
        )
        measurement = Measurement(
            width: width,
            contentSizeCategory: contentSizeCategory,
            height: height
        )
        return height
    }
}
