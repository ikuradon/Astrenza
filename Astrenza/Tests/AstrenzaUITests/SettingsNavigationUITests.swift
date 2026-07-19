import XCTest

@MainActor
final class SettingsNavigationUITests: XCTestCase {
    func testAccountProfileNavigationRemainsResponsive() {
        let application = XCUIApplication()
        application.launchArguments = [
            "-AstrenzaDebugRoute", "settings-navigation"
        ]
        application.launch()

        let account = application.buttons[
            "settings.account.\(String(repeating: "a", count: 64))"
        ]
        XCTAssertTrue(account.waitForExistence(timeout: 12))
        account.tap()

        let profile = application.buttons["settings.account.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()

        XCTAssertTrue(
            application.navigationBars["Profile"].waitForExistence(timeout: 5),
            "Profile navigation must not construct or synchronously load sibling destinations"
        )
        XCTAssertTrue(application.staticTexts["Mock screen"].exists)
    }
}
