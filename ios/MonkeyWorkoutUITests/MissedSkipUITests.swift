import XCTest

/// Skip on a missed workout (#340) takes it off the catch-up sheet; before, the tap changed nothing visible.
/// Demo screen `missed-catchup`: the catch-up sheet of the week's first missed day.
final class MissedSkipUITests: XCTestCase {
    func testSkipRemovesMissedWorkout() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "missed-catchup"]
        app.launch()
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Skip ")).firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "Skip on the catch-up sheet")
        let label = skip.label
        skip.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons[label])
        waitForExpectations(timeout: 5)
    }
}
