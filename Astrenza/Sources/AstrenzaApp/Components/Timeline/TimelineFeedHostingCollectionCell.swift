import UIKit

final class TimelineFeedHostingCollectionCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(
            layoutAttributes
        )
        attributes.size.width = layoutAttributes.size.width
        attributes.size.height = ceil(attributes.size.height)
        return attributes
    }
}
