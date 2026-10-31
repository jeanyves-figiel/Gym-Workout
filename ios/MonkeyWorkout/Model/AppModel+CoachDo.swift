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
        /// Today's dose of a supplement in the stack, ticked as in Fuel.
        case supplement(doseId: String, name: String, emoji: String)
        case move(sessionId: String, weekday: Int, title: String)
        case skip(sessionId: String, title: String)
        case swap(sessionId: String, uid: String, from: String, toId: String, to: String)
        /// An earlier workout of this week logged as planned.
        case done(sessionId: String, weekday: Int, title: String)
        /// Morning reminder of a workout day: a time, or nil = off.
        case reminder(Int?)
        /// When Coach reads answers aloud (Ask Coach setting).
        case voice(AskCoachPref.Speak)
    }

    enum Status: Equatable { case waiting, done, undone, failed }

    /// What Undo puts back.
    enum Undo: Equatable {
        case fuel(day: Date, log: FuelDayLog)
        case mood(MindCheckIn)
        case moves([SessionMove]?)
        case skip(String)
        case swap(String, [Block]?)
        case record(UUID)
        case notify(NotificationPrefs)
        case voice(AskCoachPref.Speak)
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
        case .water, .food, .supplement, .mood: true
        case .move, .skip, .swap, .done, .reminder, .voice: false
        }
    }

    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let moodWords = ["drained", "meh", "good", "great", "amazing"]

    var symbol: String {
        switch kind {
        case .water: "drop.fill"
        case .food: "fork.knife"
        case .supplement: "pills.fill"
        case .mood: "face.smiling"
        case .move: "calendar"
        case .skip: "forward.end.fill"
        case .swap: "arrow.left.arrow.right"
        case .done: "checkmark.seal.fill"
        case .reminder: "bell.fill"
        case .voice: "speaker.wave.2.fill"
        }
    }

    var title: String {
        switch kind {
        case let .water(n): n == 1 ? "1 glass of water" : "\(n) glasses of water"
        case let .food(_, names, _): names
        case let .supplement(_, name, _): name
        case let .mood(m): "Feeling \(Self.moodWords[max(0, min(4, m - 1))])"
        case let .move(_, wd, t): "Move \(t) to \(Self.dayNames[max(0, min(6, wd - 1))])"
        case let .skip(_, t): "Skip \(t) today"
        case let .swap(_, _, from, _, to): "\(from) → \(to)"
        case let .done(_, wd, t): "\(t) on \(Self.dayNames[max(0, min(6, wd - 1))]) done"
        case let .reminder(m): m.map { "Workout reminder at \(NotificationPrefs.clock($0))" } ?? "Workout reminders off"
        case let .voice(v): "Read answers aloud: \(v.title.lowercased())"
        }
    }

    /// The big value on the right of the card.
    var value: String {
        switch kind {
        case let .water(n): "+\(n)"
        case let .food(items, _, _): "\(items.count)"
        case let .supplement(_, _, emoji): emoji
        case let .mood(m): Feel(rawValue: m)?.emoji ?? ""
        case let .move(_, wd, _): String(Self.dayNames[max(0, min(6, wd - 1))].prefix(3))
        case .skip: "Off"
        case .swap: "1"
        case .done: "✓"
        case let .reminder(m): m.map { NotificationPrefs.clock($0) } ?? "Off"
        case let .voice(v): v == .never ? "Off" : "On"
        }
    }

    var doneLabel: String {
        switch kind {
        case .water: "WATER ADDED"
        case .food: "FOOD LOGGED"
        case .supplement: "TAKEN TODAY"
        case .mood: "MOOD LOGGED"
        case .move: "MOVED"
        case .skip: "SKIPPED"
        case .swap: "SWAPPED"
        case .done: "LOGGED"
        case .reminder: "REMINDER SET"
        case .voice: "SETTING CHANGED"
        }
    }

    var askLabel: String {
        switch kind {
        case .move: "Move it"
        case .skip: "Skip it"
        case .swap: "Swap it"
        case .done: "Log it"
        case .reminder, .voice: "Change it"
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

    /// Coach's actions as the app can do them (#999). What doesn't fit today's data is not done, and `missed` says
    /// why in a line the chat shows, so Coach's "Done" never stands for something that didn't happen.
    func coachTasks(_ list: [CoachChatDo]) -> (tasks: [CoachTask], missed: [String]) {
        var out: [CoachTask] = [], missed: [String] = []
        for d in list.prefix(5) {
            if let k = coachKind(d) { out.append(CoachTask(kind: k)) } else { missed.append(Self.missedLine(d)) }
        }
        return (out, missed)
    }

    static func missedLine(_ d: CoachChatDo) -> String {
        switch d.kind {
        case "water": "Couldn't add the water."
        case "food": "Couldn't find \"\(d.foods ?? "that")\" in foods. Add it in Fuel."
        case "supplement": "No \(d.foods ?? "supplement") left to take today in your stack. Add it in Fuel."
        case "mood": "Couldn't log your mood."
        case "move": "Couldn't move today's workout to that day."
        case "skip": "There's no workout left to skip today."
        case "done": "There's no missed workout on that day to log."
        case "reminder": "Couldn't set that reminder time."
        case "voice": "Couldn't change that setting."
        case "swap": "Couldn't swap \(d.from ?? "that exercise") for \(d.to ?? "that one") in today's workout."
        default: "Coach can't do that one."
        }
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
        case "supplement":
            guard let text = d.foods?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
            let log = FuelStore.shared.log(Date())
            let doses = fuelPlan(on: Date()).supplements.filter { log.ticks[$0.id] == nil }
            func hit(_ n: String) -> Bool { let n = n.lowercased(); return n.contains(text) || text.contains(n) }
            guard let dose = doses.first(where: { hit($0.supplement.name) }) else { return nil }
            return .supplement(doseId: dose.id, name: dose.supplement.name, emoji: dose.supplement.emoji)
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
        case "done":
            guard let wd = d.weekday, wd < todayWeekday, let s = missedSessions.first(where: { $0.weekday == wd }) else { return nil }
            return .done(sessionId: s.id, weekday: wd, title: s.displayTitle)
        case "reminder":
            if d.on == false { return .reminder(nil) }
            guard let m = d.minutes, (0..<1440).contains(m) else { return nil }
            return .reminder(m)
        case "voice":
            return d.value.flatMap(AskCoachPref.Speak.init(rawValue:)).map(CoachTask.Kind.voice)
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
        case let .supplement(doseId, _, _):
            let day = Date(), plan = fuelPlan(on: day), store = FuelStore.shared, before = store.log(day)
            guard let dose = plan.supplements.first(where: { $0.id == doseId }), before.ticks[doseId] == nil else { t.status = .failed; return t }
            store.update(day, plan: plan) { $0.tick(dose) }
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
        case let .done(id, _, _):
            guard let s = missedSessions.first(where: { $0.id == id }) else { t.status = .failed; return t }
            t.undo = .record(markMissedDone(s).id)
        case let .reminder(m):
            let n = NotificationManager.shared, before = n.prefs
            if let m { n.prefs.reminderMinutes = m }
            n.prefs.sessionReminders = m != nil
            t.undo = .notify(before)
            Task { await n.reschedule(self) }
        case let .voice(v):
            let before = AskCoachPref.speak
            UserDefaults.standard.set(v.rawValue, forKey: AskCoachPref.speakKey)
            t.undo = .voice(before)
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
        case let .record(id):
            _ = undoWorkout(id)
        case let .notify(prefs):
            NotificationManager.shared.prefs = prefs
            Task { await NotificationManager.shared.reschedule(self) }
        case let .voice(v):
            UserDefaults.standard.set(v.rawValue, forKey: AskCoachPref.speakKey)
        }
        t.status = .undone
        return t
    }
}
