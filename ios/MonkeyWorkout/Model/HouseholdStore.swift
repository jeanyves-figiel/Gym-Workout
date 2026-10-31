import APIClient
import Foundation
import SwiftUI
import WorkoutEngine

/// The plan a household shares (#1014): plan days, own recipes they use, plan settings. Optional fields so a plan from
/// another app version still reads.
struct SharedFuelPlan: Codable, Sendable, Equatable {
    var plan: [PlannedMeal]
    var recipes: [Recipe] = []
    var book: MealPlanBook?
    var people: Int?
    var budget: Double?
    var lessWaste: Bool?

    /// "7 days · 14 meals".
    var summary: String {
        let days = Set(plan.map(\.day)).count
        return "\(days) day\(days == 1 ? "" : "s") · \(plan.count) meal\(plan.count == 1 ? "" : "s")"
    }

    enum CodingKeys: String, CodingKey { case plan, recipes, book, people, budget, lessWaste }

    init(plan: [PlannedMeal], recipes: [Recipe] = [], book: MealPlanBook? = nil, people: Int? = nil, budget: Double? = nil, lessWaste: Bool? = nil) {
        self.plan = plan
        self.recipes = recipes
        self.book = book
        self.people = people
        self.budget = budget
        self.lessWaste = lessWaste
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode([PlannedMeal].self, forKey: .plan)
        recipes = (try? c.decodeIfPresent([Recipe].self, forKey: .recipes)) ?? []
        book = try? c.decodeIfPresent(MealPlanBook.self, forKey: .book)
        people = try? c.decodeIfPresent(Int.self, forKey: .people)
        budget = try? c.decodeIfPresent(Double.self, forKey: .budget)
        lessWaste = try? c.decodeIfPresent(Bool.self, forKey: .lessWaste)
    }
}

/// Fuel with a partner (#1014): the household sharing one meal plan and grocery list, its invites, and copies sent to
/// me. The server is the truth for a household: on every read a newer revision replaces this phone's plan; a change
/// made here is written back (debounced) with the revision last read, and a partner's write in between wins (409 →
/// read again, "Sam changed the plan" notice). Ticks go up one by one, so two people in two aisles never clash.
@MainActor @Observable
final class HouseholdStore {
    static let shared = HouseholdStore()

    typealias Home = Household<SharedFuelPlan>
    typealias Copy = FuelShare<SharedFuelPlan>

    private(set) var household: Home?
    private(set) var incoming: [HouseholdInvite] = []
    private(set) var outgoing: [HouseholdInvite] = []
    private(set) var copies: [Copy] = []
    /// One-line news for the plan screens ("Sam changed the plan"); cleared after a few seconds.
    private(set) var notice: String?
    /// Last error from an action, shown on the card or sheet that did it.
    var error: String?
    /// An invite the member must leave their current household to accept (server 409 `in_household`).
    private(set) var needsLeave: String?

    @ObservationIgnored var api: APIClient?
    /// Revision of the plan on this phone (last read or written).
    @ObservationIgnored private var rev = 0
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var lastRead: Date = .distantPast

    private init() {
        FuelStore.shared.onShareChange = { [weak self] plan, ticked, unticked in
            self?.changedHere(plan: plan, ticked: ticked, unticked: unticked)
        }
    }

    /// Sharing with at least one other member.
    var isSharing: Bool { !(household?.others.isEmpty ?? true) }
    var meId: String? { household?.members.first { $0.me }?.userId }

    /// Who else ticked a line, by item id (nickname).
    var tickedByOthers: [String: String] {
        guard let h = household, let me = meId else { return [:] }
        var out: [String: String] = [:]
        for t in h.bought {
            if let by = t.by, by.userId != me { out[t.itemId] = by.nickname }
        }
        return out
    }

    /// "You + Sam", "You + Sam + Kim".
    var membersLine: String {
        (["You"] + (household?.others.map(\.nickname) ?? [])).joined(separator: " + ")
    }

    // MARK: Reading

    /// Reads the household and copies; skipped when read in the last few seconds unless `force`.
    func refresh(force: Bool = false) async {
        guard let api, force || Date().timeIntervalSince(lastRead) > 8 else { return }
        lastRead = Date()
        do {
            take(try await api.household(SharedFuelPlan.self))
            copies = (try? await api.fuelShares(SharedFuelPlan.self)) ?? copies
        } catch {
            // Offline or signed out: keep what was shown.
        }
    }

