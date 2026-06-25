import CoreGraphics

public enum DSRadius: Double, CaseIterable, Codable, Sendable {
    case none = 0
    case xs = 4
    case sm = 8
    case md = 10
    case lg = 12
    case card = 14
    case xl = 18
    case pill = 999

    public var value: Double {
        rawValue
    }

    public var cgFloat: CGFloat {
        CGFloat(rawValue)
    }
}
