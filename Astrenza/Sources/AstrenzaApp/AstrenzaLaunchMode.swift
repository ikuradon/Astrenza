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
