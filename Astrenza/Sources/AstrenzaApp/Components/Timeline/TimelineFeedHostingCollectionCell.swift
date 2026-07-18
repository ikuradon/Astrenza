import UIKit

final class TimelineFeedHostingCollectionCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        guard let attributes = layoutAttributes.copy()
            as? UICollectionViewLayoutAttributes
        else { return layoutAttributes }
        let targetSize = CGSize(
            width: layoutAttributes.size.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        setNeedsLayout()
        layoutIfNeeded()
        let fittedSize = contentView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        attributes.size.width = layoutAttributes.size.width
        attributes.size.height = max(1, fittedSize.height)
        return attributes
    }
}
