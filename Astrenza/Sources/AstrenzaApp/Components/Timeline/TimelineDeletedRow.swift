import SwiftUI

struct TimelineDeletedRow: View {
    let entry: TimelineDeletedEntry

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point10) {
            Image(systemName: "trash")
                .font(.astrenza(.point13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)

            Text("Deleted")
                .font(.astrenza(.point15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)

            Spacer(minLength: 0)
        }
        .padding(.leading, 82)
        .padding(.trailing, AstrenzaSpacing.point16)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.astrenzaSeparator)
                .padding(.leading, 82)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deleted")
        .accessibilityIdentifier("timeline.deleted.\(entry.id)")
    }
}
