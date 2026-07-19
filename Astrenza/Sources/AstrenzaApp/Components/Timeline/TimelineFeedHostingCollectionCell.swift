import SwiftUI
import UIKit

struct TimelineFeedCellSizingIdentity: Hashable {
    let entryID: TimelineFeedEntry.ID
    let geometryFingerprint: Int
    let swipeSettings: TimelineSwipeSettings
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
    private let hostingController = UIHostingController(
        rootView: AnyView(EmptyView())
    )

    var hostedContentFrame: CGRect {
        hostingController.view.frame
    }

    var hostedSafeAreaIsDisabled: Bool {
        hostingController.safeAreaRegions.isEmpty
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        contentView.clipsToBounds = true
        hostingController.safeAreaRegions = []
        hostingController.view.backgroundColor = .clear
        hostingController.view.clipsToBounds = true
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(
                equalTo: contentView.topAnchor
            ),
            hostingController.view.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            hostingController.view.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            hostingController.view.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        rootView: AnyView,
        parentViewController: UIViewController?,
        sizingIdentity: TimelineFeedCellSizingIdentity
    ) {
        if self.sizingIdentity != sizingIdentity {
            measurement = nil
        }
        attachHostingControllerIfNeeded(to: parentViewController)
        self.sizingIdentity = sizingIdentity
        hostingController.rootView = rootView
        clipsToBounds = true
        contentView.clipsToBounds = true
        hostingController.view.clipsToBounds = true
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingController.rootView = AnyView(EmptyView())
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

        let fittedSize = hostingController.sizeThatFits(
            in: CGSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
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

    private func attachHostingControllerIfNeeded(
        to parentViewController: UIViewController?
    ) {
        guard let parentViewController,
              hostingController.parent !== parentViewController
        else { return }

        if hostingController.parent != nil {
            hostingController.willMove(toParent: nil)
            hostingController.removeFromParent()
        }
        parentViewController.addChild(hostingController)
        hostingController.didMove(toParent: parentViewController)
    }
}
