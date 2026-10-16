import XCTest

/// Landscape workout player (#362): on its side the player switches to the cockpit layout with everything on screen;
/// the rest of the app stays upright.
final class LandscapePlayerUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testPlayerTurnsToCockpit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "player-logged"]
        app.launch()
        let done = app.buttons.containing(NSPredicate(format: "label BEGINSWITH[c] %@", "SET ")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), "Set button upright")

        XCUIDevice.shared.orientation = .landscapeLeft
        let cockpit = app.descendants(matching: .any)["player.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 5), "Cockpit layout in landscape")
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height, "Player turned")
        XCTAssertTrue(done.isHittable, "Set button on screen")
        XCTAssertLessThanOrEqual(done.frame.maxY, window.frame.maxY)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(cockpit.exists, "Back to the upright layout")
    }

    func testRestOfAppStaysUpright() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "week"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.height, window.frame.width, "Train stays upright")
    }
}
