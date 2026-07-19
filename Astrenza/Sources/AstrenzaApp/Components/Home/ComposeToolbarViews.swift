import SwiftUI

struct ComposeToolButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    init(systemName: String, label: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ComposeToolIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ComposeEmojiToolButton: View {
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        ComposeToolIcon(systemName: "face.smiling")
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.45, perform: onLongPress)
            .accessibilityLabel("Emoji")
            .accessibilityAddTraits(.isButton)
    }
}

struct ComposeToolIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.astrenza(.point22, weight: .bold))
            .foregroundStyle(Color.astrenzaAccent)
            .frame(width: 43, height: 44)
            .contentShape(Rectangle())
    }
}
