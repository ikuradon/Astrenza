import UIKit

struct TimelineFeedCellSizingIdentity: Equatable {
    let entryID: TimelineFeedEntry.ID
    let renderFingerprint: Int
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
        let width = layoutAttributes.size.width
        let contentSizeCategory = traitCollection.preferredContentSizeCategory
        // Flow Layoutはscroll中にも同じRowを再照会する。前回boundsを
        // 再測定へ混ぜず、同一表示構成・同一幅なら確定済みの高さを返す。
        if let measurement,
           abs(measurement.width - width) <= 0.5,
           measurement.contentSizeCategory == contentSizeCategory {
            return attributes(
                copying: layoutAttributes,
                width: width,
                height: measurement.height
            )
        }

        // superの標準self-sizingと手動計測を重ねると、標準計測後の高さが
        // contentViewの次の入力になるため、ここでは手動計測だけを採用する。
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
        return attributes(
            copying: layoutAttributes,
            width: width,
            height: height
        )
    }

    private func attributes(
        copying layoutAttributes: UICollectionViewLayoutAttributes,
        width: CGFloat,
        height: CGFloat
    ) -> UICollectionViewLayoutAttributes {
        guard let preferred = layoutAttributes.copy()
            as? UICollectionViewLayoutAttributes
        else { return layoutAttributes }
        preferred.size = CGSize(width: width, height: height)
        return preferred
    }
}
