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

    func testTenThousandPostBidirectionalScrollingFlow() async throws {
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
            let launchStartedAt = ProcessInfo.processInfo.systemUptime
            application.launch()
            XCTAssertLessThan(
                ProcessInfo.processInfo.systemUptime - launchStartedAt,
                15,
                "10,000-row geometry projection must not block launch"
            )
        }

        let feed = application.collectionViews["timeline.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 12))

        if let rawDelay = environmentValue(for: "ASTRENZA_PERFORMANCE_CAPTURE_DELAY_MS"),
           let delayMilliseconds = Int(rawDelay),
           delayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(delayMilliseconds))
        }

        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 1
        measure(
            metrics: [
                XCTClockMetric(),
                XCTOSSignpostMetric.scrollingAndDecelerationMetric,
            ],
            options: measureOptions
        ) {
            for _ in 0..<12 {
                feed.swipeUp(velocity: .fast)
            }
            for _ in 0..<12 {
                feed.swipeDown(velocity: .fast)
            }
        }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(application.state, .runningForeground)
    }

    func testHorizontalRowSwipeKeepsVerticalFeedScrollingEnabled() async throws {
        guard environmentValue(for: "ASTRENZA_RUN_PERFORMANCE_UI") == "1" else {
            return
        }

        let application = XCUIApplication()
        self.application = application
        application.launchArguments = [
            "-AstrenzaDebugRoute", "timeline-performance",
            "-AstrenzaPerformancePostCount", "100"
        ]
        application.launch()

        let feed = application.collectionViews["timeline.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 12))
        let firstBody = application.staticTexts["timeline.body.performance-0"]
        XCTAssertTrue(firstBody.waitForExistence(timeout: 5))

        let initialY = firstBody.frame.minY
        let rowY = min(
            max((firstBody.frame.midY - feed.frame.minY) / feed.frame.height, 0.1),
            0.9
        )
        let swipeStart = feed.coordinate(
            withNormalizedOffset: CGVector(dx: 0.72, dy: rowY)
        )
        let swipeEnd = feed.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: rowY)
        )
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)
        let openedPost = application.staticTexts[
            "astrenza.debug.timeline.performance.last-opened-post"
        ]
        XCTAssertTrue(
            openedPost.waitForExistence(timeout: 2),
            "The horizontal row gesture must still resolve its configured action"
        )
        XCTAssertEqual(openedPost.label, "performance-0")

        feed.swipeUp(velocity: .fast)

        let deadline = Date().addingTimeInterval(3)
        while firstBody.exists,
              abs(firstBody.frame.minY - initialY) < 40,
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(
            !firstBody.exists || abs(firstBody.frame.minY - initialY) >= 40,
            "A completed horizontal row swipe must not leave vertical feed scrolling disabled"
        )
    }
}
