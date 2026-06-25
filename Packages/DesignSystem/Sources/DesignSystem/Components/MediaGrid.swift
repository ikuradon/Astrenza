import SwiftUI

public struct DSMediaGridItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var aspectRatio: Double?
    public var accessibilityLabel: String

    public init(id: String, aspectRatio: Double? = nil, accessibilityLabel: String = "Media") {
        self.id = id
        self.aspectRatio = aspectRatio
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct MediaGrid: View {
    @Environment(\.appTheme) private var theme

    private let items: [DSMediaGridItem]
    private let metrics: DSMediaMetrics
    private let maximumVisibleItems: Int

    public init(
        items: [DSMediaGridItem],
        metrics: DSMediaMetrics = .timeline,
        maximumVisibleItems: Int = 4
    ) {
        self.items = items
        self.metrics = metrics
        self.maximumVisibleItems = maximumVisibleItems
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: CGFloat(metrics.gridDivider)) {
            ForEach(visibleItems) { item in
                RoundedRectangle(cornerRadius: DSRadius.sm.cgFloat, style: .continuous)
                    .fill(theme.color(.placeholder))
                    .aspectRatio(item.aspectRatio ?? metrics.defaultAspectRatio, contentMode: .fit)
                    .frame(minHeight: CGFloat(metrics.minimumReservedHeight / 2))
                    .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .padding(CGFloat(metrics.gridDivider))
        .background(theme.color(.cardBackground), in: RoundedRectangle(cornerRadius: CGFloat(metrics.cornerRadius), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(metrics.cornerRadius), style: .continuous)
                .stroke(theme.color(.separator), lineWidth: DSSpacing.hairline.cgFloat)
        }
    }

    private var columns: [GridItem] {
        let count = visibleItems.count == 1 ? 1 : 2
        return Array(
            repeating: GridItem(.flexible(), spacing: CGFloat(metrics.gridDivider)),
            count: count
        )
    }

    private var visibleItems: [DSMediaGridItem] {
        if items.isEmpty {
            return [DSMediaGridItem(id: "media-placeholder", aspectRatio: metrics.defaultAspectRatio)]
        }
        return Array(items.prefix(maximumVisibleItems))
    }
}
