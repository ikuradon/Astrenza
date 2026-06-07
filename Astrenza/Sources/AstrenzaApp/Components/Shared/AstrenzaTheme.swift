import SwiftUI
import UIKit

enum AstrenzaThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case oled

    static let storageKey = "astrenza.themeMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .oled: "OLED"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .oled: .dark
        }
    }
}

enum AstrenzaTimelineMetrics {
    static let avatarSize: CGFloat = 42
    static let quotedAvatarSize: CGFloat = 26
    static let contextAvatarSize: CGFloat = 20
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 10
    static let rowAvatarSpacing: CGFloat = 10
    static let rowContentSpacing: CGFloat = 6
    static let bodyFontSize: CGFloat = 15
    static let bodyLineSpacing: CGFloat = 2
    static let authorPrimaryFontSize: CGFloat = 15
    static let authorSecondaryFontSize: CGFloat = 13
    static let timestampFontSize: CGFloat = 13
    static let actionHeight: CGFloat = 22
    static let actionIconSize: CGFloat = 15
    static let detailActionHeight: CGFloat = 26
    static let detailActionIconSize: CGFloat = 17
}

extension Color {
    static let astrenzaBackground = Color(uiColor: .astrenzaBackground)
    static let astrenzaSettingsBackground = Color(uiColor: .astrenzaSettingsBackground)
    static let astrenzaSettingsCard = Color(uiColor: .astrenzaSettingsCard)
    static let astrenzaSeparator = Color(uiColor: .astrenzaSeparator)
    static let astrenzaText = Color(uiColor: .astrenzaText)
    static let astrenzaAccent = Color(red: 0.62, green: 0.36, blue: 1.0)
    static let astrenzaAttachmentBackground = Color(uiColor: .astrenzaAttachmentBackground)
}

extension View {
    func astrenzaGlass<S: Shape>(tint: Color? = nil, in shape: S) -> some View {
        let baseGlass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
        return glassEffect(baseGlass.interactive(), in: shape)
    }
}

private extension UIColor {
    static let astrenzaBackground = UIColor { traits in
        switch AstrenzaThemePalette.mode(for: traits) {
        case .light:
            return UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
        case .dark:
            return UIColor(red: 0.055, green: 0.055, blue: 0.065, alpha: 1)
        case .oled:
            return UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        }
    }

    static let astrenzaSettingsBackground = UIColor { traits in
        switch AstrenzaThemePalette.mode(for: traits) {
        case .light:
            return UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)
        case .dark:
            return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .oled:
            return UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        }
    }

    static let astrenzaSettingsCard = UIColor { traits in
        switch AstrenzaThemePalette.mode(for: traits) {
        case .light:
            return UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .dark:
            return UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        case .oled:
            return UIColor(red: 0.055, green: 0.055, blue: 0.06, alpha: 1)
        }
    }

    static let astrenzaSeparator = UIColor { traits in
        switch AstrenzaThemePalette.mode(for: traits) {
        case .light:
            return UIColor.black.withAlphaComponent(0.10)
        case .dark:
            return UIColor.white.withAlphaComponent(0.10)
        case .oled:
            return UIColor.white.withAlphaComponent(0.12)
        }
    }

    static let astrenzaText = UIColor { traits in
        switch AstrenzaThemePalette.mode(for: traits) {
        case .light:
            return UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        case .dark:
            return UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1)
        case .oled:
            return UIColor(red: 0.82, green: 0.82, blue: 0.85, alpha: 1)
        }
    }

    static let astrenzaAttachmentBackground = UIColor { traits in
        switch AstrenzaThemePalette.mode(for: traits) {
        case .light:
            return UIColor(red: 0.90, green: 0.90, blue: 0.925, alpha: 1)
        case .dark:
            return UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1)
        case .oled:
            return UIColor(red: 0.055, green: 0.055, blue: 0.06, alpha: 1)
        }
    }
}

private enum AstrenzaThemePalette {
    enum ResolvedMode {
        case light
        case dark
        case oled
    }

    static func mode(for traits: UITraitCollection) -> ResolvedMode {
        let storedValue = UserDefaults.standard.string(forKey: AstrenzaThemeMode.storageKey)
        let themeMode = storedValue.flatMap(AstrenzaThemeMode.init(rawValue:)) ?? .system

        switch themeMode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .oled:
            return .oled
        case .system:
            return traits.userInterfaceStyle == .light ? .light : .dark
        }
    }
}
