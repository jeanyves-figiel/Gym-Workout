import XCTest

/// Train fits one screen (#337): Start workout is visible above the tab bar without scrolling.
/// Demo screen `week`: the full app on the Train tab with today's session in Next up.
final class TrainFitUITests: XCTestCase {
    func testStartWorkoutVisibleWithoutScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "week"]
        app.launch()
        let start = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Start workout")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15), "Start workout on Train")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(start.frame.maxY, tabBar.frame.minY, "Start workout sits above the tab bar")
        XCTAssertGreaterThan(start.frame.minY, 0, "Start workout on screen")
        XCTAssertTrue(start.isHittable)
    }
}
