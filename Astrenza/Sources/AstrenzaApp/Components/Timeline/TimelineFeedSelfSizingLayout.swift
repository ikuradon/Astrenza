import UIKit

final class TimelineFeedSelfSizingLayout: UICollectionViewFlowLayout {
    private let estimatedRowHeight: CGFloat

    static func make(
        topContentPadding: CGFloat,
        estimatedRowHeight: CGFloat = 180
    ) -> TimelineFeedSelfSizingLayout {
        TimelineFeedSelfSizingLayout(
            topContentPadding: topContentPadding,
            estimatedRowHeight: estimatedRowHeight
        )
    }

    private init(
        topContentPadding: CGFloat,
        estimatedRowHeight: CGFloat
    ) {
        self.estimatedRowHeight = estimatedRowHeight
        super.init()
        scrollDirection = .vertical
        minimumLineSpacing = 0
        minimumInteritemSpacing = 0
        sectionInset = UIEdgeInsets(
            top: topContentPadding,
            left: 0,
            bottom: 0,
            right: 0
        )
        estimatedItemSize = CGSize(width: 1, height: estimatedRowHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func prepare() {
        if let collectionView {
            let displayScale = max(
                1,
                collectionView.traitCollection.displayScale
            )
            let onePixel = 1 / displayScale
            // Flow layoutはitem幅がsection幅未満である必要があるため、
            // trailing側だけ1px広げてRowの表示幅は従来どおり維持する。
            if abs(sectionInset.right + onePixel) > 0.001 {
                sectionInset.right = -onePixel
            }
            let availableWidth = max(
                1,
                collectionView.bounds.width -
                    sectionInset.left
            )
            if abs(estimatedItemSize.width - availableWidth) > 0.5 {
                estimatedItemSize = CGSize(
                    width: availableWidth,
                    height: estimatedRowHeight
                )
            }
        }
        super.prepare()
    }

    override func shouldInvalidateLayout(
        forBoundsChange newBounds: CGRect
    ) -> Bool {
        guard let collectionView else { return false }
        return abs(collectionView.bounds.width - newBounds.width) > 0.5
    }
}
