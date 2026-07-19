import SwiftUI

struct AstrenzaLogoMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: CGFloat = 96
    var backgroundColor: Color?
    var strokeColor: Color = Color.white.opacity(0.1)
    var shadowColor: Color = Color.black.opacity(0.18)

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .padding(size * 0.18)
            .frame(width: size, height: size)
            .background(resolvedBackgroundColor, in: Circle())
            .overlay {
                Circle()
                    .stroke(strokeColor, lineWidth: max(1, size * 0.015))
            }
            .shadow(color: shadowColor, radius: size * 0.12, y: size * 0.08)
    }

    private var resolvedBackgroundColor: Color {
        if let backgroundColor {
            return backgroundColor
        }
        return colorScheme == .dark
            ? AstrenzaPalette.Logo.darkBackground
            : AstrenzaPalette.Logo.lightBackground
    }
}
