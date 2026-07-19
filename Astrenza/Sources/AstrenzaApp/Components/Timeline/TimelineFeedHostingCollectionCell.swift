import UIKit

final class TimelineFeedHostingCollectionCell: UICollectionViewCell {
    private var representedEntryID: TimelineFeedEntry.ID?
    private var onMeasuredHeight:
        ((TimelineFeedEntry.ID, CGFloat) -> Void)?
    private var measurementGeneration: UInt64 = 0
    private var isMeasurementScheduled = false

    func configureMeasurement(
        for entryID: TimelineFeedEntry.ID,
        onMeasuredHeight:
            @escaping (TimelineFeedEntry.ID, CGFloat) -> Void
    ) {
        measurementGeneration &+= 1
        isMeasurementScheduled = false
        representedEntryID = entryID
        self.onMeasuredHeight = onMeasuredHeight
        scheduleMeasurement(width: bounds.width)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        measurementGeneration &+= 1
        isMeasurementScheduled = false
        representedEntryID = nil
        onMeasuredHeight = nil
    }

    override func apply(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) {
        super.apply(layoutAttributes)
        scheduleMeasurement(width: layoutAttributes.size.width)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        scheduleMeasurement(width: layoutAttributes.size.width)
        return layoutAttributes
    }

    private func scheduleMeasurement(width: CGFloat) {
        guard representedEntryID != nil,
              width > 0,
              !isMeasurementScheduled
        else { return }
        isMeasurementScheduled = true
        let generation = measurementGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  measurementGeneration == generation,
                  let entryID = representedEntryID
            else { return }
            isMeasurementScheduled = false
            setNeedsLayout()
            layoutIfNeeded()
            let fittedSize = contentView.systemLayoutSizeFitting(
                CGSize(
                    width: width,
                    height: UIView.layoutFittingCompressedSize.height
                ),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            onMeasuredHeight?(entryID, max(1, fittedSize.height))
        }
    }
}
