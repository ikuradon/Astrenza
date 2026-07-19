import SwiftUI

struct HomeTimelineReplyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.astrenza(.point23, weight: .heavy))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .astrenzaGlass(tint: Color.white.opacity(0.08), in: Circle())
        .shadow(color: Color.black.opacity(0.26), radius: 18, y: 10)
        .accessibilityLabel("Reply")
    }
}
