import SwiftUI

public enum DSColor: String, CaseIterable, Codable, Sendable {
    case appBackground
    case timelineBackground
    case rowBackground
    case rowPressedBackground
    case textPrimary
    case textSecondary
    case textTertiary
    case accent
    case separator
    case cardBackground
    case placeholder
    case warning
    case destructive
    case repost
    case reply
    case quote
}

public struct DSColorValue: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}
