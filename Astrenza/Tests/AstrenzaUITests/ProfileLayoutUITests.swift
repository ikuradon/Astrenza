import XCTest

@MainActor
final class ProfileLayoutUITests: XCTestCase {
    func testExpandedAvatarUsesTheHeroCoordinateSpace() {
        let application = XCUIApplication()
        application.launchArguments = ["-AstrenzaMockTimeline"]
        application.launch()

        let profileTab = application.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 12))
        profileTab.tap()

        let hero = application.buttons["profile.hero"]
        let avatar = application.buttons["Open profile avatar"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))

        XCTAssertEqual(
            avatar.frame.midY,
            hero.frame.maxY,
            accuracy: 1,
            "The expanded avatar must be centered on the hero bottom edge"
        )
    }
}
