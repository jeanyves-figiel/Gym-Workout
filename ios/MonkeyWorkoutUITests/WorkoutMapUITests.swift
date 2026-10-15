import XCTest

/// What's left without leaving the player (#361): the progress dots open the read-only Workout map, and closing it
/// returns to the player with its controls still on screen. Demo screen `player`: the second session's player.
final class WorkoutMapUITests: XCTestCase {
    func testDotsOpenWorkoutMap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "player"]
        app.launch()
        let dots = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Open workout map")).firstMatch
        XCTAssertTrue(dots.waitForExistence(timeout: 15), "Progress dots are a button")
        dots.tap()
        XCTAssertTrue(app.staticTexts["What's left"].waitForExistence(timeout: 5), "Workout map opens")
        app.buttons["Close"].firstMatch.tap()
        let skip = app.buttons["Skip to next exercise"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(skip.isHittable, "Player controls stay on screen")
    }
}
