import Foundation
import WidgetKit
import WorkoutEngine

/// Home Screen widgets (#297), app side: keeps the member's look and topic per size (Account → Home Screen widgets,
/// this device only) and writes `HomeWidgetSnapshot` to the App Group whenever the data changes.
@MainActor @Observable
final class HomeWidgetSync {
    static let shared = HomeWidgetSync()
    private static let key = "homeWidgets.settings"

    private(set) var settings: HomeWidgetSettings
    /// Latest data, drawn by the previews in Account.
    private(set) var snapshot = HomeWidgetSnapshot.sample

    private weak var model: AppModel?
    private weak var health: HealthManager?

    private init() {
        settings = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(HomeWidgetSettings.self, from: $0) } ?? .default
    }

    func start(model: AppModel, health: HealthManager) {
        self.model = model
        self.health = health
        push()
    }

    func set(_ new: HomeWidgetSettings) {
        guard new != settings else { return }
        settings = new
        UserDefaults.standard.set(try? JSONEncoder().encode(new), forKey: Self.key)
        push()
    }

    func apply(_ preset: HomeWidgetPreset) { set(preset.settings) }

    /// Rebuilds the snapshot; reloads the widgets only when it changed.
    func push() {
        guard let model else { return }
        var snap = Self.snapshot(model, health: health)
        snap.settings = settings
        // Previews in Account show sample numbers until the member has a plan.
        var preview = snap.signedIn ? snap : HomeWidgetSnapshot.sample
        preview.settings = settings
        snapshot = preview
        guard !model.demo else { return }
        if HomeWidgetStore.save(snap) { WidgetCenter.shared.reloadAllTimelines() }
    }

    static func snapshot(_ model: AppModel, health: HealthManager?) -> HomeWidgetSnapshot {
        var s = HomeWidgetSnapshot()
        guard model.phase == .signedIn, let plan = model.plan else { return s }
        s.signedIn = true
        s.week = plan.week
        s.weeks = Generator.mesocycleWeeks
        s.phase = Generator.phaseName(plan.week)
        s.deload = plan.deload
        s.done = model.completedCount
        s.target = plan.sessions.count

        let cal = model.planCalendar
        let weekStart = Progression.weekStart(Date(), cal)
        let climbs = model.climbLogs
        let climbedDays = Set(climbs.filter { $0.start >= weekStart }.map { WeekSchedule.fromCalendar(cal.component(.weekday, from: $0.start)) })
        let climbPlan = Set(model.profile?.climbingWeekdays ?? [])
        let missed = Set(model.missedToHandle.map(\.id))
        s.days = WeekSchedule.weekdays.map { wd in
            let sessions = plan.sessions.filter { $0.weekday == wd }
            return .init(weekday: wd, planned: !sessions.isEmpty,
                         done: !sessions.isEmpty && sessions.allSatisfy { model.state.done[$0.id] ?? false },
                         missed: sessions.contains { missed.contains($0.id) },
                         climb: climbedDays.contains(wd) || climbPlan.contains(wd))
        }

        if let next = model.nextSession {
            let day = next.weekday.map { $0 == model.todayWeekday ? "Today" : WeekSchedule.name($0) } ?? "This week"
            s.next = .init(id: next.id, title: next.displayTitle, day: day, minutes: next.estMin,
                           exercises: next.blocks.reduce(0) { $0 + $1.items.count },
                           tint: (next.blocks.first { $0.kind == .strength } ?? next.blocks.first)?.kind.category.tintHex ?? 0xCCFF3D)
        }

        let stats = Progression.stats(records: model.state.history, weights: model.weightEntries,
                                      targetPerWeek: model.profile?.sessionsPerWeek ?? plan.sessions.count)
        s.streakWeeks = stats.currentStreakWeeks
        s.bestStreakWeeks = stats.bestStreakWeeks
        s.records = stats.personalRecords.sorted { $0.kg > $1.kg }.prefix(5).map { .init(name: Exercise.find($0.exerciseId)?.name ?? "Exercise", kg: $0.kg) }
        s.volumeWeeks = stats.weeks.suffix(4).map(\.volumeKg)
        if let r = model.history.first {
            s.last = .init(title: r.title, date: r.startedAt, minutes: r.durationSec / 60, sets: r.totalSets, volumeKg: r.volumeKg)
        }

        if let health, health.connected || model.demo {
            s.readiness = Readiness.assess(health.snapshot)?.0.title
            s.sleepHours = health.snapshot.sleepHours
            s.hrv = health.snapshot.hrv
            s.restingHR = health.snapshot.restingHR
        }

        let game = model.game
        let rank = GameRank.of(level: game.level)
        s.level = game.level
        s.rank = rank.title
        s.nextRank = rank.next?.title
        s.xpInLevel = game.xpInLevel
        s.xpPerLevel = GameRank.perLevel
        s.workouts = game.workouts
        s.badges = model.badges.filter(\.unlocked).count

        s.climbing = .init(thisWeek: climbedDays.count, lastDate: climbs.first?.start,
                           lastKind: climbs.first?.kind.label, lastGrade: climbs.first?.topGrade)
        return s
    }
}

/// Opens what a tapped widget links to (`HomeWidgetLink`).
@MainActor
enum HomeWidgetRouter {
    static func open(_ url: URL, model: AppModel) {
        guard url.scheme == HomeWidgetLink.scheme, model.phase == .signedIn else { return }
        switch url.host() {
        case "session":
            let id = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            model.tab = .train
            if model.session(id) != nil { NotificationManager.shared.route = .session(id) }
        case "progress", "level":
            model.tab = .progress
        default:
            model.tab = .train
        }
    }
}
