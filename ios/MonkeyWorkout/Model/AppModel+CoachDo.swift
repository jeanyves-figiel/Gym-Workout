import APIClient
import Foundation
import WorkoutEngine

/// Coach can act (#999, mix A + B + C from `coach-can-act/proposals.png`): what Coach does for the member from the chat.
/// The server sends only allowlisted kinds (backend `cleanDo`); the app checks each again against its own data and
/// drops anything it can't do. Logs (water, food, mood) happen at once with Undo; plan changes (move, skip, swap) wait
/// for a tap; two or more come as one checklist. Nothing here touches the account, payment, posts or deletes data.
struct CoachTask: Identifiable, Equatable {
    enum Kind: Equatable {
        case water(Int)
        case food([FoodServing], names: String, slot: String)
        case mood(Int)
        case move(sessionId: String, weekday: Int, title: String)
        case skip(sessionId: String, title: String)
        case swap(sessionId: String, uid: String, from: String, toId: String, to: String)
    }

    enum Status: Equatable { case waiting, done, undone, failed }

    /// What Undo puts back.
    enum Undo: Equatable {
        case fuel(day: Date, log: FuelDayLog)
        case mood(MindCheckIn)
        case moves([SessionMove]?)
        case skip(String)
        case swap(String, [Block]?)
    }

    let id = UUID()
    let kind: Kind
    var status: Status = .waiting
    var undo: Undo?
    /// Ticked in the checklist (C).
    var on = true

    /// Logs are done at once (B); plan changes ask first (A).
    var instant: Bool {
        switch kind {
        case .water, .food, .mood: true
        case .move, .skip, .swap: false
        }
    }

    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let moodWords = ["drained", "meh", "good", "great", "amazing"]

    var symbol: String {
        switch kind {
        case .water: "drop.fill"
        case .food: "fork.knife"
        case .mood: "face.smiling"
        case .move: "calendar"
        case .skip: "forward.end.fill"
        case .swap: "arrow.left.arrow.right"
        }
    }

    var title: String {
        switch kind {
        case let .water(n): n == 1 ? "1 glass of water" : "\(n) glasses of water"
        case let .food(_, names, _): names
        case let .mood(m): "Feeling \(Self.moodWords[max(0, min(4, m - 1))])"
        case let .move(_, wd, t): "Move \(t) to \(Self.dayNames[max(0, min(6, wd - 1))])"
        case let .skip(_, t): "Skip \(t) today"
        case let .swap(_, _, from, _, to): "\(from) → \(to)"
        }
    }

    /// The big value on the right of the card.
    var value: String {
        switch kind {
        case let .water(n): "+\(n)"
        case let .food(items, _, _): "\(items.count)"
        case let .mood(m): Feel(rawValue: m)?.emoji ?? ""
        case let .move(_, wd, _): String(Self.dayNames[max(0, min(6, wd - 1))].prefix(3))
        case .skip: "Off"
        case .swap: "1"
        }
    }

    var doneLabel: String {
        switch kind {
        case .water: "WATER ADDED"
        case .food: "FOOD LOGGED"
        case .mood: "MOOD LOGGED"
        case .move: "MOVED"
        case .skip: "SKIPPED"
        case .swap: "SWAPPED"
        }
    }

    var askLabel: String {
        switch kind {
        case .move: "Move it"
        case .skip: "Skip it"
        case .swap: "Swap it"
        default: "Do it"
        }
    }
}

extension AppModel {
    /// Today's exercises by name (#999), so Coach can swap one; none once it is done or under way.
    var coachTodayExercises: [String]? {
        guard let s = todaySession, canEditExercises(s), let blocks = editableBlocks(s.id) else { return nil }
        var seen = Set<String>()
        let names = blocks.flatMap(\.items).compactMap { Exercise.find($0.exerciseId)?.name }.filter { seen.insert($0).inserted }
        return names.isEmpty ? nil : Array(names.prefix(40))
    }

    /// Coach's actions as the app can do them (#999); anything that doesn't fit today's data is dropped.
    func coachTasks(_ list: [CoachChatDo]) -> [CoachTask] {
        var out: [CoachTask] = []
        for d in list.prefix(5) {
            guard let k = coachKind(d) else { continue }
            out.append(CoachTask(kind: k))
        }
        return out
    }

