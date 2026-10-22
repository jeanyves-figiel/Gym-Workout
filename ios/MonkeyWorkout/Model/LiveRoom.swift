import APIClient
import Foundation
import LiftSensor
import UIKit

/// Live group sessions (#626, designs B + C). Gym buddies: while you train, your set goes to paired buddies, theirs
/// and their cheers come to you (and to your Watch). Challenge room: the week's AMRAP with a live leaderboard.
/// Only sent while a paired buddy exists or the challenge runs; polled, so it works without SharePlay or FaceTime.
@MainActor @Observable
final class LiveRoom {
    static let shared = LiveRoom()

    private(set) var buddies: [GymBuddy] = []
    private(set) var room: ChallengeRoom?
    /// Latest cheer or buddy set, shown a few seconds in the player.
    private(set) var toast: WBuddyPing?
    var error: String?

    var paired: [GymBuddy] { buddies.filter { $0.status == .paired } }
    var invites: [GymBuddy] { buddies.filter { $0.status == .invitesYou } }
    func status(_ userId: String) -> GymBuddy.Status? { buddies.first { $0.userId == userId }?.status }

    /// This week's key and WOD (the member's time zone).
    var week: String { WeeklyChallenge.key(for: .now) }
    var wod: WodTimer { WeeklyChallenge.wod(for: week) }

    private var api: APIClient?
    private var sent: LiveSet?
    private var sentAt: Date = .distantPast
    private var lastCheer = 0
    private var seen: [String: Date] = [:]
    private var poll: Task<Void, Never>?
    private var challengeWeek: String?
    /// Newest state from the player, sent by the next tick when the 5″ limit held it back.
    private var latest: LiveSet?

    // MARK: Loading

    /// Members only; before Community loaded, the server says (403) and nothing is sent.
    private var notMember: Bool { Community.shared.loaded && Community.shared.profile == nil }

    func load(api: APIClient) async {
        guard !notMember else { return }
        self.api = api
        do {
            async let b = api.gymBuddies()
            async let r = api.challengeRoom(week: week)
            (buddies, room) = try await (b, r)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: B: buddies

    func add(_ userId: String, api: APIClient) async {
        do {
            _ = try await api.addBuddy(userId)
            await load(api: api)
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ userId: String, api: APIClient) async {
        do {
            try await api.removeBuddy(userId)
            buddies.removeAll { $0.userId == userId }
        } catch { self.error = error.localizedDescription }
    }

    func cheer(_ userId: String, _ kind: LiveCheer, api: APIClient) {
        Task {
            do { try await api.cheerBuddy(userId, kind) } catch { self.error = error.localizedDescription }
        }
    }

    // MARK: Live while training

    /// From the player on every change; nil when the workout ends. Sent when it changed (state at once, the rest at
    /// most every 5″) and only while someone can see it.
    func player(_ live: LiveSet?, api: APIClient) {
        self.api = api
        guard !notMember else { return }
        guard var live else { return end() }
        live.challengeWeek = challengeWeek
        latest = live
        if poll == nil { start() }
        guard !paired.isEmpty || challengeWeek != nil, live != sent else { return }
        if let sent, sent.state == live.state, Date().timeIntervalSince(sentAt) < 5 { return }
        send(live)
    }

    /// The challenge timer opened (week key) or closed (nil).
    func challengeTimer(_ week: String?, api: APIClient) {
        self.api = api
        challengeWeek = week
        if let week {
            player(LiveSet(title: "Week challenge", exercise: WeeklyChallenge.wod(for: week).name, detail: "AMRAP \(WeeklyChallenge.minutes)′", state: .set), api: api)
        } else {
            end()
        }
    }

    private func send(_ live: LiveSet) {
        sent = live
        sentAt = Date()
        guard let api else { return }
        Task { try? await api.setLive(live) }
    }

    private func end() {
        poll?.cancel()
        poll = nil
        challengeWeek = nil
        latest = nil
        guard sent != nil else { return }
        sent = nil
        if let api { Task { try? await api.setLive(nil) } }
    }

    /// Every 15″ while training: cheers for you, buddies' new sets; the live row is refreshed every 2′.
    private func start() {
        poll = Task { [weak self] in
            if let api = self?.api { await self?.load(api: api) }
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func tick() async {
        guard let api else { return }
        guard !paired.isEmpty || challengeWeek != nil else { return }
        if let latest, latest != sent || Date().timeIntervalSince(sentAt) > 120 { send(latest) }
        if let r = try? await api.liveCheers(after: lastCheer) {
            lastCheer = r.last
            for c in r.cheers { ping(WBuddyPing(userId: c.from.userId, name: c.from.nickname, cheer: c.kind.emoji)) }
        }
        guard !paired.isEmpty, let fresh = try? await api.gymBuddies() else { return }
        buddies = fresh
        for b in fresh where b.status == .paired {
            guard let l = b.live, let at = l.updatedAt, l.state == .rest, seen[b.userId] != at else { continue }
            let first = seen[b.userId] == nil
            seen[b.userId] = at
            if !first { ping(WBuddyPing(userId: b.userId, name: b.nickname, text: "\(l.exercise)\(l.detail.map { " \($0)" } ?? "") ✓")) }
        }
    }

    private func ping(_ p: WBuddyPing) {
        toast = p
        WatchSync.shared.sendBuddy(p)
        if p.cheer != nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        let id = p.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toast?.id == id { toast = nil }
        }
    }

    // MARK: C: challenge room

    func sendScore(rounds: Int, reps: Int, api: APIClient) async -> ChallengeScoreResult? {
        do {
            let r = try await api.sendChallengeScore(week: week, rounds: rounds, reps: reps)
            room = try? await api.challengeRoom(week: week)
            return r
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
