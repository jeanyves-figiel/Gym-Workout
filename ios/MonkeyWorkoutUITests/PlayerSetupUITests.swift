import XCTest

/// Player setup strip (#809): a saved machine setup opens again from the player, also when it only keeps the
/// push / lower switch. Demo screen `player-setup`: a machine exercise with Seat 4 · Pad 2 · ROM off and a note.
final class PlayerSetupUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "player-setup"]
        app.launch()
    }

    private var strip: XCUIElement {
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH[c] %@", "My setup")).firstMatch
    }

    private func openSetup(_ step: String) {
        XCTAssertTrue(strip.waitForExistence(timeout: 15), "Setup strip (\(step))")
        strip.tap()
        XCTAssertTrue(app.navigationBars["Machine setup"].waitForExistence(timeout: 5), "Setup sheet opens (\(step))")
    }

    private func closeSetup() {
        app.navigationBars["Machine setup"].buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Machine setup"].waitForNonExistence(timeout: 5), "Setup sheet closed")
    }

    func testSetupOpensAgain() {
        openSetup("first")
        closeSetup()
        openSetup("second")
        closeSetup()
        openSetup("third")
    }

    func testPushLowerOnlySetupOpensAgain() {
        openSetup("first")
        let split = app.switches["setup.splitLoad"].firstMatch
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        if (split.value as? String) != "1" { split.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertEqual(split.value as? String, "1", "Push / lower on")
        for name in ["Seat", "Pad", "ROM"] {
            let remove = app.buttons["Remove \(name)"].firstMatch
            if remove.waitForExistence(timeout: 2) { remove.tap() }
        }
        let note = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.matching(
            NSPredicate(format: "value BEGINSWITH[c] %@", "Pad just")).firstMatch
        if note.waitForExistence(timeout: 2) {
            note.tap()
            note.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        }
        closeSetup()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Push ≠ lower")).firstMatch
            .waitForExistence(timeout: 10), "Strip shows the push / lower setup")
        openSetup("push / lower only")
        closeSetup()
        openSetup("push / lower only, again")
    }
}
