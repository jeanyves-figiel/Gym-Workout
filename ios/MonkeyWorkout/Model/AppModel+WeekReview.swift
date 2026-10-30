import Foundation
import WorkoutEngine

/// Weekly Coach review (#867): the last review, which changes were applied and whether the card was closed, kept on the
/// device for its account (one review a week, asked once).
@MainActor @Observable
final class WeekReviewStore {
    static let shared = WeekReviewStore()

    struct Saved: Codable, Equatable {
        var review: WeekReview
        /// Monday key of the week the changes apply to.
        var nextWeekOf: String
        var applied: [String] = []
        var closed = false
    }

    private static let file = "week-review.json"
    private(set) var saved: Saved?
    var loading = false
    @ObservationIgnored private var ownerId: String?

    func load(ownerId: String?) {
        guard self.ownerId != ownerId else { return }
        self.ownerId = ownerId
        saved = DeviceCache.load(Saved.self, Self.file, userId: ownerId)
    }

    func set(_ s: Saved?) {
        saved = s
        if ownerId != "demo" { DeviceCache.save(s, Self.file, userId: ownerId) }
    }
}

extension AppModel {
    /// The review to show on Train today: Sunday and Monday, for the week just done, until closed.
    var weekReview: WeekReviewStore.Saved? {
        guard let s = WeekReviewStore.shared.saved, !s.closed, let week = WeekReview.reviewedWeek(on: Date(), calendar: planCalendar),
              s.review.weekOf == PlanCalendar.key(week, planCalendar) else { return nil }
        return s
    }

    /// Asks Coach for this week's review once (Pro; quietly nothing when the server says no).
    func loadWeekReview(now: Date = Date()) async {
        let store = WeekReviewStore.shared
        store.load(ownerId: demo ? "demo" : state.ownerId)
        // Demo shows it on its own screen (`week-review`) only, so Train screenshots stay the same any day.
        guard !demo, !store.loading, let reviewed = WeekReview.reviewedWeek(on: now, calendar: planCalendar),
              !ProStore.shared.locked else { return }
        let key = PlanCalendar.key(reviewed, planCalendar)
        guard store.saved?.review.weekOf != key, let built = weekReviewDigest(reviewed: reviewed, now: now), !built.0.next.isEmpty else { return }
        let (digest, nextWeekOf) = built
        store.loading = true
        defer { store.loading = false }
        guard let review = try? await api.coachReview(digest, as: WeekReview.self) else { return }
        store.set(WeekReviewStore.Saved(review: review.cleaned(for: digest), nextWeekOf: nextWeekOf))
    }

    /// The week under review and the coming week, without identifiers. Sunday: this week, next week coming. Monday:
    /// last week from history (done workouts), this week coming.
    func weekReviewDigest(reviewed: Date, now: Date = Date()) -> (WeekReviewDigest, String)? {
        let cal = planCalendar
        guard let end = cal.date(byAdding: .day, value: 7, to: reviewed) else { return nil }
        let thisMonday = Progression.weekStart(now, cal)
        let current = reviewed == thisMonday
        var days: [WeekReviewDigest.Day] = []
        let records = state.history.filter { $0.startedAt >= reviewed && $0.startedAt < end }
        func minutes(_ id: String) -> Int? { records.last { $0.sessionId == id }.map { $0.durationSec / 60 } }
        if current, let week = calendarWeeks(count: 1, now: now).first {
            for s in week.plan.sessions {
                guard let wd = s.weekday else { continue }
                days.append(.init(weekday: wd, title: String(s.displayTitle.prefix(60)), done: doneIds.contains(s.id), minutes: minutes(s.id)))
            }
        } else {
            for r in records {
                days.append(.init(weekday: WeekSchedule.fromCalendar(cal.component(.weekday, from: r.startedAt)), title: String(r.title.prefix(60)),
                                  done: true, minutes: r.durationSec / 60))
            }
        }
        let coming: PlanCalendar.Week? = current ? aheadWeeks(now: now).first : calendarWeeks(count: 1, now: now).first
        guard let coming else { return nil }
        let next: [WeekReviewDigest.Next] = coming.plan.sessions.compactMap { s in
            guard let wd = s.weekday, s.hiit == nil, current || !doneIds.contains(s.id) else { return nil }
            let edited = current ? (aheadEdited(s.id) ?? s) : s.applying(sessionEdit(s.id))
            return .init(id: s.id, weekday: wd, title: String(s.displayTitle.prefix(60)), lifts: WeekReviewDigest.lifts(edited))
        }
        let mood = WeekReviewDigest.mood(MindStore.shared.saved.checkIns, from: reviewed, to: end)
        let snap = health?.snapshot
        var hrv: String?
        if let h = snap?.hrv, let b = snap?.hrvBaseline, b > 0 {
            let p = Int(((h / b - 1) * 100).rounded())
            hrv = p >= 0 ? "+\(p) % vs usual" : "−\(abs(p)) % vs usual"
        }
        let digest = WeekReviewDigest(
            weekOf: PlanCalendar.key(reviewed, cal), goal: profile?.goal.rawValue, level: profile?.experience.rawValue,
            days: Array(days.sorted { $0.weekday < $1.weekday }.prefix(21)),
            bests: WeekReviewDigest.bests(records: state.history, from: reviewed, to: end),
            sleepHours: snap?.sleepHours.map { ($0 * 10).rounded() / 10 }, hrv: hrv, mood: mood.average, moodAbout: mood.about,
            next: Array(next.prefix(14)), offDays: coming.off.keys.sorted()
        )
        return (digest, PlanCalendar.key(coming.start, cal))
    }

    func isApplied(_ c: WeekReviewChange) -> Bool { WeekReviewStore.shared.saved?.applied.contains(c.id) == true }

    /// Makes one change on the coming week: a later week through its ahead moves, skips and edits, this week directly.
    func applyWeekReview(_ c: WeekReviewChange) {
        let store = WeekReviewStore.shared
        guard var s = store.saved, !s.applied.contains(c.id) else { return }
        let ahead = aheadWeeks().first { PlanCalendar.key($0.start, planCalendar) == s.nextWeekOf }
        switch c.kind {
        case .move:
            guard let wd = c.weekday else { return }
            if let ahead { moveSession(c.sessionId, to: wd, in: ahead) } else { moveSession(c.sessionId, to: wd) }
        case .skip:
            if let ahead { setSkipped(true, c.sessionId, in: ahead) } else { skipSession(c.sessionId) }
        case .lighter:
            guard let blocks = editableBlocks(c.sessionId) else { return }
            saveSessionEdit(c.sessionId, blocks: blocks.lighter())
        case .addSet:
            guard let uid = c.uid, let blocks = editableBlocks(c.sessionId) else { return }
            saveSessionEdit(c.sessionId, blocks: blocks.addingSet(uid))
        }
        s.applied.append(c.id)
        store.set(s)
    }

    func closeWeekReview() {
        guard var s = WeekReviewStore.shared.saved else { return }
        s.closed = true
        WeekReviewStore.shared.set(s)
    }

    /// Ask Coach about it (#867 C): the chat opens on the review, so the member can tweak it in words.
    func askCoachAboutWeekReview(_ r: WeekReview) {
        let changes = r.changes.map(\.label).joined(separator: "; ")
        CoachAsk.shared.request = AskCoachRequest(focus: CoachFocus(
            screen: "train", title: "Week review",
            detail: "Score \(r.score). \(r.headline). \(r.summary)" + (changes.isEmpty ? "" : " Changes: \(changes)"),
            starters: ["Can I keep my days?", "Make next week lighter", "Why these changes?"]
        ))
    }
}
