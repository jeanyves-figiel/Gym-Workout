import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct FinishEarlyTests {
    private let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)

    private var session: Session { Generator.generateWeek(profile, seed: 42).sessions[0] }

    private func items(_ blocks: [Block], _ kind: BlockKind) -> [PlannedExercise] { blocks.first { $0.kind == kind }?.items ?? [] }

    /// Member on the main lift with the warm-up behind them.
    private func onMainLift(_ s: Session) throws -> (current: String, done: [String: Int]) {
        let main = try #require(items(s.blocks, .strength).first)
        return (main.uid, [:])
    }

    @Test func enoughTimeChangesNothing() throws {
        let s = session
        let (current, done) = try onMainLift(s)
        let fit = FinishEarly.fit(s.blocks, setsDone: done, current: current, minutes: 600)
        #expect(!fit.changed && fit.fits)
        #expect(fit.blocks == s.blocks)
        #expect(fit.leftSec == fit.beforeSec)
    }

    @Test func itemsBehindTheMemberCountAsDone() throws {
        let s = session
        let (current, _) = try onMainLift(s)
        let behind = FinishEarly.behind(s.blocks, setsDone: [:], current: current)
        for it in items(s.blocks, .warmup) { #expect(behind[it.uid] == max(1, it.prescription.sets)) }
        #expect(behind[current] == nil)
        let fit = FinishEarly.fit(s.blocks, setsDone: [:], current: current, minutes: 600)
        #expect(!fit.lines.contains { $0.kind == .warmup })
    }

    @Test func shortTimeKeepsMainLiftAndCooldown() throws {
        let s = session
        let (current, done) = try onMainLift(s)
        let fit = FinishEarly.fit(s.blocks, setsDone: done, current: current, minutes: 15)
        #expect(fit.changed)
        #expect(fit.leftSec < fit.beforeSec)
        #expect(fit.blocks.flatMap(\.items).contains { $0.uid == current })
        let cool = items(fit.blocks, .cooldown)
        #expect(!cool.isEmpty)
        let coolBefore = FinishEarly.remainingSec([s.blocks.first { $0.kind == .cooldown }!], setsDone: [:])
        #expect(FinishEarly.remainingSec([fit.blocks.first { $0.kind == .cooldown }!], setsDone: [:])
            >= min(coolBefore, FinishEarly.minCooldownSec))
        // Done items stay exactly as they were.
        for it in items(s.blocks, .warmup) { #expect(fit.blocks.flatMap(\.items).contains(it)) }
        // Lower-priority work goes before the main lift loses anything.
        if fit.fits, let main = fit.lines.first(where: { $0.uid == current }) {
            #expect(main.change == .kept || fit.lines.filter { $0.kind == .strength && $0.uid != current }.allSatisfy { $0.change == .skipped })
        }
    }

    @Test func doneSetsAreNeverCut() throws {
        let s = session
        let main = try #require(items(s.blocks, .strength).first)
        let done = main.prescription.sets - 1
        let fit = FinishEarly.fit(s.blocks, setsDone: [main.uid: done], current: main.uid, minutes: 1)
        let after = try #require(fit.blocks.flatMap(\.items).first { $0.uid == main.uid })
        #expect(after.prescription.sets >= max(1, done))
        #expect(!items(fit.blocks, .cooldown).isEmpty)
    }

    @Test func wrapUpLeavesCurrentAndCooldown() throws {
        let s = session
        let (current, done) = try onMainLift(s)
        let fit = FinishEarly.fit(s.blocks, setsDone: done, current: current, minutes: 0)
        let kinds = Set(fit.blocks.filter { !$0.items.isEmpty }.map(\.kind))
        #expect(kinds.contains(.cooldown))
        #expect(!kinds.contains(.mobility) && !kinds.contains(.cardio))
        let strength = items(fit.blocks, .strength).filter { $0.supersetWith == nil }
        #expect(strength.allSatisfy { $0.uid == current || ($0.group != nil && $0.group == strength.first?.group) })
        #expect(fit.skipped > 0)
    }

    @Test func groupMembersChangeTogether() throws {
        var blocks = session.blocks
        let b = try #require(blocks.firstIndex { $0.kind == .strength })
        try #require(blocks[b].items.filter { $0.supersetWith == nil }.count >= 3)
        let free = blocks[b].items.indices.filter { blocks[b].items[$0].supersetWith == nil }
        let a1 = free[free.count - 2], a2 = free[free.count - 1]
        blocks[b].items[a1].group = "A1"
        blocks[b].items[a2].group = "A2"
        blocks[b].items[a2].prescription.sets = blocks[b].items[a1].prescription.sets
        let main = blocks[b].items[free[0]].uid
        let uidA1 = blocks[b].items[a1].uid, uidA2 = blocks[b].items[a2].uid
        for m in [10, 15, 20, 25] {
            let fit = FinishEarly.fit(blocks, setsDone: [:], current: main, minutes: m)
            let all = fit.blocks.flatMap(\.items)
            let x = all.first { $0.uid == uidA1 }, y = all.first { $0.uid == uidA2 }
            #expect((x == nil) == (y == nil))
            if let x, let y { #expect(x.prescription.sets == y.prescription.sets) }
        }
    }

    @Test func fitSessionKeepsIdAndUpdatesEstimate() throws {
        let s = session
        let (current, done) = try onMainLift(s)
        let fit = FinishEarly.fit(s.blocks, setsDone: done, current: current, minutes: 12)
        let out = FinishEarly.session(s, fit)
        #expect(out.id == s.id && out.blocks == fit.blocks)
        #expect(out.estMin <= s.estMin)
    }
}
