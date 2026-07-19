// Astrenza全体で共有する視覚表現の唯一の定義元。
import SwiftUI
import UIKit

// 画面固有のgeometryや操作閾値は含めず、複数画面で共有する視覚tokenだけを管理する。
enum AstrenzaDesignSystem {
    enum Palette {
        static let background = Color(uiColor: .astrenzaBackground)
        static let settingsBackground = Color(uiColor: .astrenzaSettingsBackground)
        static let settingsCard = Color(uiColor: .astrenzaSettingsCard)
        static let separator = Color(uiColor: .astrenzaSeparator)
        static let text = Color(uiColor: .astrenzaText)
        static let accent = Color(red: 0.62, green: 0.36, blue: 1.0)
        static let attachmentBackground = Color(uiColor: .astrenzaAttachmentBackground)
        static let emojiPickerBackground = Color(white: 0.18)
        static let linkPreviewFallbackBackground = Color(red: 0.93, green: 0.94, blue: 0.95)
        static let linkPreviewFallbackText = Color(red: 0.13, green: 0.15, blue: 0.18)

        enum Logo {
            static let darkBackground = Color(red: 0.96, green: 0.91, blue: 1.0)
            static let lightBackground = Color(red: 0.98, green: 0.95, blue: 1.0)
        }

        enum Onboarding {
            static let background = Color(red: 0.25, green: 0.02, blue: 0.82)
            static let backgroundMiddle = Color(red: 0.38, green: 0.0, blue: 0.92)
            static let backgroundDeep = Color(red: 0.11, green: 0.0, blue: 0.34)
            static let accent = Color(red: 0.74, green: 0.42, blue: 1.0)
            static let card = Color.white.opacity(0.13)
            static let selectedCard = Color.white.opacity(0.25)
        }
    }

    enum Typography {
        enum Size: CGFloat {
            case point10 = 10
            case point11 = 11
            case point12 = 12
            case point13 = 13
            case point14 = 14
            case point15 = 15
            case point16 = 16
            case point17 = 17
            case point18 = 18
            case point19 = 19
            case point20 = 20
            case point21 = 21
            case point22 = 22
            case point23 = 23
            case point24 = 24
            case point25 = 25
            case point26 = 26
            case point27 = 27
            case point28 = 28
            case point30 = 30
            case point31 = 31
            case point32 = 32
            case point34 = 34
            case point38 = 38
            case point42 = 42
            case point82 = 82
            case point118 = 118
        }

        static func font(
            _ size: Size,
            weight: Font.Weight = .regular,
            design: Font.Design = .default
        ) -> Font {
            .system(size: size.rawValue, weight: weight, design: design)
        }

        static func uiFont(
            _ size: Size,
            weight: UIFont.Weight = .regular
        ) -> UIFont {
            .systemFont(ofSize: size.rawValue, weight: weight)
        }
    }

    enum Spacing {
        static let point1: CGFloat = 1
        static let point2: CGFloat = 2
        static let point3: CGFloat = 3
        static let point4: CGFloat = 4
        static let point5: CGFloat = 5
        static let point6: CGFloat = 6
        static let point7: CGFloat = 7
        static let point8: CGFloat = 8
        static let point9: CGFloat = 9
        static let point10: CGFloat = 10
        static let point11: CGFloat = 11
        static let point12: CGFloat = 12
        static let point13: CGFloat = 13
        static let point14: CGFloat = 14
        static let point15: CGFloat = 15
        static let point16: CGFloat = 16
        static let point18: CGFloat = 18
        static let point20: CGFloat = 20
        static let point22: CGFloat = 22
        static let point24: CGFloat = 24
        static let point26: CGFloat = 26
        static let point28: CGFloat = 28
        static let point30: CGFloat = 30
        static let point32: CGFloat = 32
        static let point34: CGFloat = 34
    }

    enum Radius {
        static let point8: CGFloat = 8
        static let point9: CGFloat = 9
        static let point10: CGFloat = 10
        static let point12: CGFloat = 12
        static let point13: CGFloat = 13
        static let point14: CGFloat = 14
        static let point15: CGFloat = 15
        static let point16: CGFloat = 16
        static let point18: CGFloat = 18
        static let point20: CGFloat = 20
        static let point24: CGFloat = 24
        static let point26: CGFloat = 26
    }

