import SwiftUI

struct TimelineGapRow: View {
    let gap: TimelineGap
    let direction: TimelineGapFillDirection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 3) {
                    Text(gap.title)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(detailText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)

                trailingIndicator
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.astrenzaAccent.opacity(0.18), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gap.title). \(gap.detail)")
        .accessibilityIdentifier("timeline.gap.row")
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.astrenzaAccent.opacity(0.16))

            Image(systemName: iconSystemName)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Color.astrenzaAccent)
        }
        .frame(width: 34, height: 34)
    }

    private var detailText: String {
        switch gap.state {
        case .needsBackfill:
            "\(direction.label) from \(gap.relayCount) relays"
        case .fetching:
            direction == .newer
                ? "Requesting newer since/until windows"
                : "Requesting older since/until windows"
        case .limited:
            gap.detail
        }
    }

    private var iconSystemName: String {
        switch gap.state {
        case .fetching:
            "arrow.triangle.2.circlepath"
        case .needsBackfill, .limited:
            direction.systemName
        }
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        switch gap.state {
        case .fetching:
            ProgressView()
                .controlSize(.small)
                .tint(Color.astrenzaAccent)
        case .needsBackfill, .limited:
            Image(systemName: direction == .newer ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.astrenzaAccent.opacity(0.86))
        }
    }
}
