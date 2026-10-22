import APIClient
import LiftSensor
import SwiftUI
import WorkoutEngine

// Live group sessions (#626, designs B + C from `apple-tech-radar/batch4.html`; no SharePlay).

/// B: gym buddies in Community. Paired buddies training now show their set, with cheers to send; invites to answer.
struct BuddiesCard: View {
    @Environment(AppModel.self) private var model
    private var live: LiveRoom { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "figure.2").font(.system(size: 22, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gym buddies").font(Theme.display(21))
                    Text("Live sets and cheers on your Watch").font(.footnote.weight(.semibold)).opacity(0.88)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(live.paired.filter { $0.live != nil }.count)").font(Theme.display(26)).monospacedDigit()
                    Text("LIVE").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
            }
            ForEach(live.invites) { b in
                HStack(spacing: 10) {
                    AvatarView(url: model.api.resolve(b.avatarUrl), nickname: b.nickname, size: 32)
                    Text("\(b.nickname) wants to train with you").font(Theme.label(13)).lineLimit(2)
                    Spacer(minLength: 4)
                    Button("PAIR") { Task { await live.add(b.userId, api: model.api) } }
                        .font(Theme.label(13)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.lime))
                    Button { Task { await live.remove(b.userId, api: model.api) } } label: {
                        Image(systemName: "xmark").font(.footnote.bold()).frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Decline \(b.nickname)")
                }
                .buttonStyle(.plain)
            }
            ForEach(live.paired) { BuddyRow(buddy: $0) }
            if live.paired.isEmpty && live.invites.isEmpty {
                Text("Open a member's profile and tap Gym buddy. Once you both pair, you see each other's sets while you train.")
                    .font(.caption.weight(.semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x00B86B), Color(hex: 0x1E9BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

private struct BuddyRow: View {
    let buddy: GymBuddy
    @Environment(AppModel.self) private var model
    @State private var sent: LiveCheer?

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(value: buddy.author) {
                HStack(spacing: 10) {
                    AvatarView(url: model.api.resolve(buddy.avatarUrl), nickname: buddy.nickname, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(buddy.nickname.uppercased() + (buddy.live == nil ? "" : " · LIVE")).font(Theme.label(11)).tracking(1)
                        Text(buddy.live.map { "\($0.exercise)\($0.detail.map { " \($0)" } ?? "")\($0.state == .rest ? " ✓" : "")" } ?? "Not training now")
                            .font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            if buddy.live != nil {
                ForEach(LiveCheer.allCases) { c in
                    Button {
                        LiveRoom.shared.cheer(buddy.userId, c, api: model.api)
                        sent = c
                    } label: {
                        Text(c.emoji).font(.system(size: 20)).frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(sent == c ? 0.4 : 0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cheer \(buddy.nickname) \(c.rawValue)")
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.14)))
        .sensoryFeedback(.success, trigger: sent)
    }
}

/// On a member's page: invite, accept, or unpair.
struct BuddyButton: View {
    let userId: String
    @Environment(AppModel.self) private var model
    @State private var busy = false
    private var live: LiveRoom { .shared }

    private func title(_ status: GymBuddy.Status?) -> String {
        switch status {
        case .paired: "GYM BUDDY ✓"
        case .invited: "INVITED · CANCEL"
        case .invitesYou: "ACCEPT GYM BUDDY"
        case nil: "GYM BUDDY"
        }
    }

    var body: some View {
        let status = live.status(userId)
        Button {
            busy = true
            Task {
                defer { busy = false }
                if status == .paired || status == .invited { await live.remove(userId, api: model.api) } else { await live.add(userId, api: model.api) }
            }
        } label: {
            Label(title(status), systemImage: "figure.2")
        }
        .buttonStyle(LimeButtonStyle(fill: status == nil || status == .invitesYou ? Theme.lime : Theme.cardStrong,
                                     text: status == nil || status == .invitesYou ? Theme.ink : .white))
        .disabled(busy)
        .task { if live.buddies.isEmpty { await live.load(api: model.api) } }
    }
}

/// A buddy's set or cheer, over the player for a few seconds.
struct BuddyToast: View {
    private var live: LiveRoom { .shared }

    var body: some View {
        if let p = live.toast {
            HStack(spacing: 8) {
                Text(p.cheer ?? "💪").font(.system(size: 22))
                Text(p.cheer == nil ? "\(p.name) · \(p.text ?? "")" : "\(p.name) cheered you").font(Theme.label(14)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x00B86B), Color(hex: 0x1E9BFF)], startPoint: .leading, endPoint: .trailing)))
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(p.id)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: C: weekly challenge room

private let challengeGradient = LinearGradient(colors: [Color(hex: 0xFF7A00), Color(hex: 0xFF3D8B)], startPoint: .topLeading, endPoint: .bottomTrailing)

struct ChallengeRoomCard: View {
    private var live: LiveRoom { .shared }

    var body: some View {
        NavigationLink { ChallengeRoomView() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Week challenge").font(Theme.label(12)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                HStack(alignment: .firstTextBaseline) {
                    Text(live.wod.name).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
                }
                Text("AMRAP \(WeeklyChallenge.minutes)′ · \(live.room?.joined ?? 0) joined" + ((live.room?.training ?? 0) > 0 ? " · \(live.room!.training) live" : ""))
                    .font(Theme.label(13)).opacity(0.92)
                if let board = live.room?.leaderboard, !board.isEmpty {
                    Text(board.prefix(3).map { "\($0.rank). \($0.me ? "You" : $0.nickname) \(ChallengeRoomView.score($0))" }.joined(separator: " · "))
                        .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(challengeGradient))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Same WOD all week: start it on the big screen, enter rounds + reps, see the leaderboard (live when others train).
struct ChallengeRoomView: View {
    @Environment(AppModel.self) private var model
    @State private var running: WodTimer?
    @State private var scoring = false
    private var live: LiveRoom { .shared }

    static func score(_ e: ChallengeEntry) -> String { e.reps == 0 ? "\(e.rounds) rds" : "\(e.rounds)+\(e.reps)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                Button("START · AMRAP \(WeeklyChallenge.minutes)′") { running = live.wod }
                    .buttonStyle(LimeButtonStyle())
                Button("Enter my score") { scoring = true }
                    .font(Theme.label(15)).foregroundStyle(Theme.lime).frame(maxWidth: .infinity, minHeight: 44)
                ErrorText(message: live.error)
                Text("Leaderboard").eyebrow()
                ForEach(live.room?.leaderboard ?? []) { row($0) }
                if let me = live.room?.me, !(live.room?.leaderboard.contains { $0.me } ?? false) { row(me) }
                if live.room?.leaderboard.isEmpty ?? true {
                    Text("No scores yet this week. Be first.").font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Week challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await live.load(api: model.api)
            // Live leaderboard: refreshed while the room is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await live.load(api: model.api)
            }
        }
        .fullScreenCover(item: $running, onDismiss: {
            live.challengeTimer(nil, api: model.api)
            scoring = true
        }) { t in
            BigScreenTimerView(timer: t).onAppear { live.challengeTimer(live.week, api: model.api) }
        }
        .sheet(isPresented: $scoring) { ChallengeScoreSheet().presentationDetents([.medium]) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week challenge · \(live.week)").font(Theme.label(12)).tracking(1.2).textCase(.uppercase).opacity(0.85)
            Text(live.wod.name).font(Theme.display(34))
            Text("AMRAP \(WeeklyChallenge.minutes)′: as many rounds as you can").font(Theme.label(14))
            ForEach(live.wod.moves, id: \.self) { m in
                Label(m, systemImage: "circle.fill").font(Theme.label(15)).labelStyle(BulletLabel())
            }
            HStack(spacing: 18) {
                stat("\(live.room?.joined ?? 0)", "JOINED")
                stat("\(live.room?.training ?? 0)", "TRAINING NOW")
                if let me = live.room?.me { stat("#\(me.rank)", "YOU") }
            }
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(challengeGradient))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.display(24)).monospacedDigit()
            Text(label).font(Theme.label(9)).tracking(1.2).opacity(0.85)
        }
    }

    private func row(_ e: ChallengeEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(e.rank)").font(Theme.display(18)).foregroundStyle(e.rank <= 3 ? Theme.ink : .white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(e.rank <= 3 ? Theme.lime : Theme.cardStrong))
            AvatarView(url: model.api.resolve(e.avatarUrl), nickname: e.nickname, size: 32)
            Text(e.me ? "You" : e.nickname).font(Theme.label(15)).lineLimit(1)
            if e.live {
                Text("LIVE").font(Theme.label(10)).foregroundStyle(Theme.ink).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xFF3D8B)))
            }
            Spacer(minLength: 4)
            Text(Self.score(e)).font(Theme.display(20)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(e.me ? Theme.cardStrong : Theme.card))
        .accessibilityElement(children: .combine)
    }
}

private struct BulletLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

/// Rounds + extra reps after the timer; the best of the week stays.
private struct ChallengeScoreSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rounds = 0
    @State private var reps = 0
    @State private var saving = false
    @State private var result: ChallengeScoreResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your score").font(Theme.display(26))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.body.bold()).frame(width: 36, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            Stepper("Rounds: \(rounds)", value: $rounds, in: 0...200).font(Theme.label(16))
            Stepper("Extra reps: \(reps)", value: $reps, in: 0...999).font(Theme.label(16))
            if let result {
                Text(result.best ? "Saved: #\(result.rank) this week" : "Your best stays \(result.rounds)+\(result.reps) · #\(result.rank)")
                    .font(Theme.label(15)).foregroundStyle(Theme.lime)
            }
            Button(result == nil ? "SAVE SCORE" : "DONE") {
                if result != nil { return dismiss() }
                saving = true
                Task {
                    result = await LiveRoom.shared.sendScore(rounds: rounds, reps: reps, api: model.api)
                    saving = false
                }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(saving || (rounds == 0 && reps == 0))
            ErrorText(message: LiveRoom.shared.error)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
    }
}
