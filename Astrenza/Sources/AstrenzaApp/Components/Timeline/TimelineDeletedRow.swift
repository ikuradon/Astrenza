import SwiftUI

struct TimelineDeletedRow: View {
    let entry: TimelineDeletedEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)

            Text("Deleted")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)

            Spacer(minLength: 0)
        }
        .padding(.leading, 82)
        .padding(.trailing, 16)
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
