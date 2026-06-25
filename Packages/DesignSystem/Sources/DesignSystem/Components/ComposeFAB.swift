import SwiftUI

public struct ComposeFAB: View {
    @Environment(\.appTheme) private var theme

    private let accessibilityLabel: String
    private let action: () -> Void

    public init(accessibilityLabel: String = "Compose", action: @escaping () -> Void = {}) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: DSIcon.compose.systemName)
                .font(DSIcon.compose.font(for: .composeFAB, weight: .bold))
                .foregroundStyle(theme.color(.textPrimary))
                .frame(
                    width: CGFloat(DSControlSize.composeFAB.hitTargetWidth),
                    height: CGFloat(DSControlSize.composeFAB.hitTargetHeight)
                )
                .background(theme.color(.accent), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("compose.fab")
    }
}
