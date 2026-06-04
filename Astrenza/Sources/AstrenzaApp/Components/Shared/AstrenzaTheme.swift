import SwiftUI

extension Color {
    static let astrenzaBackground = Color(red: 0.01, green: 0.01, blue: 0.012)
    static let astrenzaSeparator = Color.white.opacity(0.1)
    static let astrenzaText = Color(red: 0.78, green: 0.78, blue: 0.8)
    static let astrenzaAccent = Color(red: 0.62, green: 0.36, blue: 1.0)
    static let astrenzaAttachmentBackground = Color(red: 0.12, green: 0.12, blue: 0.13)
}

extension View {
    func astrenzaGlass<S: Shape>(tint: Color? = nil, in shape: S) -> some View {
        let baseGlass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
        return glassEffect(baseGlass.interactive(), in: shape)
    }
}
