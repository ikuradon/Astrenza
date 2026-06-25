import SwiftUI

public enum DSFontWeight: String, Codable, Sendable {
    case regular
    case medium
    case semibold
    case bold
    case heavy

    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

public enum DSFontDesign: String, Codable, Sendable {
    case `default`
    case rounded

    var swiftUIDesign: Font.Design {
        switch self {
        case .default: .default
        case .rounded: .rounded
        }
    }
}

public struct DSTypographyStyle: Equatable, Codable, Sendable {
    public var size: Double
    public var weight: DSFontWeight
    public var design: DSFontDesign
    public var lineSpacing: Double

    public init(size: Double, weight: DSFontWeight, design: DSFontDesign = .rounded, lineSpacing: Double = 0) {
        self.size = size
        self.weight = weight
        self.design = design
        self.lineSpacing = lineSpacing
    }

    public var font: Font {
        .system(size: CGFloat(size), weight: weight.swiftUIWeight, design: design.swiftUIDesign)
    }
}

public enum DSTypography: String, CaseIterable, Codable, Sendable {
    case body
    case bodyEmphasized
    case authorName
    case authorHandle
    case caption
    case captionEmphasized
    case badge
    case actionCount
    case composeFAB

    public var style: DSTypographyStyle {
        switch self {
        case .body:
            DSTypographyStyle(size: 15, weight: .regular, lineSpacing: 2)
        case .bodyEmphasized:
            DSTypographyStyle(size: 15, weight: .semibold, lineSpacing: 2)
        case .authorName:
            DSTypographyStyle(size: 15, weight: .bold)
        case .authorHandle:
            DSTypographyStyle(size: 13, weight: .semibold)
        case .caption:
            DSTypographyStyle(size: 12, weight: .medium)
        case .captionEmphasized:
            DSTypographyStyle(size: 12, weight: .bold)
        case .badge:
            DSTypographyStyle(size: 12, weight: .heavy)
        case .actionCount:
            DSTypographyStyle(size: 12, weight: .semibold)
        case .composeFAB:
            DSTypographyStyle(size: 22, weight: .bold, design: .default)
        }
    }

    public var font: Font {
        style.font
    }
}
