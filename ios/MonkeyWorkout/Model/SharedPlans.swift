import APIClient
import CryptoKit
import Foundation
import WorkoutEngine

/// A member-made programme shared in Community → Plans (#666).
typealias MemberPlan = SharedPlan<Programme>

/// Community → Plans (#666): programmes other members shared, your own shared ones, and copying one into My programmes.
@MainActor @Observable
final class SharedPlans {
    static let shared = SharedPlans()

    private(set) var plans: [MemberPlan] = []
    private(set) var mine: [MemberPlan] = []
    private(set) var loaded = false
    private(set) var loading = false
    var error: String?
    private var demo = false

    func load(api: APIClient, level: SharedPlanLevel? = nil) async {
        guard !demo, Community.shared.profile != nil else { return }
        loading = true
        defer { loading = false }
        do {
            async let others = api.sharedPlans(Programme.self, level: level)
            async let own = api.sharedPlans(Programme.self, mine: true)
            (plans, mine) = try await (others, own)
            loaded = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Shares `programme` (one of My programmes), or updates the plan it was shared as.
    func share(_ programme: Programme, level: SharedPlanLevel, about: String?, visibility: CommunityVisibility, api: APIClient) async throws {
        let draft = SharedPlanDraft(name: programme.name, about: about, level: level, goal: programme.goal.rawValue, weeks: programme.weeks,
                                    sessionsPerWeek: programme.sessionsPerWeek, programme: programme, visibility: visibility)
        if demo {
            let author = CommunityAuthor(userId: "demo", nickname: Community.shared.profile?.nickname ?? "me")
            upsertMine(MemberPlan(id: Self.planId(programme), name: draft.name, about: about, level: level, goal: draft.goal, weeks: draft.weeks,
                                  sessionsPerWeek: draft.sessionsPerWeek, programme: programme, author: author, mine: true, visibility: visibility))
            return
        }
        upsertMine(try await api.saveSharedPlan(id: Self.planId(programme), draft))
    }

    /// The shared plan of one of My programmes, if shared.
    func sharedPlan(of programme: Programme) -> MemberPlan? { mine.first { $0.id == Self.planId(programme) } }

    func unshare(_ plan: MemberPlan, api: APIClient) async {
        mine.removeAll { $0.id == plan.id }
        guard !demo else { return }
        do { try await api.deleteSharedPlan(plan.id) } catch { self.error = error.localizedDescription }
    }

    /// Saves a copy into My programmes (new id, same name) and counts it for the author. Returns the copy to open.
    func copy(_ plan: MemberPlan, model: AppModel) async -> Programme {
        let copy = plan.programme.copy(name: plan.name)
        model.saveProgramme(copy)
        if let i = plans.firstIndex(where: { $0.id == plan.id }), !plans[i].copiedByMe {
            plans[i].copiedByMe = true
            plans[i].copies += 1
        }
        guard !demo else { return copy }
        do {
            let counted = try await model.api.countSharedPlanCopy(plan.id, as: Programme.self)
            if let i = plans.firstIndex(where: { $0.id == plan.id }) { plans[i] = counted }
        } catch {}
        return copy
    }

    func report(_ plan: MemberPlan, reason: CommunityReportReason, api: APIClient) async {
        plans.removeAll { $0.id == plan.id }
        guard !demo else { return }
        do { try await api.reportSharedPlan(plan.id, reason: reason) } catch { self.error = error.localizedDescription }
    }

    /// A blocked member's plans go at once.
    func blocked(_ userId: String) { plans.removeAll { $0.author.userId == userId } }

    func reset() {
        plans = []
        mine = []
        loaded = false
    }

    private func upsertMine(_ plan: MemberPlan) {
        if let i = mine.firstIndex(where: { $0.id == plan.id }) { mine[i] = plan } else { mine.insert(plan, at: 0) }
    }

    /// One shared plan per programme: My programmes carry a UUID after "my-"; anything else gets a stable one from its id.
    static func planId(_ programme: Programme) -> String {
        let tail = programme.id.hasPrefix(Programme.minePrefix) ? String(programme.id.dropFirst(Programme.minePrefix.count)) : programme.id
        if let u = UUID(uuidString: tail) { return u.uuidString.lowercased() }
        var b = Array(Insecure.MD5.hash(data: Data(programme.id.utf8)))
        b[6] = (b[6] & 0x0F) | 0x30
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString.lowercased()
    }

    #if DEBUG
    func loadDemo() {
        demo = true
        loaded = true
        let bea = CommunityAuthor(userId: "u-bea", nickname: "bench_bea", level: 42)
        let crimpy = CommunityAuthor(userId: "u-crimpy", nickname: "crimpy", level: 4)
        let tom = CommunityAuthor(userId: "u-tom", nickname: "tom_runs", level: 12)
        let picks: [(Programme, CommunityAuthor, SharedPlanLevel, String, Int)] = [
            (Programme.all[0].copy(name: "Bea's Bench Builder"), bea, .intermediate, "Heavy bench twice a week, legs once. Got me to 100 kg.", 14),
            (Programme.all[2].copy(name: "Finger Strength Block"), crimpy, .advanced, "Hangs before climbing, pulls after. Skin first.", 8),
            (Programme.all[3].copy(name: "5k + Lifting Hybrid"), tom, .beginner, "Run Tue/Thu, lift Mon/Fri. Never sore on run days.", 5),
        ]
        plans = picks.map { p, a, l, about, copies in
            MemberPlan(id: Self.planId(p), name: p.name, about: about, level: l, goal: p.goal.rawValue, weeks: p.weeks,
                       sessionsPerWeek: p.sessionsPerWeek, programme: p, author: a, mine: false, copies: copies)
        }
    }
    #endif
}
