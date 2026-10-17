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

    /// #373: the smart Up next bar above the controls opens the map too, and the card's own buttons never overlap.
    func testUpNextBarOpensMapAndButtonsDontOverlap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "player"]
        app.launch()
        let bar = app.descendants(matching: .any)["player.upNext"]
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "Up next bar")
        XCTAssertTrue(bar.isHittable, "Up next bar on screen")
        let form = app.buttons["Setup and technique"]
        XCTAssertTrue(form.exists, "Form button")
        let change = app.buttons["Change exercise"]
        if change.exists {
            XCTAssertFalse(form.frame.intersects(change.frame), "Form and Change don't overlap")
        }
        XCTAssertFalse(app.staticTexts["Coming up"].exists, "No Coming up strip")
        bar.tap()
        XCTAssertTrue(app.staticTexts["What's left"].waitForExistence(timeout: 5), "Workout map opens from Up next")
    }
}
