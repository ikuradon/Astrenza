import UIKit

final class TimelineFeedHostingCollectionCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let preferred = super.preferredLayoutAttributesFitting(
            layoutAttributes
        )
        let width = layoutAttributes.size.width
        let fittedSize = contentView.systemLayoutSizeFitting(
            CGSize(
                width: width,
                height: UIView.layoutFittingCompressedSize.height
            ),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let displayScale = max(1, traitCollection.displayScale)
        preferred.size = CGSize(
            width: width,
            height: max(
                1,
                ceil(fittedSize.height * displayScale) / displayScale
            )
        )
        return preferred
    }
}
