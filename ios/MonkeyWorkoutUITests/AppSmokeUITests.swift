import XCTest

/// Smoke run of the main paths in demo mode (`-demo -demoScreen …`, see `Demo.swift` / `DemoScreen` in RootView):
/// every tab opens; Train → Start workout → log a set → Finish → DONE; Explore → muscle → exercise → back;
/// Progress → History; Fuel → a glass of water; Social; Me → Settings; the HIIT builder; the Ask Coach paywall.
/// Demo screen `week` is the full app (tabs) on Train with today's session in Next up.
final class AppSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(_ screen: String) {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", screen]
        app.launch()
    }

    private func button(beginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// The first of `elements` to exist within `timeout` (polls with waitForExistence, no sleeps).
    private func firstToExist(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let e = elements.first(where: { $0.exists }) { return e }
            _ = elements.first?.waitForExistence(timeout: 0.5)
        } while Date() < deadline
        return elements.first(where: { $0.exists })
    }

    /// Swipes up until `element` is hittable (at most `swipes` times).
    @discardableResult
    private func scrollTo(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes where !(element.exists && element.isHittable) { app.swipeUp() }
        return element.exists && element.isHittable
    }

    private func waitUntil(_ format: String, _ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    /// Taps a tab of the tab bar (iPhone) or sidebar (iPad / unfolded Duo).
    private func openTab(_ name: String) {
        let bar = app.tabBars.firstMatch
        let tab = bar.exists ? bar.buttons[name].firstMatch : app.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(name) tab")
        tab.tap()
        if bar.exists {
            XCTAssertTrue(waitUntil("isSelected == true", tab), "\(name) tab selected")
        }
    }

    private func launchTabs() {
        launch("week")
        XCTAssertTrue(app.buttons["me.pill"].firstMatch.waitForExistence(timeout: 20), "Main tabs loaded")
    }

    // MARK: Tabs

    func testEveryTabOpens() {
        launchTabs()
        openTab("Explore")
        XCTAssertTrue(app.staticTexts["Explore"].firstMatch.waitForExistence(timeout: 10), "Explore title")
        openTab("Progress")
        XCTAssertTrue(app.staticTexts["Progress"].firstMatch.waitForExistence(timeout: 10), "Progress title")
        openTab("Fuel")
        XCTAssertTrue(app.staticTexts["Fuel"].firstMatch.waitForExistence(timeout: 10), "Fuel title")
        openTab("Social")
        XCTAssertNotNil(firstToExist([app.buttons["Share a win"], app.navigationBars["Join the community"],
                                      app.staticTexts["Social"]], timeout: 10), "Social opens")
        openTab("Train")
        XCTAssertNotNil(firstToExist([button(containing: "Start workout"), button(containing: "Resume workout"),
                                      app.buttons["me.pill"]], timeout: 10), "Back on Train")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Train → player → finish

    func testStartLogSetAndFinish() {
        launchTabs()
        let start = firstToExist([button(containing: "Start workout"), button(containing: "Resume workout")], timeout: 15)
        XCTAssertNotNil(start, "Start workout on Train")
        start?.tap()

        let menu = app.buttons["Workout menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "Player open")

        // Warm-up and timed items have START instead of SET n DONE: skip to the first loggable set.
        let setDone = button(beginningWith: "SET ")
        let skip = app.buttons["Skip to next exercise"]
        for _ in 0..<15 where !(setDone.exists && setDone.isHittable) {
            guard skip.waitForExistence(timeout: 5), skip.isHittable else { break }
            skip.tap()
            _ = setDone.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(setDone.exists && setDone.isHittable, "A set to log")
        let label = setDone.label
        setDone.tap()

        // Logged: the rest card (SKIP REST / CONTINUE in the controls, +15 s, the "Rest" timer), the next set's button,
        // or NEXT / FINISH after a single-set item.
        let after = firstToExist([
            app.buttons["SKIP REST"], app.buttons["CONTINUE"], app.buttons["Add 15 seconds of rest"],
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Rest")).firstMatch,
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "SET ", label)).firstMatch,
            app.buttons["NEXT"], app.buttons["FINISH"], app.buttons["FINISH WORKOUT"],
        ], timeout: 10)
        XCTAssertNotNil(after, "Set logged")

        // Finish from the workout map (#538).
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(app.staticTexts["What's left"].waitForExistence(timeout: 5), "Workout map")
        let finish = app.buttons["Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "Finish in the map")
        finish.tap()

        let done = app.buttons["DONE"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "Finish summary")
        if !done.isHittable { scrollTo(done) }
        done.tap()
        XCTAssertTrue(app.buttons["me.pill"].firstMatch.waitForExistence(timeout: 10), "Back on Train")
    }

    // MARK: Explore

    func testExploreOpensExerciseAndBack() {
        launchTabs()
        openTab("Explore")
        XCTAssertTrue(app.staticTexts["Explore"].firstMatch.waitForExistence(timeout: 10), "Explore opens")

        // A muscle page (demo screen, so Explore's current mode doesn't matter) → an exercise → close.
        launch("muscle")
        let muscleBar = app.navigationBars["Muscle"]
        XCTAssertTrue(muscleBar.waitForExistence(timeout: 20), "Muscle page")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "MAIN", "ASSIST")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Exercise row")
        XCTAssertTrue(scrollTo(row), "Exercise row on screen")
        row.tap()

        let exerciseBar = app.navigationBars["Exercise"]
        XCTAssertTrue(exerciseBar.waitForExistence(timeout: 10), "Exercise page")
        exerciseBar.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(waitUntil("exists == false", exerciseBar), "Exercise sheet closed")
        XCTAssertTrue(muscleBar.waitForExistence(timeout: 5), "Back on the muscle page")
    }

    // MARK: Progress

    func testProgressOpensHistory() {
        launchTabs()
        openTab("Progress")
        XCTAssertTrue(app.staticTexts["Progress"].firstMatch.waitForExistence(timeout: 10))
        // Either the History tile or the Recent sessions strip's See all (#442).
        let seeAll = button(beginningWith: "See all")
        let tile = button(containing: "History")
        var target: XCUIElement?
        for _ in 0..<8 {
            if seeAll.exists, seeAll.isHittable { target = seeAll; break }
            if tile.exists, tile.isHittable { target = tile; break }
            app.swipeUp()
        }
        guard let target else { return XCTFail("No way into History on Progress") }
        target.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10), "History page")
    }

    // MARK: Fuel

    func testFuelAddsWater() {
        launchTabs()
        openTab("Fuel")
        XCTAssertTrue(app.staticTexts["Fuel"].firstMatch.waitForExistence(timeout: 10))
        // The tank's water square adds a glass per tap (#733).
        let water = app.descendants(matching: .any)["fuel.tank.water"].firstMatch
        XCTAssertTrue(water.waitForExistence(timeout: 10), "Water square")
        let before = water.label
        water.tap()
        let counted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label != %@", "fuel.tank.water", before)).firstMatch
        XCTAssertTrue(counted.waitForExistence(timeout: 5), "Glass counted")
    }

    // MARK: Social

    func testSocialOpens() {
        launchTabs()
        openTab("Social")
        XCTAssertNotNil(firstToExist([app.buttons["Share a win"], app.navigationBars["Join the community"],
                                      app.staticTexts["Social"]], timeout: 15), "Social feed or join page")
    }

    // MARK: Me → Settings

    func testMeSheetOpensSettings() {
        launchTabs()
        let pill = app.buttons["me.pill"].firstMatch
        pill.tap()
        let settings = app.buttons["me.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings row in the Me sheet")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings page")
    }

    // MARK: HIIT

    /// Demo screen `explore-hiit`: Explore on HIIT; a format tile opens the builder.
    func testHiitBuilderOpens() {
        launch("explore-hiit")
        let tabata = app.buttons["hiit.format.tabata"]
        XCTAssertTrue(tabata.waitForExistence(timeout: 20), "Tabata tile")
        XCTAssertTrue(scrollTo(tabata))
        tabata.tap()
        XCTAssertTrue(app.buttons["hiit.doToday"].waitForExistence(timeout: 10), "Builder: Do today")
        XCTAssertTrue(app.buttons["hiit.reshuffle"].exists, "Builder: Reshuffle")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(waitUntil("exists == false", app.buttons["hiit.doToday"]), "Builder closed")
    }

    // MARK: Pro

    /// Demo screen `pro-gate`: the paywall Ask Coach shows when Pro is locked.
    func testAskCoachPaywallSheet() {
        launch("pro-gate")
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 20), "Paywall sheet")
        close.tap()
    }

    /// Ask Coach must hit the paywall only while Pro is locked. Demo mode always unlocks Pro
    /// (`ProStore.loadDemo` gives `access: true`) and has no launch argument to lock it, so this can't run yet.
    func testAskCoachGatedOnlyWhenLocked() throws {
        throw XCTSkip("No demo launch argument locks Pro (ProStore.loadDemo always grants access).")
    }
}
