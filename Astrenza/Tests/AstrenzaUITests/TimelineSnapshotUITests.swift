import XCTest

@MainActor
final class TimelineSnapshotUITests: XCTestCase {
    private var application: XCUIApplication?

    override func tearDown() async throws {
        application?.terminate()
        application = nil
        try await super.tearDown()
    }

    func testSinglePortrait() async throws {
        try await assertStaticSnapshot(
            snapshotCase: "single-portrait",
            name: "single_portrait-iPhone17-iOS26_5-dark-large@3x"
        )
    }

    func testSingleLandscape() async throws {
        try await assertStaticSnapshot(
            snapshotCase: "single-landscape",
            name: "single_landscape-iPhone17-iOS26_5-dark-large@3x"
        )
    }

    func testGallery2() async throws {
        try await assertStaticSnapshot(
            snapshotCase: "gallery-2",
            name: "gallery_2-iPhone17-iOS26_5-dark-large@3x"
        )
    }

    func testGallery3() async throws {
        try await assertStaticSnapshot(
            snapshotCase: "gallery-3",
            name: "gallery_3-iPhone17-iOS26_5-dark-large@3x"
        )
    }

    func testGallery4() async throws {
        try await assertStaticSnapshot(
            snapshotCase: "gallery-4",
            name: "gallery_4-iPhone17-iOS26_5-dark-large@3x"
        )
    }

    func testMetadataLateArrival() async throws {
        try await assertLateArrivalSnapshots(
            snapshotCase: "metadata-late-arrival",
            pendingName: "metadata_pending-iPhone17-iOS26_5-dark-large@3x",
            resolvedName: "metadata_resolved-iPhone17-iOS26_5-dark-large@3x"
        )
    }

    func testOGPLateArrival() async throws {
        try await assertLateArrivalSnapshots(
            snapshotCase: "ogp-late-arrival",
            pendingName: "ogp_pending-iPhone17-iOS26_5-dark-large@3x",
            resolvedName: "ogp_resolved-iPhone17-iOS26_5-dark-large@3x"
        )
    }

    private func assertStaticSnapshot(snapshotCase: String, name: String) async throws {
        let launched = try launchTimelineSnapshotApp(snapshotCase: snapshotCase)
        application = launched.0
        let image = try await stableTimelineScreenshot(of: launched.1)
        try assertTimelineUISnapshot(image, named: name)
    }

    private func assertLateArrivalSnapshots(
        snapshotCase: String,
        pendingName: String,
        resolvedName: String
    ) async throws {
        let launched = try launchTimelineSnapshotApp(snapshotCase: snapshotCase)
        let app = launched.0
        application = app

        let pendingImage = try await stableTimelineScreenshot(of: launched.1)
        try assertTimelineUISnapshot(pendingImage, named: pendingName)

        let resolveButton = app.buttons[TimelineUISnapshotConfiguration.resolveIdentifier]
        XCTAssertTrue(resolveButton.waitForExistence(timeout: 3))
        resolveButton.tap()

        let resolvedButton = app.buttons[TimelineUISnapshotConfiguration.resolvedIdentifier]
        XCTAssertTrue(resolvedButton.waitForExistence(timeout: 3))
        let resolvedCapture = app
            .descendants(matching: .any)[TimelineUISnapshotConfiguration.captureIdentifier]
        XCTAssertTrue(resolvedCapture.waitForExistence(timeout: 3))
        let resolvedImage = try await stableTimelineScreenshot(of: resolvedCapture)

        try assertTimelineUISnapshotsVisiblyDiffer(pendingImage, resolvedImage)
        try assertTimelineUISnapshot(resolvedImage, named: resolvedName)
    }
}
