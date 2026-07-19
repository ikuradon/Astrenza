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

    func testActionButtonsUseSystemMenusWithoutLockingFeedScrolling() async throws {
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
        let openedPost = application.staticTexts[
            "astrenza.debug.timeline.performance.last-opened-post"
        ]

        let repost = application.descendants(matching: .any)[
            "timeline.action.repost.performance-0"
        ]
        XCTAssertTrue(repost.waitForExistence(timeout: 5))
        repost.press(forDuration: 0.8)

        let quotedRepost = application.buttons["Quoted Repost"]
        XCTAssertTrue(
            quotedRepost.waitForExistence(timeout: 3),
            "Long-pressing Repost must present the UIKit context menu"
        )
        XCTAssertFalse(
            openedPost.exists,
            "Opening an action context menu must not open post detail"
        )
        quotedRepost.tap()

        let more = application.descendants(matching: .any)[
            "timeline.action.more.performance-0"
        ]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        let viewDetails = application.buttons["View Details"]
        XCTAssertTrue(
            viewDetails.waitForExistence(timeout: 3),
            "Tapping More must present the same UIKit menu as its primary action"
        )
        viewDetails.tap()
        XCTAssertTrue(openedPost.waitForExistence(timeout: 2))
        XCTAssertEqual(
            openedPost.label,
            "performance-0",
            "View Details must commit the selected post"
        )

        feed.swipeUp(velocity: .fast)
        let deadline = Date().addingTimeInterval(3)
        while firstBody.exists,
              abs(firstBody.frame.minY - initialY) < 40,
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(
            !firstBody.exists || abs(firstBody.frame.minY - initialY) >= 40,
            "Dismissing a system action menu must leave vertical scrolling enabled"
        )
    }

    func testRowBackgroundOpensPostWithoutLeakingFromExplicitControls() async throws {
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
        let openedPost = application.staticTexts[
            "astrenza.debug.timeline.performance.last-opened-post"
        ]

        let avatar = application.descendants(matching: .any)[
            "timeline.avatar.performance-0"
        ]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        avatar.tap()
        let openedProfile = application.staticTexts[
            "astrenza.debug.timeline.performance.last-opened-profile"
        ]
        XCTAssertTrue(openedProfile.waitForExistence(timeout: 2))
        XCTAssertFalse(
            openedPost.exists,
            "The avatar must keep its profile-specific action"
        )

        let linkedProfile = application.descendants(matching: .any)[
            "timeline.body.performance-1"
        ]
        XCTAssertTrue(linkedProfile.waitForExistence(timeout: 5))
        linkedProfile.tap()
        let linkedProfilePubkey = String(repeating: "b", count: 64)
        let profileDeadline = Date().addingTimeInterval(2)
        while openedProfile.label != linkedProfilePubkey,
              Date() < profileDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            openedProfile.label,
            linkedProfilePubkey,
            "An npub link must keep its profile-specific action"
        )
        XCTAssertFalse(
            openedPost.exists,
            "An npub link must not leak into the row detail action"
        )

        let attachment = application.descendants(matching: .any)[
            "timeline.attachment"
        ]
        XCTAssertTrue(attachment.waitForExistence(timeout: 5))
        attachment.tap()
        XCTAssertTrue(
            application.staticTexts[
                "astrenza.debug.timeline.performance.opened-media"
            ].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(
            openedPost.exists,
            "An attachment must not leak into the row detail action"
        )

        let reply = application.descendants(matching: .any)[
            "timeline.action.reply.performance-0"
        ]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(
            openedPost.exists,
            "A post action must not leak into the row detail action"
        )

        let rowY = min(
            max((firstBody.frame.midY - feed.frame.minY) / feed.frame.height, 0.1),
            0.9
        )
        feed.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: rowY)
        ).tap()

        XCTAssertTrue(
            openedPost.waitForExistence(timeout: 2),
            "The non-interactive row gutter must open post detail"
        )
        XCTAssertEqual(openedPost.label, "performance-0")

        let openPostCount = application.staticTexts[
            "astrenza.debug.timeline.performance.open-post-count"
        ]
        XCTAssertEqual(openPostCount.label, "1")
        firstBody.tap()
        let bodyTapDeadline = Date().addingTimeInterval(2)
        while openPostCount.label != "2",
              Date() < bodyTapDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            openPostCount.label,
            "2",
            "A body tap must issue exactly one post-detail action"
        )
    }
}
