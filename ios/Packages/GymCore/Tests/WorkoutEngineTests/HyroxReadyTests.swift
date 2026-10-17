import Foundation
import Testing
@testable import WorkoutEngine

/// Hyrox ready (#431): one block per race, gaps between races get their own block, targets on signatures.
@Suite struct HyroxReadyTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    private var now: Date { day("2026-10-19") } // Monday

    private func kinds(_ p: Programme) -> [ProgrammePhaseKind] { (1...p.weeks).map { p.phase(week: $0).kind } }

    @Test func noRaceIsTheStandardBlock() {
        let p = Programme.hyroxSeason(races: [], now: now, calendar: cal)
        #expect(p == Programme.find(Programme.hyroxId))
        #expect(p.weeks == 9 && p.isHyrox && p.lifts.isEmpty)
        #expect(p.phases.map(\.kind) == [.base, .build, .peak, .test, .ease])
    }

    @Test func oneRaceFitsTheBlockToRaceWeek() {
        // Race Sat 19 Dec: week 9 (weeks 1–8 before it).
        let p = Programme.hyroxSeason(races: [day("2026-12-19")], now: now, calendar: cal)
        #expect(p.weeks == 9)
        #expect(p.phases.map(\.weeks) == [3, 3, 1, 1, 1])
        // Close race: short Build, sim, race.
        let close = Programme.hyroxSeason(races: [day("2026-11-14")], now: now, calendar: cal)
        #expect(kinds(close) == [.build, .build, .test, .ease])
        // Race next week: one sharpening week.
        #expect(kinds(Programme.hyroxSeason(races: [day("2026-10-31")], now: now, calendar: cal)) == [.peak, .ease])
        // Past races are dropped.
        #expect(Programme.hyroxSeason(races: [day("2026-09-01"), day("2026-12-19")], now: now, calendar: cal).weeks == 9)
    }

    @Test func gapsBetweenRacesGetTheirOwnBlock() {
        let first = day("2026-12-19") // week 9
        // 8 weeks between race weeks → recovery, Build 6, Peak, race.
        let long = Programme.hyroxSeason(races: [first, day("2027-02-20")], now: now, calendar: cal)
        #expect(long.weeks == 9 + 9)
        #expect(long.phases.suffix(4).map(\.kind) == [.ease, .build, .peak, .ease])
        #expect(long.phases.suffix(4).map(\.weeks) == [1, 6, 1, 1])
        // 4 weeks gap → recovery, Build 3, race.
        let mid = Programme.hyroxSeason(races: [first, day("2027-01-23")], now: now, calendar: cal)
        #expect(mid.phases.suffix(3).map(\.kind) == [.ease, .build, .ease] && mid.phases.suffix(3).map(\.weeks) == [1, 3, 1])
        // 2 weeks gap → recovery, sharpen, race; back-to-back weeks → just the race.
        let short = Programme.hyroxSeason(races: [first, day("2027-01-09")], now: now, calendar: cal)
        #expect(short.phases.suffix(3).map(\.kind) == [.ease, .peak, .ease])
        let back = Programme.hyroxSeason(races: [first, day("2026-12-26")], now: now, calendar: cal)
        #expect(back.weeks == 10 && back.phases.last?.kind == .ease)
        // Unsorted and duplicate days give the same season.
        #expect(Programme.hyroxSeason(races: [day("2027-02-20"), first, first], now: now, calendar: cal) == long)
    }

    @Test func seasonPinsSignaturesAndCarriesTargets() {
        let p = Programme.hyroxSeason(races: [day("2026-12-19")], now: now, calendar: cal)
            .targeting { $0 == "treadmill-run" ? "Race pace 4:55 /km" : nil }
        let member = Profile(goal: .balanced, sessionsPerWeek: 4, experience: .intermediate)
        let plan = p.previewWeek(1, member: member, seed: 1, starting: true)
        let pinned = plan.sessions.filter(\.isPlanInsert)
        #expect(pinned.count >= 2)
        let run = pinned.flatMap(\.blocks).flatMap(\.items).first { $0.exerciseId == "treadmill-run" }
        #expect(run == nil || run?.prescription.intensity == "Race pace 4:55 /km")
        // Race and recovery weeks pin nothing.
        #expect(!p.previewWeek(9, member: member, seed: 1, starting: true).sessions.contains(where: \.isPlanInsert))
    }

    @Test func racesAreKeptOnTheRunningProgramme() throws {
        let saved = ActiveProgramme.SavedPlan(profile: Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate), seed: 1, week: 1)
        let season = Programme.hyroxSeason(races: [day("2026-12-19"), day("2027-02-20")], now: now, calendar: cal)
        var a = ActiveProgramme(programmeId: season.id, start: now, seed: 2, saved: saved, custom: season)
        a.races = [day("2026-12-19"), day("2027-02-20")]
        let back = try JSONDecoder().decode(ActiveProgramme.self, from: JSONEncoder().encode(a))
        #expect(back.races == a.races && back.programme?.weeks == 18)
        #expect(!back.finished(on: day("2027-02-20"), calendar: cal))
        #expect(back.finished(on: day("2027-02-23"), calendar: cal))
    }
}
