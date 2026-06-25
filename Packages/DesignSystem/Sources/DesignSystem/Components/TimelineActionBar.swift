import SwiftUI

public struct TimelineActionBarItem: Identifiable {
    public var id: String
    public var icon: DSIcon
    public var activeIcon: DSIcon?
    public var isActive: Bool
    public var accessibilityLabel: String
    public var countText: String?
    public var action: () -> Void

    public init(
        id: String,
        icon: DSIcon,
        activeIcon: DSIcon? = nil,
        isActive: Bool = false,
        accessibilityLabel: String,
        countText: String? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.id = id
        self.icon = icon
        self.activeIcon = activeIcon
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.countText = countText
        self.action = action
    }
}

public struct TimelineActionBar: View {
    @Environment(\.appTheme) private var theme

    private let items: [TimelineActionBarItem]
    private let metrics: TimelineActionMetrics

    public init(items: [TimelineActionBarItem], metrics: TimelineActionMetrics = .default) {
        self.items = items
        self.metrics = metrics
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs.cgFloat) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: DSSpacing.xs.cgFloat) {
                        Image(systemName: icon(for: item).systemName)
                            .font(icon(for: item).font(size: metrics.visualIconSize, weight: item.isActive ? .bold : .semibold))

                        if let countText = item.countText {
                            Text(countText)
                                .font(DSTypography.actionCount.font)
                        }
                    }
                    .foregroundStyle(theme.color(item.isActive ? .accent : .textSecondary))
                    .frame(minWidth: CGFloat(metrics.targetWidth), minHeight: CGFloat(metrics.targetHeight))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityIdentifier("timeline.action.\(item.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for item: TimelineActionBarItem) -> DSIcon {
        (item.isActive ? item.activeIcon : nil) ?? item.icon
    }
}
