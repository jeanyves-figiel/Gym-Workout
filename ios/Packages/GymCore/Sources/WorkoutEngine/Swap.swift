import Foundation

// MARK: - Exercise swaps (#101)

/// A swap kept for future weeks: on that day of the plan, `from` is replaced by `to` whenever the generator picks it.
public struct ExerciseSwap: Codable, Hashable, Sendable {
    /// `Session.weekday` when the plan is laid out on weekdays, else nil.
    public var weekday: Int?
    /// `Session.index`, used when the plan has no weekdays.
    public var sessionIndex: Int
    public var from: String
    public var to: String

    public init(weekday: Int?, sessionIndex: Int, from: String, to: String) {
        self.weekday = weekday
        self.sessionIndex = sessionIndex
        self.from = from
        self.to = to
    }

    /// Same plan day.
    public func matches(_ s: Session) -> Bool {
        if let weekday, let day = s.weekday { return weekday == day }
        return weekday == nil && s.weekday == nil && sessionIndex == s.index
    }

    /// The rule for `from` on the same day as `session`.
    public func sameSlot(_ other: ExerciseSwap) -> Bool {
        weekday == other.weekday && sessionIndex == other.sessionIndex && from == other.from
    }
}

extension WeekPlan {
    /// Kept swaps applied to generated sessions. Targets that no longer resolve (archived custom exercise) are skipped.
    public func applying(swaps: [ExerciseSwap], custom: CustomExercises = .shared) -> WeekPlan {
        guard !swaps.isEmpty else { return self }
        var p = self
        for s in p.sessions.indices where !p.sessions[s].isPlanInsert {
            let rules = swaps.filter { $0.matches(p.sessions[s]) }
            guard !rules.isEmpty else { continue }
            for b in p.sessions[s].blocks.indices {
                for i in p.sessions[s].blocks[b].items.indices {
                    let id = p.sessions[s].blocks[b].items[i].exerciseId
                    if let r = rules.first(where: { $0.from == id }), Exercise.find(r.to, custom: custom) != nil {
                        p.sessions[s].blocks[b].items[i].exerciseId = r.to
                    }
                }
            }
        }
        return p
    }
}

extension Exercise {
    /// Swap suggestions: same role (`alternatives`), best muscle overlap first, then other exercises of the
    /// category hitting the same primary muscles with the member's equipment. Shared by the session swap sheet
    /// and plan variation.
    public func swapOptions(for profile: Profile, excluding: Set<String> = []) -> [Exercise] {
        let mine = Set(primary)
        let overlap: (Exercise) -> Int = { e in
            2 * e.primary.filter { mine.contains($0) }.count + e.secondary.filter { mine.contains($0) }.count
        }
        var seen = excluding.union([id])
        var out: [Exercise] = []
        for e in alternatives(for: profile).sorted(by: { overlap($0) > overlap($1) }) where seen.insert(e.id).inserted {
            out.append(e)
        }
        let more = Selector.candidates(level: profile.experience.level, equipment: Set(profile.equipment), Query(category: category))
            .filter { e in e.primary.contains { mine.contains($0) } }
            .sorted { overlap($0) > overlap($1) }
        for e in more where seen.insert(e.id).inserted { out.append(e) }
        return out
    }
}
