public enum AnySendableJSON: Equatable, Sendable {
    case int(Int)
    case string(String)
    case strings([String])
    case ints([Int])

    public var jsonValue: Any {
        switch self {
        case .int(let value):
            value
        case .string(let value):
            value
        case .strings(let value):
            value
        case .ints(let value):
            value
        }
    }
    public var stringArrayValue: [String] {
        switch self {
        case .string(let value):
            [value]
        case .strings(let values):
            values
        case .int, .ints:
            []
        }
    }

    public var intArrayValue: [Int] {
        switch self {
        case .int(let value):
            [value]
        case .ints(let values):
            values
        case .string, .strings:
            []
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let value):
            value
        case .string(let value):
            Int(value)
        case .ints, .strings:
            nil
        }
    }
}
