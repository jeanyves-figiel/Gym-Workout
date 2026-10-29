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

    /// #903: a custom gym session discarded from the map is gone once its Undo bar is: Train offers a new one, not Resume.
    func testDiscardedCustomSessionIsNotResumable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "week"]
        app.launch()
        let tile = app.buttons["train.freestyle"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "Custom gym session tile")
        for _ in 0..<6 where !tile.isHittable { app.swipeUp() }
        tile.tap()
        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start ")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "A pick to start")
        start.tap()
        let menu = app.buttons["Workout menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Player with workout menu")
        XCTAssertTrue(waitEnabled(menu), "Menu enabled once an exercise is in")
        menu.tap()
        let discard = app.buttons["Discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Discard on the map")
        discard.tap()
        XCTAssertTrue(app.staticTexts["Workout discarded"].firstMatch.waitForExistence(timeout: 5), "Undo bar")
        // Undo bar (5 s) and the discard behind it run out.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.staticTexts["Workout discarded"].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Undo bar gone")
        sleep(2)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Tile back on Train")
        XCTAssertFalse(tile.label.contains("Resume"), "Nothing to resume: \(tile.label)")
    }

    private func waitEnabled(_ e: XCUIElement) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: e)
        return XCTWaiter().wait(for: [exp], timeout: 5) == .completed
    }
}
