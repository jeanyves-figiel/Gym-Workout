import XCTest

/// In-workout coach (#379): the header pill, the subtitle bubble and the Final set badge show without moving the player;
/// the record burst covers the exercise card and closes on tap. Demo screens `player-coach`, `player-record`.
final class CoachUITests: XCTestCase {
    func testFinalSetBubbleAndPill() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "player-coach"]
        app.launch()
        let pill = app.buttons["player.coach"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "Coach pill in the header")
        XCTAssertTrue(app.descendants(matching: .any)["player.coachBubble"].exists, "Subtitle bubble")
        XCTAssertTrue(app.descendants(matching: .any)["player.finalSet"].exists, "Final set badge")
        let skip = app.buttons["Skip to next exercise"]
        XCTAssertTrue(skip.isHittable, "Controls stay on screen")
        pill.tap()
        XCTAssertTrue(app.buttons["Coach muted. Unmute"].waitForExistence(timeout: 3), "Tap mutes")
    }

    func testRecordBurstCloses() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "player-record"]
        app.launch()
        let burst = app.buttons["player.coachRecord"]
        XCTAssertTrue(burst.waitForExistence(timeout: 15), "Record burst")
        burst.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: burst)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "Tap closes it")
    }
}