    private func coachKind(_ d: CoachChatDo) -> CoachTask.Kind? {
        switch d.kind {
        case "water":
            guard let n = d.glasses, (1...10).contains(n) else { return nil }
            return .water(n)
        case "food":
            guard let text = d.foods?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let own = FuelStore.shared.saved.foods
            let foods = Food.find(in: text, own: own).prefix(6)
            guard !foods.isEmpty else { return nil }
            let plan = fuelPlan(on: Date())
            let cal = Calendar.current
            let minute = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
            let slot = d.meal.flatMap { m in plan.slots.first { $0.kind.rawValue == m } } ?? plan.next(after: minute)
            guard let slot else { return nil }
            return .food(foods.map { FoodServing(foodId: $0.id) }, names: foods.map(\.name).joined(separator: ", "), slot: slot.id)
        case "mood":
            guard let m = d.mood, (1...5).contains(m) else { return nil }
            return .mood(m)
        case "move":
            guard let wd = d.weekday, let s = todaySession, moveTargets(s.id).contains(wd), wd != todayWeekday else { return nil }
            return .move(sessionId: s.id, weekday: wd, title: s.displayTitle)
        case "skip":
            guard let s = todaySession, canSkip(s) else { return nil }
            return .skip(sessionId: s.id, title: s.displayTitle)
        case "swap":
            guard let from = d.from, let to = d.to, let s = todaySession, canEditExercises(s),
                  let blocks = editableBlocks(s.id), let target = Exercise.named(to) else { return nil }
            let key = from.lowercased()
            guard let item = blocks.flatMap(\.items).first(where: { Exercise.find($0.exerciseId)?.name.lowercased() == key }),
                  item.exerciseId != target.id, let name = Exercise.find(item.exerciseId)?.name else { return nil }
            return .swap(sessionId: s.id, uid: item.uid, from: name, toId: target.id, to: target.name)
        default:
            return nil
        }
    }

    /// Does one task; returns it with its Undo, or failed when today's data changed meanwhile.
    func performCoach(_ t: CoachTask) -> CoachTask {
        var t = t
        switch t.kind {
        case let .water(n):
            let day = Date(), before = FuelStore.shared.log(day)
            FuelStore.shared.addGlasses(n, on: day)
            t.undo = .fuel(day: day, log: before)
        case let .food(items, _, slotId):
            let day = Date(), plan = fuelPlan(on: day)
            guard let slot = plan.slots.first(where: { $0.id == slotId }) else { t.status = .failed; return t }
            let store = FuelStore.shared, before = store.log(day)
            store.update(day, plan: plan) { $0.log(items, at: slot, own: store.saved.foods) }
            t.undo = .fuel(day: day, log: before)
        case let .mood(m):
            let c = MindCheckIn(date: Date(), mood: m)
            MindStore.shared.addCheckIn(c)
            t.undo = .mood(c)
        case let .move(id, wd, _):
            guard moveTargets(id).contains(wd) else { t.status = .failed; return t }
            let before = state.synced?.moves
            moveSession(id, to: wd)
            t.undo = .moves(before)
        case let .skip(id, _):
            guard let s = plan?.sessions.first(where: { $0.id == id }), canSkip(s) else { t.status = .failed; return t }
            skipSession(id)
            t.undo = .skip(id)
        case let .swap(id, uid, _, toId, _):
            guard let blocks = editableBlocks(id), blocks.flatMap(\.items).contains(where: { $0.uid == uid }) else { t.status = .failed; return t }
            let before = isEdited(id) ? blocks : nil
            swapInSession(id, uid: uid, to: toId)
            t.undo = .swap(id, before)
        }
        t.status = .done
        return t
    }

    /// Puts back what the task changed.
    func undoCoach(_ t: CoachTask) -> CoachTask {
        var t = t
        guard t.status == .done, let u = t.undo else { return t }
        switch u {
        case let .fuel(day, log):
            FuelStore.shared.update(day, plan: fuelPlan(on: day)) { $0 = log }
        case let .mood(c):
            MindStore.shared.removeCheckIn(c)
        case let .moves(before):
            guard var sp = state.synced else { break }
            sp.moves = before
            state.synced = sp
            state.profileDirty = true
            replanCurrentWeek()
            persist()
            Task { await sync() }
        case let .skip(id):
            unskip(id)
        case let .swap(id, blocks):
            restoreSessionEdit(id, to: blocks)
        }
        t.status = .undone
        return t
    }
}
