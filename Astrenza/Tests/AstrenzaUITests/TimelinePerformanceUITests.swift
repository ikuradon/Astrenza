import XCTest

@MainActor
final class TimelinePerformanceUITests: XCTestCase {
    private var application: XCUIApplication?

    private func environmentValue(for key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_\(key)"]
    }

    override func tearDown() async throws {
        if environmentValue(for: "ASTRENZA_PERFORMANCE_ATTACH") != "1" {
            application?.terminate()
        }
        application = nil
        try await super.tearDown()
    }

    func testTenThousandPostScrollingFlow() async throws {
        guard environmentValue(for: "ASTRENZA_RUN_PERFORMANCE_UI") == "1" else {
            return
        }

        let application = XCUIApplication()
        self.application = application
        if environmentValue(for: "ASTRENZA_PERFORMANCE_ATTACH") == "1" {
            application.activate()
        } else {
            application.launchArguments = [
                "-AstrenzaDebugRoute", "timeline-performance",
                "-AstrenzaPerformancePostCount", "10000"
            ]
            application.launch()
        }

        let feed = application.collectionViews["timeline.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 12))

        if let rawDelay = environmentValue(for: "ASTRENZA_PERFORMANCE_CAPTURE_DELAY_MS"),
           let delayMilliseconds = Int(rawDelay),
           delayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(delayMilliseconds))
        }

        for _ in 0..<24 {
            feed.swipeUp(velocity: .fast)
        }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(application.state, .runningForeground)
    }
}