    /// Keeps the household fresh while a plan screen is on screen (attach with `.task`).
    func watch() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(isSharing ? 10 : 60))
        }
    }

    private func take(_ v: HouseholdView<SharedFuelPlan>) {
        incoming = v.invites.incoming
        outgoing = v.invites.outgoing
        let first = household == nil
        household = v.household
        guard let h = v.household else {
            rev = 0
            return
        }
        let fuel = FuelStore.shared
        if h.rev != rev {
            if let st = h.state {
                if st != fuel.sharedPlan {
                    fuel.applyShared(st)
                    if !first, let by = h.updatedBy, by.userId != meId { show("\(by.nickname) changed the plan") }
                }
                rev = h.rev
            } else {
                // Nobody wrote a plan yet: mine becomes the household's.
                rev = h.rev
                schedulePush(after: 0)
            }
        }
        fuel.applySharedBought(Set(h.bought.map(\.itemId)))
        // Everyone in the household eats: servings follow.
        if h.members.count > fuel.saved.people { fuel.setPlanOptions(people: h.members.count) }
    }

    // MARK: Writing

    private func changedHere(plan: Bool, ticked: Set<String>, unticked: Set<String>) {
        guard household != nil, let api else { return }
        if plan { schedulePush(after: 1.5) }
        if !ticked.isEmpty || !unticked.isEmpty {
            Task {
                if !ticked.isEmpty { try? await api.setHouseholdBought(Array(ticked), bought: true) }
                if !unticked.isEmpty { try? await api.setHouseholdBought(Array(unticked), bought: false) }
            }
        }
    }

    private func schedulePush(after seconds: Double) {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    private func push() async {
        guard let api, household != nil else { return }
        do {
            rev = try await api.putHouseholdState(rev: rev, state: FuelStore.shared.sharedPlan)
        } catch let APIError.server(status, _, _) where status == 409 {
            show("Your partner changed the plan first. Showing theirs.")
            await refresh(force: true)
        } catch {
            // Offline: the next change or read tries again.
        }
    }

    private func show(_ text: String) {
        notice = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if self?.notice == text { self?.notice = nil }
        }
    }

    // MARK: Actions

    func invite(_ userId: String) async {
        guard let api else { return }
        error = nil
        do { take(try await api.inviteToHousehold(userId, SharedFuelPlan.self)) } catch { self.error = Self.message(error) }
    }

    func accept(_ id: String, leaveCurrent: Bool = false) async {
        guard let api else { return }
        error = nil
        do {
            // Their plan replaces mine on this phone (the household's is the truth): read it as new.
            rev = -1
            take(try await api.acceptHouseholdInvite(id, leaveCurrent: leaveCurrent, SharedFuelPlan.self))
            needsLeave = nil
        } catch let APIError.server(_, code, message) where code == "in_household" {
            rev = household?.rev ?? 0
            needsLeave = id
            self.error = message
        } catch {
            rev = household?.rev ?? 0
            self.error = Self.message(error)
        }
    }

    /// Decline theirs or cancel mine.
    func drop(_ id: String) async {
        guard let api else { return }
        incoming.removeAll { $0.id == id }
        outgoing.removeAll { $0.id == id }
        if needsLeave == id { needsLeave = nil }
        try? await api.dropHouseholdInvite(id)
        await refresh(force: true)
    }

    /// Leave: this phone keeps its copy of the plan.
    func leave() async {
        guard let api else { return }
        error = nil
        do {
            try await api.leaveHousehold()
            household = nil
            rev = 0
            pushTask?.cancel()
        } catch { self.error = Self.message(error) }
    }

    /// Sends a one-off copy; nil when sent, else the reason.
    func send(to userId: String, kind: FuelShareKind, groceries: [SharedGroceryLine]) async -> String? {
        guard let api else { return "Sign in to send." }
        let payload = FuelSharePayload(plan: kind == .groceries ? nil : FuelStore.shared.sharedPlan,
                                       groceries: kind == .plan ? nil : groceries)
        do {
            try await api.sendFuelShare(to: userId, kind: kind, payload: payload)
            return nil
        } catch { return Self.message(error) }
    }

    func dismiss(_ copy: Copy) async {
        copies.removeAll { $0.id == copy.id }
        try? await api?.dropFuelShare(copy.id)
    }

    /// "Use as my plan": the copy replaces this phone's plan (and the household's, when sharing). Undo puts it back.
    func use(_ copy: Copy) {
        guard let p = copy.payload.plan else { return }
        let fuel = FuelStore.shared
        let before = fuel.sharedPlan
        fuel.applyShared(p, local: true)
        UndoCloseCenter.shared.show(UndoOffer(title: "Plan from \(copy.from.nickname)", detail: p.summary, symbol: "fork.knife",
                                              reopen: { AnyView(EmptyView()) }, revert: { fuel.applyShared(before, local: true) }))
        Task { await dismiss(copy) }
    }

    func signOut() {
        household = nil
        incoming = []
        outgoing = []
        copies = []
        rev = 0
        pushTask?.cancel()
    }

    private static func message(_ e: Error) -> String {
        if case let APIError.server(_, _, message) = e { return message }
        return "Couldn't reach MonkeyWorkout. Try again."
    }
}
