import XCTest

/// Settings → Your gym (#271): items added to the gym list stay after REBUILD PLAN (was SAVE, #539), by ADD ALL or the Equipment page.
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
        // Settings opens from the Me pill on every tab (#560); after REBUILD PLAN or back the sheet is still open.
        if !app.navigationBars["Settings"].exists {
            let pill = app.buttons["me.pill"].firstMatch
            XCTAssertTrue(pill.waitForExistence(timeout: 10), "Me pill")
            pill.tap()
            let settings = app.buttons["me.settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings row")
            settings.tap()
        }
        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Fitnesspark")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Your gym card")
        card.tap()
        XCTAssertTrue(app.buttons["REBUILD PLAN"].waitForExistence(timeout: 10), "Your gym page")
    }

    private func count(_ n: Int) -> XCUIElement { app.staticTexts["\(n) items"] }

    private func save() {
        app.buttons["REBUILD PLAN"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    func testAddAllSticksAfterSave() {
        openYourGym()
        XCTAssertTrue(count(48).waitForExistence(timeout: 5))
        app.buttons["ADD ALL"].tap()
        XCTAssertTrue(count(68).waitForExistence(timeout: 5), "ADD ALL shows the full list")
        // The Equipment page opened and closed keeps the edit.
        app.staticTexts["Equipment"].tap()
        // The Equipment sheet closes with its X (#539).
        let close = app.navigationBars["Equipment"].buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(count(68).waitForExistence(timeout: 5), "still 68 after the Equipment page")
        save()
        openYourGym()
        XCTAssertTrue(count(68).waitForExistence(timeout: 5), "saved list reopened")
        XCTAssertFalse(app.buttons["ADD ALL"].exists)
    }

    /// The member's path on build 32: Equipment page → close → back, no REBUILD PLAN.
    func testEquipmentPageAdditionSticksWithoutSave() {
        openYourGym()
        XCTAssertTrue(count(48).waitForExistence(timeout: 5))
        app.staticTexts["Equipment"].tap()
        let close = app.navigationBars["Equipment"].buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        // Scroll to the tile (search would hide the X while it's active).
        let ghd = app.buttons["Glute-ham developer (GHD)"].firstMatch
        for _ in 0..<15 where !(ghd.exists && ghd.isHittable) { app.swipeUp() }
        XCTAssertTrue(ghd.isHittable)
        ghd.tap()
        close.tap()
        XCTAssertTrue(count(49).waitForExistence(timeout: 5), "item added on the Equipment page")
        sleep(2)
        XCTAssertTrue(count(49).exists, "count stays after closing")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        openYourGym()
        XCTAssertTrue(count(49).waitForExistence(timeout: 5), "saved list reopened")
    }
}
