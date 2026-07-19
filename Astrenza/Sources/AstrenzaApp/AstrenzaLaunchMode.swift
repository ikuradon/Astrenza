import Foundation

struct AstrenzaLaunchMode {
    let arguments: [String]
    let environment: [String: String]
    private let userDefaults: UserDefaults?

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = .standard
    ) {
        self.arguments = arguments
        self.environment = environment
        self.userDefaults = userDefaults
    }

    var usesMockTimeline: Bool {
        arguments.contains("-AstrenzaMockTimeline")
            || arguments.contains { $0.contains("AstrenzaMockTimeline") }
            || environment["ASTRENZA_MOCK_TIMELINE"] == "1"
            || environment["ASTRENZA_ROUTE"] == "mock"
            || userDefaults?.bool(forKey: "AstrenzaMockTimeline") == true
    }
}

#if DEBUG
enum AstrenzaDebugLaunchRoute: Equatable {
    case timelineSnapshot(AstrenzaDebugTimelineSnapshotCase)
    case timelinePerformance(postCount: Int)
    case settingsNavigation
}

enum AstrenzaDebugTimelineSnapshotCase: String, CaseIterable {
    case singlePortrait = "single-portrait"
    case singleLandscape = "single-landscape"
    case gallery2 = "gallery-2"
    case gallery3 = "gallery-3"
    case gallery4 = "gallery-4"
    case metadataLateArrival = "metadata-late-arrival"
    case ogpLateArrival = "ogp-late-arrival"
}

extension AstrenzaLaunchMode {
    var debugRoute: AstrenzaDebugLaunchRoute? {
        let route = argumentValue(after: "-AstrenzaDebugRoute")
            ?? environment["ASTRENZA_DEBUG_ROUTE"]

        switch route {
        case "timeline-snapshot":
            let rawCase = argumentValue(after: "-AstrenzaSnapshotCase")
                ?? environment["ASTRENZA_SNAPSHOT_CASE"]
            guard let rawCase,
                  let snapshotCase = AstrenzaDebugTimelineSnapshotCase(rawValue: rawCase)
            else { return nil }
            return .timelineSnapshot(snapshotCase)

        case "timeline-performance":
            let rawCount = argumentValue(after: "-AstrenzaPerformancePostCount")
                ?? environment["ASTRENZA_PERFORMANCE_POST_COUNT"]
            let postCount = min(max(Int(rawCount ?? "") ?? 10_000, 1), 100_000)
            return .timelinePerformance(postCount: postCount)

        case "settings-navigation":
            return .settingsNavigation

        default:
            return nil
        }
    }

    private func argumentValue(after flag: String) -> String? {
        guard let flagIndex = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }
}
#endif
