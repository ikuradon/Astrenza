import SwiftUI

struct TimelineSwitcherMenu: View {
    @Binding var selected: TimelineKind

    var body: some View {
        VStack(spacing: 0) {
            ForEach(TimelineKind.allCases) { kind in
                Button {
                    selected = kind
                } label: {
                    HStack {
                        Text(kind.title)
                            .font(.astrenza(.point19, weight: .medium, design: .rounded))
                        Spacer()
                        Image(systemName: kind.systemName)
                            .font(.astrenza(.point22, weight: .semibold))
                    }
                    .foregroundStyle(kind == selected ? .primary : .secondary)
                    .padding(.horizontal, AstrenzaSpacing.point20)
                    .frame(height: 55)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if kind != TimelineKind.allCases.last {
                    Divider().overlay(Color.astrenzaSeparator)
                }
            }
        }
        .frame(width: 286)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
    }
}
