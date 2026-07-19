import SwiftUI
import UIKit

final class TimelineFeedHostingCollectionCell: UICollectionViewCell {
    private var representedEntryID: TimelineFeedEntry.ID?
    private var onMeasuredHeight:
        ((TimelineFeedEntry.ID, CGFloat) -> Void)?
    private var measurementGeneration: UInt64 = 0
    private var isMeasurementScheduled = false

    func configureMeasurement(
        for entryID: TimelineFeedEntry.ID,
        width: CGFloat,
        isEnabled: Bool,
        onMeasuredHeight:
            @escaping (TimelineFeedEntry.ID, CGFloat) -> Void
    ) {
        measurementGeneration &+= 1
        isMeasurementScheduled = false
        representedEntryID = entryID
        self.onMeasuredHeight = onMeasuredHeight
        if isEnabled {
            scheduleMeasurement(width: width)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        measurementGeneration &+= 1
        isMeasurementScheduled = false
        representedEntryID = nil
        onMeasuredHeight = nil
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

@MainActor
final class TimelineFeedOffscreenMeasurer {
    private let hostingController = UIHostingController(
        rootView: AnyView(EmptyView())
    )

    init() {
        hostingController.view.backgroundColor = .clear
    }

    func height<Content: View>(
        for content: Content,
        width: CGFloat,
        context: TimelineRowMeasurementContext
    ) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        let layoutDirection: LayoutDirection =
            context.layoutDirection == "rtl" ? .rightToLeft : .leftToRight
        let dynamicTypeSize = DynamicTypeSize(
            contentSizeCategory: UIContentSizeCategory(
                rawValue: context.contentSizeCategory
            )
        )
        hostingController.rootView = AnyView(
            content
                .frame(width: width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, layoutDirection)
                .environment(
                    \.locale,
                    Locale(identifier: context.localeIdentifier)
                )
                .dynamicTypeSize(dynamicTypeSize)
        )
        hostingController.view.semanticContentAttribute =
            layoutDirection == .rightToLeft
                ? .forceRightToLeft
                : .forceLeftToRight
        hostingController.view.bounds = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: 1
        )
        hostingController.view.invalidateIntrinsicContentSize()
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        let rawHeight = hostingController.sizeThatFits(
            in: CGSize(
                width: width,
                height: UIView.layoutFittingExpandedSize.height
            )
        ).height
        let scale = max(
            CGFloat(context.displayScaleMilli) / 1_000,
            1
        )
        return ceil(rawHeight * scale) / scale
    }
}

private extension DynamicTypeSize {
    init(contentSizeCategory: UIContentSizeCategory) {
        switch contentSizeCategory {
        case .extraSmall:
            self = .xSmall
        case .small:
            self = .small
        case .medium:
            self = .medium
        case .extraLarge:
            self = .xLarge
        case .extraExtraLarge:
            self = .xxLarge
        case .extraExtraExtraLarge:
            self = .xxxLarge
        case .accessibilityMedium:
            self = .accessibility1
        case .accessibilityLarge:
            self = .accessibility2
        case .accessibilityExtraLarge:
            self = .accessibility3
        case .accessibilityExtraExtraLarge:
            self = .accessibility4
        case .accessibilityExtraExtraExtraLarge:
            self = .accessibility5
        default:
            self = .large
        }
    }
}
