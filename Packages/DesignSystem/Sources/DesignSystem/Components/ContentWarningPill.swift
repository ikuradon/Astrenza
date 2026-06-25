import SwiftUI

public struct ContentWarningPill: View {
    @Environment(\.appTheme) private var theme

    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs.cgFloat) {
            Image(systemName: DSIcon.warning.systemName)
                .font(DSIcon.warning.font(for: .compactBadge, weight: .bold))

            Text(text)
                .font(DSTypography.badge.font)
                .lineLimit(1)
        }
        .foregroundStyle(theme.color(.warning))
        .padding(.horizontal, DSSpacing.xl.cgFloat)
        .frame(minHeight: CGFloat(DSControlSize.minimumHitTarget))
        .background(theme.color(.warning).opacity(0.14), in: Capsule())
    }
}
