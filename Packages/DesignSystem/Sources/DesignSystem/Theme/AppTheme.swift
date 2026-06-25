import SwiftUI

public enum AppThemeKind: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
    case black
    case highContrast
}

public struct AppTheme: Equatable, Codable, Sendable {
    public var kind: AppThemeKind
    public var colors: [DSColor: DSColorValue]

    public init(kind: AppThemeKind, colors: [DSColor: DSColorValue]) {
        self.kind = kind
        self.colors = colors
    }

    public func color(_ token: DSColor) -> Color {
        (colors[token] ?? AppTheme.dark.colors[token] ?? DSColorValue(red: 1, green: 0, blue: 1)).color
    }

    public static let system = AppTheme(kind: .system, colors: AppTheme.dark.colors)

    public static let light = AppTheme(kind: .light, colors: [
        .appBackground: DSColorValue(red: 0.965, green: 0.965, blue: 0.975),
        .timelineBackground: DSColorValue(red: 0.965, green: 0.965, blue: 0.975),
        .rowBackground: DSColorValue(red: 1, green: 1, blue: 1),
        .rowPressedBackground: DSColorValue(red: 0.92, green: 0.92, blue: 0.95),
        .textPrimary: DSColorValue(red: 0.11, green: 0.11, blue: 0.13),
        .textSecondary: DSColorValue(red: 0.36, green: 0.36, blue: 0.40),
        .textTertiary: DSColorValue(red: 0.54, green: 0.54, blue: 0.58),
        .accent: DSColorValue(red: 0.62, green: 0.36, blue: 1),
        .separator: DSColorValue(red: 0, green: 0, blue: 0, opacity: 0.10),
        .cardBackground: DSColorValue(red: 0.90, green: 0.90, blue: 0.925),
        .placeholder: DSColorValue(red: 0.82, green: 0.82, blue: 0.86),
        .warning: DSColorValue(red: 0.86, green: 0.55, blue: 0.08),
        .destructive: DSColorValue(red: 0.86, green: 0.18, blue: 0.24),
        .repost: DSColorValue(red: 0.20, green: 0.63, blue: 0.45),
        .reply: DSColorValue(red: 0.25, green: 0.50, blue: 0.90),
        .quote: DSColorValue(red: 0.62, green: 0.36, blue: 1)
    ])

    public static let dark = AppTheme(kind: .dark, colors: [
        .appBackground: DSColorValue(red: 0.055, green: 0.055, blue: 0.065),
        .timelineBackground: DSColorValue(red: 0.055, green: 0.055, blue: 0.065),
        .rowBackground: DSColorValue(red: 0.075, green: 0.075, blue: 0.085),
        .rowPressedBackground: DSColorValue(red: 0.12, green: 0.12, blue: 0.14),
        .textPrimary: DSColorValue(red: 0.92, green: 0.92, blue: 0.94),
        .textSecondary: DSColorValue(red: 0.72, green: 0.72, blue: 0.76),
        .textTertiary: DSColorValue(red: 0.50, green: 0.50, blue: 0.55),
        .accent: DSColorValue(red: 0.62, green: 0.36, blue: 1),
        .separator: DSColorValue(red: 1, green: 1, blue: 1, opacity: 0.10),
        .cardBackground: DSColorValue(red: 0.14, green: 0.14, blue: 0.15),
        .placeholder: DSColorValue(red: 0.24, green: 0.24, blue: 0.27),
        .warning: DSColorValue(red: 1.0, green: 0.72, blue: 0.22),
        .destructive: DSColorValue(red: 1.0, green: 0.32, blue: 0.38),
        .repost: DSColorValue(red: 0.36, green: 0.86, blue: 0.62),
        .reply: DSColorValue(red: 0.52, green: 0.70, blue: 1.0),
        .quote: DSColorValue(red: 0.72, green: 0.52, blue: 1)
    ])

    public static let black = AppTheme(kind: .black, colors: [
        .appBackground: DSColorValue(red: 0, green: 0, blue: 0),
        .timelineBackground: DSColorValue(red: 0, green: 0, blue: 0),
        .rowBackground: DSColorValue(red: 0.025, green: 0.025, blue: 0.030),
        .rowPressedBackground: DSColorValue(red: 0.08, green: 0.08, blue: 0.09),
        .textPrimary: DSColorValue(red: 0.94, green: 0.94, blue: 0.96),
        .textSecondary: DSColorValue(red: 0.74, green: 0.74, blue: 0.78),
        .textTertiary: DSColorValue(red: 0.52, green: 0.52, blue: 0.56),
        .accent: DSColorValue(red: 0.68, green: 0.43, blue: 1),
        .separator: DSColorValue(red: 1, green: 1, blue: 1, opacity: 0.12),
        .cardBackground: DSColorValue(red: 0.055, green: 0.055, blue: 0.06),
        .placeholder: DSColorValue(red: 0.16, green: 0.16, blue: 0.18),
        .warning: DSColorValue(red: 1.0, green: 0.72, blue: 0.22),
        .destructive: DSColorValue(red: 1.0, green: 0.32, blue: 0.38),
        .repost: DSColorValue(red: 0.36, green: 0.86, blue: 0.62),
        .reply: DSColorValue(red: 0.52, green: 0.70, blue: 1.0),
        .quote: DSColorValue(red: 0.72, green: 0.52, blue: 1)
    ])

    public static let highContrast = AppTheme(kind: .highContrast, colors: [
        .appBackground: DSColorValue(red: 0, green: 0, blue: 0),
        .timelineBackground: DSColorValue(red: 0, green: 0, blue: 0),
        .rowBackground: DSColorValue(red: 0.03, green: 0.03, blue: 0.03),
        .rowPressedBackground: DSColorValue(red: 0.15, green: 0.15, blue: 0.15),
        .textPrimary: DSColorValue(red: 1, green: 1, blue: 1),
        .textSecondary: DSColorValue(red: 0.86, green: 0.86, blue: 0.86),
        .textTertiary: DSColorValue(red: 0.72, green: 0.72, blue: 0.72),
        .accent: DSColorValue(red: 0.75, green: 0.58, blue: 1),
        .separator: DSColorValue(red: 1, green: 1, blue: 1, opacity: 0.24),
        .cardBackground: DSColorValue(red: 0.10, green: 0.10, blue: 0.10),
        .placeholder: DSColorValue(red: 0.28, green: 0.28, blue: 0.28),
        .warning: DSColorValue(red: 1.0, green: 0.82, blue: 0.26),
        .destructive: DSColorValue(red: 1.0, green: 0.40, blue: 0.46),
        .repost: DSColorValue(red: 0.50, green: 1.0, blue: 0.72),
        .reply: DSColorValue(red: 0.66, green: 0.82, blue: 1.0),
        .quote: DSColorValue(red: 0.82, green: 0.66, blue: 1)
    ])
}