    enum Motion {
        static let instant: TimeInterval = 0.12
        static let quick: TimeInterval = 0.16
        static let fast: TimeInterval = 0.18
        static let responsive: TimeInterval = 0.20
        static let standard: TimeInterval = 0.22
        static let relaxed: TimeInterval = 0.24
        static let emphasized: TimeInterval = 0.28
        static let slow: TimeInterval = 0.30
    }

    enum Timeline {
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
}

typealias AstrenzaPalette = AstrenzaDesignSystem.Palette
typealias AstrenzaTypography = AstrenzaDesignSystem.Typography
typealias AstrenzaSpacing = AstrenzaDesignSystem.Spacing
typealias AstrenzaRadius = AstrenzaDesignSystem.Radius
typealias AstrenzaMotion = AstrenzaDesignSystem.Motion
typealias AstrenzaTimelineMetrics = AstrenzaDesignSystem.Timeline

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

extension Color {
    static let astrenzaBackground = AstrenzaPalette.background
    static let astrenzaSettingsBackground = AstrenzaPalette.settingsBackground
    static let astrenzaSettingsCard = AstrenzaPalette.settingsCard
    static let astrenzaSeparator = AstrenzaPalette.separator
    static let astrenzaText = AstrenzaPalette.text
    static let astrenzaAccent = AstrenzaPalette.accent
    static let astrenzaAttachmentBackground = AstrenzaPalette.attachmentBackground
}

extension Font {
    static func astrenza(
        _ size: AstrenzaTypography.Size,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        AstrenzaTypography.font(size, weight: weight, design: design)
    }
}

extension UIFont {
    static func astrenza(
        _ size: AstrenzaTypography.Size,
        weight: UIFont.Weight = .regular
    ) -> UIFont {
        AstrenzaTypography.uiFont(size, weight: weight)
    }
}

extension View {
    func astrenzaGlass<S: Shape>(tint: Color? = nil, in shape: S) -> some View {
        let baseGlass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
        return glassEffect(baseGlass.interactive(), in: shape)
    }
}

private extension UIColor {
    static let astrenzaBackground = UIColor { traits in
        switch AstrenzaThemeResolver.mode(for: traits) {
        case .light:
            return UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
        case .dark:
            return UIColor(red: 0.055, green: 0.055, blue: 0.065, alpha: 1)
        case .oled:
            return UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        }
    }

    static let astrenzaSettingsBackground = UIColor { traits in
        switch AstrenzaThemeResolver.mode(for: traits) {
        case .light:
            return UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)
        case .dark:
            return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .oled:
            return UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        }
    }

    static let astrenzaSettingsCard = UIColor { traits in
        switch AstrenzaThemeResolver.mode(for: traits) {
        case .light:
            return UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .dark:
            return UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        case .oled:
            return UIColor(red: 0.055, green: 0.055, blue: 0.06, alpha: 1)
        }
    }

    static let astrenzaSeparator = UIColor { traits in
        switch AstrenzaThemeResolver.mode(for: traits) {
        case .light:
            return UIColor.black.withAlphaComponent(0.10)
        case .dark:
            return UIColor.white.withAlphaComponent(0.10)
        case .oled:
            return UIColor.white.withAlphaComponent(0.12)
        }
    }

    static let astrenzaText = UIColor { traits in
        switch AstrenzaThemeResolver.mode(for: traits) {
        case .light:
            return UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        case .dark:
            return UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1)
        case .oled:
            return UIColor(red: 0.82, green: 0.82, blue: 0.85, alpha: 1)
        }
    }

    static let astrenzaAttachmentBackground = UIColor { traits in
        switch AstrenzaThemeResolver.mode(for: traits) {
        case .light:
            return UIColor(red: 0.90, green: 0.90, blue: 0.925, alpha: 1)
        case .dark:
            return UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1)
        case .oled:
            return UIColor(red: 0.055, green: 0.055, blue: 0.06, alpha: 1)
        }
    }
}

private enum AstrenzaThemeResolver {
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
