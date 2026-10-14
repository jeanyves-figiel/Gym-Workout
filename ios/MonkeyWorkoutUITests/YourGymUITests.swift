import XCTest

/// Account → Your gym (#271): items added to the gym list stay after SAVE, by ADD ALL or the Equipment page.
/// Demo screen `gym-missing`: Fitnesspark Puls 5 with 48 of its items, the full app (tabs) around it.
final class YourGymUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "gym-missing"]
        app.launch()
    }

    private func openYourGym() {
        let tab = app.tabBars.buttons["Account"]
        if tab.waitForExistence(timeout: 10) { tab.tap() } else { app.buttons["Account"].firstMatch.tap() }
        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Fitnesspark")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Your gym card")
        card.tap()
        XCTAssertTrue(app.buttons["SAVE"].waitForExistence(timeout: 10), "Your gym page")
    }

    private func count(_ n: Int) -> XCUIElement { app.staticTexts["\(n) items"] }

    private func save() {
        app.buttons["SAVE"].tap()
        XCTAssertTrue(app.tabBars.buttons["Account"].waitForExistence(timeout: 10))
    }

    func testAddAllSticksAfterSave() {
        openYourGym()
        XCTAssertTrue(count(48).waitForExistence(timeout: 5))
        app.buttons["ADD ALL"].tap()
        XCTAssertTrue(count(68).waitForExistence(timeout: 5), "ADD ALL shows the full list")
        // The Equipment page opened and closed keeps the edit.
        app.staticTexts["Equipment"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(count(68).waitForExistence(timeout: 5), "still 68 after the Equipment page")
        save()
        openYourGym()
        XCTAssertTrue(count(68).waitForExistence(timeout: 5), "saved list reopened")
        XCTAssertFalse(app.buttons["ADD ALL"].exists)
    }

    /// The member's path on build 32: Equipment page → Done → back, no SAVE.
    func testEquipmentPageAdditionSticksWithoutSave() {
        openYourGym()
        XCTAssertTrue(count(48).waitForExistence(timeout: 5))
        app.staticTexts["Equipment"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("glute ham")
        let ghd = app.buttons["Glute-ham developer (GHD)"].firstMatch
        XCTAssertTrue(ghd.waitForExistence(timeout: 5))
        ghd.tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(count(49).waitForExistence(timeout: 5), "item added on the Equipment page")
        sleep(2)
        XCTAssertTrue(count(49).exists, "count stays after Done")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["Account"].waitForExistence(timeout: 10))
        openYourGym()
        XCTAssertTrue(count(49).waitForExistence(timeout: 5), "saved list reopened")
    }
}
