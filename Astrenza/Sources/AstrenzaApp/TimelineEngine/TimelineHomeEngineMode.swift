import Foundation

enum AstrenzaTimelineEngineMode: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView
}

struct TimelineHomeEngineModeIssue: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case unknownTimelineEngineMode
    }

    var kind: Kind
    var argument: String?
    var rawValue: String?
}

struct TimelineHomeEngineModeResolution: Codable, Equatable, Sendable {
    var mode: AstrenzaTimelineEngineMode
    var issues: [TimelineHomeEngineModeIssue]
}

enum TimelineHomeEngineModeResolver {
    private static let argumentPrefix = "--timeline-engine="

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> TimelineHomeEngineModeResolution {
        guard let argument = arguments.last(where: { $0.hasPrefix(argumentPrefix) }) else {
            return TimelineHomeEngineModeResolution(mode: .legacy, issues: [])
        }

        let rawValue = String(argument.dropFirst(argumentPrefix.count))
        guard let mode = AstrenzaTimelineEngineMode(rawValue: rawValue) else {
            return TimelineHomeEngineModeResolution(
                mode: .legacy,
                issues: [
                    TimelineHomeEngineModeIssue(
                        kind: .unknownTimelineEngineMode,
                        argument: argument,
                        rawValue: rawValue
                    )
                ]
            )
        }

        return TimelineHomeEngineModeResolution(mode: mode, issues: [])
    }
}
