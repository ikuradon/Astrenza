import SwiftUI

public struct RepostContextChip: View {
    @Environment(\.appTheme) private var theme

    private let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs.cgFloat) {
            Image(systemName: DSIcon.repost.systemName)
                .font(DSIcon.repost.font(for: .compactBadge, weight: .bold))

            Text(text)
                .font(DSTypography.captionEmphasized.font)
                .lineLimit(1)
        }
        .foregroundStyle(theme.color(.repost))
        .padding(.horizontal, DSSpacing.lg.cgFloat)
        .frame(minHeight: CGFloat(DSControlSize.minimumHitTarget))
        .background(theme.color(.repost).opacity(0.12), in: Capsule())
    }
}
