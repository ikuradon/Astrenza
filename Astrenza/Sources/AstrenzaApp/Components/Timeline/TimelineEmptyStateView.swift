import SwiftUI

struct TimelineEmptyStateView: View {
    let state: TimelineEmptyState
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: AstrenzaSpacing.point22) {
            symbol

            VStack(spacing: AstrenzaSpacing.point8) {
                Text(state.title)
                    .font(.astrenza(.point28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.astrenzaText)

                Text(state.message)
                    .font(.astrenza(.point16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 310)
            }

            HStack(spacing: AstrenzaSpacing.point12) {
                Button(action: onPrimaryAction) {
                    Label(state.primaryActionTitle, systemImage: "arrow.right")
                        .labelStyle(.titleOnly)
                        .font(.astrenza(.point16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.astrenzaBackground)
                        .frame(height: 42)
                        .padding(.horizontal, AstrenzaSpacing.point18)
                        .background(Color.astrenzaAccent, in: Capsule())
                }
                .buttonStyle(.plain)

                if let secondaryActionTitle = state.secondaryActionTitle,
                   let onSecondaryAction {
                    Button(action: onSecondaryAction) {
                        Text(secondaryActionTitle)
                            .font(.astrenza(.point16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.astrenzaAccent)
                            .frame(height: 42)
                            .padding(.horizontal, AstrenzaSpacing.point18)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AstrenzaSpacing.point28)
        .padding(.top, 150)
        .padding(.bottom, 120)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline.empty_state")
    }

    private var symbol: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.astrenzaAccent.opacity(0.26),
                            Color.cyan.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 92, height: 92)

            Image(systemName: state.systemName)
                .font(.astrenza(.point38, weight: .semibold))
                .foregroundStyle(Color.astrenzaAccent)
        }
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }
}
