import Foundation
import Observation
import WorkoutEngine

/// A climbing session tracked live (#829). Kept on the device until finished, so closing the screen or the app keeps
/// it going.
struct ClimbLiveSession: Codable, Equatable, Sendable {
    var id = UUID()
    var start = Date()
    var kind: ClimbKind = .boulder
    var scale: ClimbScale
    /// Grade the next tap logs.
    var grade: String
    var attempts: [ClimbAttempt] = []
    /// Last change on either side: the newer copy wins when the Watch and the iPhone both changed it.
    var updatedAt = Date()
    /// The Watch records it (heart rate, the Health workout).
    var watch = false
    /// Gym or crag (#832): the last climbing place to start with.
    var place: SessionPlace?

    var tally: ClimbTally { ClimbTally(attempts, scale: scale) }
    func minutes(_ now: Date = Date()) -> Int { max(1, Int(now.timeIntervalSince(start) / 60)) }
}

/// Climbing live on the iPhone (#829 B), mirrored with the Watch when one tracks it (#829 A).
@MainActor @Observable
final class ClimbLive {
    static let shared = ClimbLive()

    private(set) var session: ClimbLiveSession?
    var running: Bool { session != nil }

    private static let key = "climbLive"
    /// Grade scale the member last used.
    private static let scaleKey = "climbLiveScale"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let s = try? JSONDecoder().decode(ClimbLiveSession.self, from: data) {
            session = s
        }
    }

    /// Starts a session, or keeps the one running. `watch`: also tracked on a paired Watch.
    func start(watch: Bool, place: SessionPlace?) {
        guard session == nil else { return }
        let scale = UserDefaults.standard.string(forKey: Self.scaleKey).flatMap(ClimbScale.init(rawValue:)) ?? .font
        session = ClimbLiveSession(scale: scale, grade: scale.start, watch: watch, place: place)
        save(send: false)
        if watch { WatchSync.shared.startClimb() }
    }

    func log(_ result: ClimbResult) {
        // 300 goes at most: what the server keeps for one climb.
        guard let g = session?.grade, (session?.attempts.count ?? 0) < 300 else { return }
        session?.attempts.append(ClimbAttempt(grade: g, result: result))
        save()
    }

    /// Takes the last go back.
    func undo() {
        guard session?.attempts.isEmpty == false else { return }
        session?.attempts.removeLast()
        save()
    }

    func setGrade(_ grade: String) {
        guard session?.grade != grade else { return }
        session?.grade = grade
        save()
    }

    func setScale(_ scale: ClimbScale) {
        guard var s = session, s.scale != scale else { return }
        s.scale = scale
        s.grade = scale.start
        session = s
        UserDefaults.standard.set(scale.rawValue, forKey: Self.scaleKey)
        save()
    }

    func setPlace(_ place: SessionPlace?) {
        guard session != nil else { return }
        session?.place = place
        save(send: false)
    }

    func setKind(_ kind: ClimbKind) {
        guard session?.kind != kind else { return }
        session?.kind = kind
        save(send: false)
    }

    /// Ends it and logs the climb. `end`: when it finished (the Watch's time when ended there). The Health workout is
    /// written here only when no Watch recorded it.
    @discardableResult
    func finish(model: AppModel, health: HealthManager, end: Date = Date(), fromWatch: Bool = false) -> ClimbLog? {
        guard let s = session else { return nil }
        session = nil
        persist()
        if s.watch, !fromWatch {
            // The Watch ends its workout and saves it to Health with this climb's id.
            var copy = Self.copy(s)
            copy.ended = end
            WatchSync.shared.sendClimb(copy)
        }
        let t = s.tally
        let minutes = s.minutes(end)
        let log = ClimbLog(id: s.id, kind: s.kind, start: s.start, minutes: minutes,
                           effort: ClimbTally.effort(attempts: t.attempts, minutes: minutes), topGrade: t.top,
                           attempts: s.attempts.isEmpty ? nil : s.attempts, scale: s.scale, place: s.place)
        model.saveClimb(log)
        let weight = model.body.weightKg ?? health.snapshot.weightKg
        Task {
            if !s.watch, await health.saveClimb(log, kcal: Climbs.kcal(log, weightKg: weight)) {
                await health.refresh()
            } else if s.watch {
                // The Watch's workout lands in Health a moment later.
                try? await Task.sleep(for: .seconds(8))
                await health.refresh()
            }
        }
        return log
    }

    /// Throws the session away, nothing logged.
    func discard() {
        guard let s = session else { return }
        session = nil
        persist()
        if s.watch {
            var copy = Self.copy(s)
            copy.ended = Date()
            copy.discarded = true
            WatchSync.shared.sendClimb(copy)
        }
    }

    #if DEBUG
    /// CI screenshots (#829): a session 47′ in with 9 goes, last one 72″ ago.
    func demo() {
        let now = Date()
        let goes: [(String, ClimbResult, Double)] = [("5+", .flash, 44), ("6A", .flash, 40), ("6A+", .fall, 35), ("6A+", .send, 31),
                                                     ("6B", .fall, 25), ("6B", .fall, 20), ("6B", .send, 14), ("6A", .flash, 7), ("6B+", .fall, 1.2)]
        session = ClimbLiveSession(start: now.addingTimeInterval(-47 * 60), scale: .font, grade: "6B+",
                                   attempts: goes.map { ClimbAttempt(grade: $0.0, result: $0.1, at: now.addingTimeInterval(-$0.2 * 60)) })
    }
    #endif

    // MARK: Watch

    var watchCopy: WClimbLive? { session.map(Self.copy) }

    private static func copy(_ s: ClimbLiveSession) -> WClimbLive {
        WClimbLive(id: s.id, start: s.start, grades: s.scale.grades, grade: s.grade,
                   attempts: s.attempts.map { WClimbAttempt(id: $0.id, grade: $0.grade, result: $0.result.rawValue, at: $0.at) },
                   updatedAt: s.updatedAt)
    }

    /// The session as the Watch changed it; ended there → logged here.
    func fromWatch(_ w: WClimbLive, model: AppModel, health: HealthManager) {
        if var s = session, s.id == w.id {
            if w.updatedAt > s.updatedAt {
                s.grade = w.grade
                s.attempts = w.attempts.compactMap { a in
                    ClimbResult(rawValue: a.result).map { ClimbAttempt(id: a.id, grade: a.grade, result: $0, at: a.at) }
                }
                s.updatedAt = w.updatedAt
                s.watch = true
                session = s
                persist()
            }
        } else if session == nil, w.ended == nil, !model.climbLogs.contains(where: { $0.id == w.id }) {
            // Started on the Watch: the iPhone screen follows it.
            session = ClimbLiveSession(id: w.id, start: w.start, scale: ClimbScale.allCases.first { $0.grades == w.grades } ?? .font,
                                       grade: w.grade,
                                       attempts: w.attempts.compactMap { a in
                                           ClimbResult(rawValue: a.result).map { ClimbAttempt(id: a.id, grade: a.grade, result: $0, at: a.at) }
                                       },
                                       updatedAt: w.updatedAt, watch: true)
            persist()
        } else {
            return
        }
        if let end = w.ended, session?.id == w.id {
            if w.discarded == true {
                session = nil
                persist()
            } else {
                finish(model: model, health: health, end: end, fromWatch: true)
            }
        }
    }

    private func save(send: Bool = true) {
        session?.updatedAt = Date()
        persist()
        if send, let s = session, s.watch { WatchSync.shared.sendClimb(Self.copy(s)) }
    }

    private func persist() {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
