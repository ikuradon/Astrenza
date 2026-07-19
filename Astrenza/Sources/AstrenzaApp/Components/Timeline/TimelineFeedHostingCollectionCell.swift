import UIKit

final class TimelineFeedHostingCollectionCell: UICollectionViewCell {
    private var representedEntryID: TimelineFeedEntry.ID?
    private var onMeasuredHeight:
        ((TimelineFeedEntry.ID, CGFloat) -> Void)?
    private var measurementGeneration: UInt64 = 0
    private var isMeasurementScheduled = false
    private var lastReportedWidth: CGFloat?
    private var lastReportedHeight: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        contentView.clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configureMeasurement(
        for entryID: TimelineFeedEntry.ID,
        onMeasuredHeight:
            @escaping (TimelineFeedEntry.ID, CGFloat) -> Void
    ) {
        measurementGeneration &+= 1
        isMeasurementScheduled = false
        lastReportedWidth = nil
        lastReportedHeight = nil
        representedEntryID = entryID
        self.onMeasuredHeight = onMeasuredHeight
        scheduleMeasurement(width: bounds.width)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        measurementGeneration &+= 1
        isMeasurementScheduled = false
        lastReportedWidth = nil
        lastReportedHeight = nil
        representedEntryID = nil
        onMeasuredHeight = nil
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
            let fittedHeight = max(1, fittedSize.height)
            let widthChanged = lastReportedWidth.map {
                abs($0 - width) > 0.5
            } ?? true
            let heightChanged = lastReportedHeight.map {
                abs($0 - fittedHeight) > 0.5
            } ?? true
            guard widthChanged || heightChanged else { return }
            lastReportedWidth = width
            lastReportedHeight = fittedHeight
            onMeasuredHeight?(entryID, fittedHeight)
        }
    }
}
