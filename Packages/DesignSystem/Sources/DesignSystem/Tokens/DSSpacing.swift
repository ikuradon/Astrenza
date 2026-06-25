import CoreGraphics

public enum DSSpacing: Double, CaseIterable, Codable, Sendable {
    case hairline = 1
    case xxs = 2
    case xs = 4
    case sm = 6
    case md = 8
    case lg = 10
    case xl = 12
    case xxl = 16
    case xxxl = 20
    case xxxxl = 24

    public var value: Double {
        rawValue
    }

    public var cgFloat: CGFloat {
        CGFloat(rawValue)
    }
}
