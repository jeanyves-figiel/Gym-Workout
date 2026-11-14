import XCTest
@testable import WorkoutEngine

/// Invisible Monkey (#1087): confidence ladder, drinks from sips, merging finds.
final class AutoTrackTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: h, minute: m))!
    }

    func testLadder() {
        XCTAssertEqual(AutoTrack.step(0.92), .log)
        XCTAssertEqual(AutoTrack.step(0.85), .log)
        XCTAssertEqual(AutoTrack.step(0.7), .ask)
        XCTAssertEqual(AutoTrack.step(0.59), .drop)
    }

    func testSipsMakeOneDrinkAndGrowMoreSure() {
        let sips = (0..<5).map { AutoTrack.Sip(date: at(10, $0 * 2), confidence: 0.7) }
        let d = AutoTrack.drinks(sips, mlPerSip: 30)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.ml, 150)
        XCTAssertEqual(d.first?.count, 5)
        XCTAssertEqual(d.first?.confidence ?? 0, 0.86, accuracy: 0.001)
        XCTAssertEqual(AutoTrack.step(d.first!.confidence), .log)
    }

    func testDrinksSplitAfterGap() {
        let sips = [AutoTrack.Sip(date: at(9), confidence: 0.9), AutoTrack.Sip(date: at(11), confidence: 0.9)]
        XCTAssertEqual(AutoTrack.drinks(sips, mlPerSip: 30).count, 2)
    }

    func testMergeAppliesLadderAndKeepsAnswers() {
        let sure = AutoTrack.drinks([AutoTrack.Sip(date: at(8), confidence: 0.95)], mlPerSip: 30)
        let weak = AutoTrack.drinks([AutoTrack.Sip(date: at(12), confidence: 0.5)], mlPerSip: 30)
        let meal = AutoTrack.meal(start: at(12, 30), end: at(12, 50), bites: 14, confidence: 0.9)
        var all = AutoTrack.merge([], new: sure + weak + [meal], now: at(20), calendar: cal)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.kind == .water }?.state, .logged)
        // A sure meal still needs to know what was eaten.
        XCTAssertEqual(all.first { $0.kind == .meal }?.state, .pending)
        // The member binned the meal; the Watch reports it again: still binned.
        all = all.map { var e = $0; if e.kind == .meal { e.state = .dismissed }; return e }
        all = AutoTrack.merge(all, new: [meal], now: at(20), calendar: cal)
        XCTAssertEqual(all.first { $0.kind == .meal }?.state, .dismissed)
    }

    func testPhotoReplacesOverlappingWatchMeal() {
        let meal = AutoTrack.meal(start: at(12, 30), end: at(12, 50), bites: 14, confidence: 0.7)
        let photo = AutoTrack.photo(id: "A1", date: at(12, 28), title: "Pasta", confidence: 0.9)
        let all = AutoTrack.merge([], new: [meal, photo], now: at(20), calendar: cal)
        XCTAssertEqual(all.map(\.source), [.photo])
        XCTAssertEqual(all.first?.state, .pending)
        XCTAssertLessThan(all.first?.confidence ?? 1, AutoTrack.sure)
    }

    func testOldFindsDropped() {
        let old = AutoTrack.drinks([AutoTrack.Sip(date: at(8).addingTimeInterval(-20 * 86400), confidence: 0.95)], mlPerSip: 30)
        XCTAssertTrue(AutoTrack.merge([], new: old, now: at(20), calendar: cal).isEmpty)
    }

    func testWorkoutTimeIsNotDrinking() {
        let e = AutoTrack.drinks([AutoTrack.Sip(date: at(18, 20), confidence: 0.95)], mlPerSip: 30)[0]
        XCTAssertFalse(AutoTrack.outside(e, workouts: [DateInterval(start: at(18), end: at(19))]))
        XCTAssertTrue(AutoTrack.outside(e, workouts: [DateInterval(start: at(7), end: at(8))]))
    }

    func testWaterMlAndGlasses() {
        var events = AutoTrack.drinks([AutoTrack.Sip(date: at(8), confidence: 0.95)] + (0..<9).map { AutoTrack.Sip(date: at(14, $0), confidence: 0.95) }, mlPerSip: 30)
        events = AutoTrack.merge([], new: events, now: at(20), calendar: cal)
        XCTAssertEqual(AutoTrack.loggedMl(events, on: at(20), calendar: cal), 300)
        XCTAssertEqual(AutoTrack.glasses(ml: 300, glassMl: 250), 1)
        XCTAssertEqual(AutoTrack.glasses(ml: 249, glassMl: 250), 0)
    }

    func testSummary() {
        XCTAssertEqual(AutoTrack.summary([]), "Nothing caught yet today")
        let logged = AutoEvent(id: "a", kind: .water, source: .sips, start: at(8), end: at(8), confidence: 0.9, state: .logged)
        let ask = AutoEvent(id: "b", kind: .meal, source: .bites, start: at(9), end: at(9), confidence: 0.7, state: .pending)
        XCTAssertEqual(AutoTrack.summary([logged]), "Monkey logged 1 thing today · Undo any")
        XCTAssertEqual(AutoTrack.summary([logged, ask]), "Logged 1 · 1 to check")
    }

    func testGymOncePerDay() {
        XCTAssertEqual(AutoTrack.gym(at: at(7), calendar: cal).id, AutoTrack.gym(at: at(18), calendar: cal).id)
    }
}
