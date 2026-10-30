import APIClient
import LiftSensor
import SwiftUI

// Week challenge room (#626 C; #748 design C from `week-challenges/proposals.png`): the server's deck card or the
// members' winner, Easy / Rx / Beast, next week's teaser, your past weeks, the member-week vote and suggestions.

extension ChallengeFormat {
    var kind: WodTimer.Kind {
        switch self {
        case .amrap: .amrap
        case .emom: .emom
        case .fortime: .forTime
        case .tabata: .tabata
        }
    }

    /// Minutes a suggestion may run (same limits as the server); Tabata is 4′ per move.
    var minuteRange: ClosedRange<Int> {
        switch self {
        case .amrap: 5...20
        case .emom: 6...20
        case .fortime: 5...25
        case .tabata: 4...20
        }
    }

    var maxReps: Int {
        switch self {
        case .amrap: 50
        case .emom: 30
        case .fortime: 100
        case .tabata: 0
        }
    }
}

extension ChallengeTier {
    var note: String {
        switch self {
        case .easy: "½ reps"
        case .rx: "as written"
        case .beast: "+1 round or a vest"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .easy: LinearGradient(colors: [Color(hex: 0x2A6DF4), Color(hex: 0x00C7FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .rx: LinearGradient(colors: [Color(hex: 0x8A3CF0), Color(hex: 0xC86BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .beast: LinearGradient(colors: [Color(hex: 0xE8306A), Color(hex: 0xFF7A00)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private let voteGradient = LinearGradient(colors: [Color(hex: 0x8A3CF0), Color(hex: 0xE8306A)], startPoint: .topLeading, endPoint: .bottomTrailing)
private let memberGradient = LinearGradient(colors: [Color(hex: 0xF0C43C), Color(hex: 0xF08A3C)], startPoint: .topLeading, endPoint: .bottomTrailing)

/// Same WOD all week: start it on the big screen, enter your score at your level, see the leaderboard (live when
/// others train); vote for and suggest the member week.
struct ChallengeRoomView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("challenge.tier") private var tierRaw = ChallengeTier.rx.rawValue
    @State private var running: WodTimer?
    @State private var scoring = false
    @State private var suggesting = false
    private var live: LiveRoom { .shared }
    private var tier: ChallengeTier { ChallengeTier(rawValue: tierRaw) ?? .rx }

    static func score(_ e: ChallengeEntry, _ format: ChallengeFormat) -> String {
        if let s = e.seconds { return WodTimer.clock(s) }
        switch format {
        case .tabata: return "\(e.reps) reps"
        case .fortime: return "\(e.reps) reps"
        case .amrap, .emom: return e.reps == 0 ? "\(e.rounds) rds" : "\(e.rounds)+\(e.reps)"
        }
    }

    var body: some View {
        let c = live.challenge
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero(c)
                Button("START · \(c.headline.uppercased())") { running = live.wod }
                    .buttonStyle(LimeButtonStyle())
                    .accessibilityIdentifier("challenge.start")
                levels
                Button("Enter my score") { scoring = true }
                    .font(Theme.label(15)).foregroundStyle(Theme.lime).frame(maxWidth: .infinity, minHeight: 44)
                ErrorText(message: live.error)
                if let next = live.room?.next { teaser(next) }
                vote
                Text("Leaderboard").eyebrow()
                ForEach(live.room?.leaderboard ?? []) { row($0, c.format) }
                if let me = live.room?.me, !(live.room?.leaderboard.contains { $0.me } ?? false) { row(me, c.format) }
                if live.room?.leaderboard.isEmpty ?? true {
                    Text("No scores yet this week. Be first.").font(.subheadline).foregroundStyle(Theme.muted)
                }
                if let past = live.room?.history, !past.isEmpty { history(past) }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Week challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await live.load(api: model.api)
            await live.loadSuggestions(api: model.api)
            #if DEBUG
            if Demo.screen == "challenge-suggest" { suggesting = true }
            #endif
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
        .sheet(isPresented: $scoring) { ChallengeScoreSheet(format: c.format, minutes: c.minutes, tier: tier).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $suggesting) { SuggestChallengeSheet() }
    }

    private func hero(_ c: ChallengeWod) -> some View {
        let member = c.memberWeek == true
        let eyebrow = member
            ? "Member week · \(live.week)" + (c.by.map { " · by \($0.nickname)" } ?? "")
            : "Week challenge · \(live.week)" + (c.card.map { n in c.deckSize.map { " · card \(n)/\($0)" } ?? "" } ?? "")
        return VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(Theme.label(12)).tracking(1.2).textCase(.uppercase).opacity(0.85)
            Text(c.name).font(Theme.display(34)).minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: 6) {
                chip(c.headline)
                chip("No kit")
                chip(tier.label)
            }
            Text(c.rule).font(Theme.label(14))
            ForEach(c.moves, id: \.self) { m in
                Label(m, systemImage: "circle.fill").font(Theme.label(15)).labelStyle(BulletLabel())
            }
            HStack(spacing: 18) {
                stat("\(live.room?.joined ?? 0)", "JOINED")
                stat("\(live.room?.training ?? 0)", "TRAINING NOW")
                if let me = live.room?.me { stat("#\(me.rank)", "YOU") }
            }
            .padding(.top, 4)
        }
        .foregroundStyle(member ? Theme.ink : .white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(member ? memberGradient : LinearGradient.wod(c.format.kind)))
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(Theme.label(12)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.22)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.display(24)).monospacedDigit()
            Text(label).font(Theme.label(9)).tracking(1.2).opacity(0.85)
        }
    }

    /// Easy / Rx / Beast: square tiles, the pick stays for next weeks.
    private var levels: some View {
        HStack(spacing: 8) {
            ForEach(ChallengeTier.allCases) { t in
                Button { tierRaw = t.rawValue } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.label).font(Theme.label(13)).opacity(0.9)
                        Text(t.note).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .selectableGradient(t.gradient, selected: t == tier, cornerRadius: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t.label): \(t.note)")
                .accessibilityAddTraits(t == tier ? .isSelected : [])
            }
        }
    }

    private func teaser(_ n: ChallengeNext) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next week · \(n.week)").font(Theme.label(11)).tracking(1.4).textCase(.uppercase).opacity(0.85)
            if n.memberWeek {
                Text("Member week: the vote decides").font(Theme.display(20))
            } else if let f = n.format, let m = n.minutes {
                Text("??? · \(f == .fortime ? "For time, \(m)′ cap" : "\(f.label) \(m)′") · \(n.moveCount ?? 0) moves").font(Theme.display(20))
            }
        }
        .foregroundStyle(n.memberWeek ? Theme.ink : .white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(n.memberWeek ? memberGradient : LinearGradient.wod(n.format?.kind ?? .forTime)))
        .accessibilityElement(children: .combine)
    }

    /// The next member week's vote: up to 3 approved suggestions, tap to vote; suggest yours under it.
    private var vote: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let v = live.room?.vote {
                Text("Vote · member week \(v.week) · ends \(v.endsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(Theme.label(11)).tracking(1.4).textCase(.uppercase).opacity(0.9)
                if v.finalists.isEmpty {
                    Text("No finalists yet. Suggest one: approved ones go to the vote.").font(Theme.label(14))
                }
                let total = max(1, v.finalists.reduce(0) { $0 + $1.votes })
                ForEach(v.finalists) { f in
                    Button { Task { await live.vote(f.id, api: model.api) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(f.name).font(Theme.label(15))
                                Text("· \(f.format.label) · by \(f.by.nickname)").font(Theme.label(12)).opacity(0.85).lineLimit(1)
                                Spacer(minLength: 4)
                                if f.mine { Image(systemName: "checkmark.circle.fill") }
                                Text("\(f.votes)").font(Theme.display(16)).monospacedDigit()
                            }
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.25))
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4).fill(Theme.lime).frame(width: g.size.width * CGFloat(f.votes) / CGFloat(total))
                                    }
                            }
                            .frame(height: 8)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(f.mine ? 0.32 : 0.2)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(f.name) by \(f.by.nickname), \(f.votes) votes\(f.mine ? ", your vote" : "")")
                }
            }
            Button { suggesting = true } label: {
                Label("Suggest a challenge", systemImage: "plus").font(Theme.label(15)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("challenge.suggest")
            if !live.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(live.suggestions) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(Theme.label(13)).lineLimit(1)
                                Text(status(s)).font(Theme.label(11)).opacity(0.85)
                            }
                            .padding(10).frame(width: 130, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
                            .contextMenu {
                                if s.week == nil {
                                    Button("Withdraw", systemImage: "trash", role: .destructive) { Task { await live.withdraw(s.id, api: model.api) } }
                                }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(voteGradient))
    }

    private func status(_ s: ChallengeSuggestion) -> String {
        if let w = s.week { return "★ Ran \(w)" }
        switch s.status {
        case .pending: return "⏳ In review"
        case .approved: return "✓ In the vote"
        case .rejected: return "✕ Not this time"
        }
    }

    private func history(_ past: [ChallengePast]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Past weeks").eyebrow()
            HStack(spacing: 8) {
                ForEach(past) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(p.week.suffix(3))).font(Theme.label(11)).opacity(0.8)
                        Text(p.rank.map { "#\($0)" } ?? "—").font(Theme.display(20)).monospacedDigit()
                        Text(p.name).font(Theme.label(10)).lineLimit(1).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.rank == nil ? Theme.card : Theme.cardStrong))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func row(_ e: ChallengeEntry, _ format: ChallengeFormat) -> some View {
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
            if let t = e.tier, t != .rx {
                Text(t.label.uppercased()).font(Theme.label(10)).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(t.gradient))
            }
            Spacer(minLength: 4)
            Text(Self.score(e, format)).font(Theme.display(20)).monospacedDigit()
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

/// After the timer: AMRAP / EMOM rounds + reps, Tabata reps, For time the finish time (or reps at the cap).
private struct ChallengeScoreSheet: View {
    let format: ChallengeFormat
    let minutes: Int
    let tier: ChallengeTier
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rounds = 0
    @State private var reps = 0
    @State private var finished = true
    @State private var min = 0
    @State private var sec = 0
    @State private var saving = false
    @State private var result: ChallengeScoreResult?

    private var seconds: Int? { format == .fortime && finished && min * 60 + sec > 0 ? min * 60 + sec : nil }
    private var empty: Bool { seconds == nil && rounds == 0 && reps == 0 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Your score").font(Theme.display(26))
                    Text(tier.label).font(Theme.label(12)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(tier.gradient))
                    Spacer()
                }
                switch format {
                case .amrap, .emom:
                    Stepper("\(format == .emom ? "Rounds done" : "Rounds"): \(rounds)", value: $rounds, in: 0...200).font(Theme.label(16))
                    repsField(format == .emom ? "Extra reps in the last round" : "Extra reps")
                case .tabata:
                    repsField("Total reps")
                case .fortime:
                    Picker("", selection: $finished) {
                        Text("Finished").tag(true)
                        Text("Hit the \(minutes)′ cap").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if finished {
                        HStack {
                            Text("Time").font(Theme.label(16))
                            Spacer()
                            Picker("Minutes", selection: $min) { ForEach(0...minutes, id: \.self) { Text("\($0)′").tag($0) } }
                            Picker("Seconds", selection: $sec) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d″", $0)).tag($0) } }
                        }
                    } else {
                        repsField("Reps done")
                    }
                }
                if let result {
                    Text(result.best ? "Saved: #\(result.rank) this week" : "Your best stays · #\(result.rank)")
                        .font(Theme.label(15)).foregroundStyle(Theme.lime)
                }
                Button(result == nil ? "SAVE SCORE" : "DONE") {
                    if result != nil { return dismiss() }
                    saving = true
                    Task {
                        result = await LiveRoom.shared.sendScore(rounds: rounds, reps: reps, seconds: seconds, tier: tier, api: model.api)
                        saving = false
                    }
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(saving || empty || (seconds ?? 0) > minutes * 60)
                ErrorText(message: LiveRoom.shared.error)
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            // Standard ✕ top right (#823): was a plain white ✕ in the title row.
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    private func repsField(_ title: String) -> some View {
        HStack {
            Text(title).font(Theme.label(16))
            Spacer()
            TextField("0", value: $reps, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .font(Theme.display(22)).frame(width: 90)
                .onChange(of: reps) { _, v in reps = Swift.min(999, Swift.max(0, v)) }
        }
    }
}

/// Suggest a challenge (#748): name, format, time, 2–5 moves from the kit-free list. The Coach check runs on send;
/// the owner approves; members vote; the winner runs the last week of a month.
struct SuggestChallengeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var format = ChallengeFormat.amrap
    @State private var minutes = 12
    @State private var moves: [Move] = []
    @State private var saving = false
    @State private var sent = false
    private var live: LiveRoom { .shared }

    struct Move: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var reps: Int
    }

    private var valid: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 && (2...5).contains(moves.count) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Suggest a challenge").font(Theme.display(26))
                        Spacer()
                    }
                    if sent {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sent for review").font(Theme.display(22))
                            Text("Once approved it joins the member-week vote.").font(Theme.label(14))
                        }
                        .gradientCard(memberGradient, ink: Theme.ink)
                        Button("DONE") { dismiss() }.buttonStyle(LimeButtonStyle())
                    } else {
                        form
                    }
                }
                .padding(20)
            }
            .foregroundStyle(.white)
            .background(Theme.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                #if DEBUG
                if Demo.enabled, moves.isEmpty {
                    name = "Lemur Leap"
                    moves = [Move(name: "burpees", reps: 10), Move(name: "air squats", reps: 15), Move(name: "v-ups", reps: 10)]
                }
                #endif
            }
            // Standard ✕ top right (#823): was a plain white ✕ in the title row.
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    @ViewBuilder private var form: some View {
        TextField("Name", text: $name)
            .font(Theme.display(22))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .onChange(of: name) { _, v in if v.count > 32 { name = String(v.prefix(32)) } }
        Text("Format").eyebrow()
        HStack(spacing: 8) {
            ForEach(ChallengeFormat.allCases) { f in
                Button {
                    format = f
                    minutes = Swift.min(Swift.max(minutes, f.minuteRange.lowerBound), f.minuteRange.upperBound)
                    if f != .tabata { for i in moves.indices { moves[i].reps = Swift.min(moves[i].reps, f.maxReps) } }
                } label: {
                    Text(f.label).font(Theme.label(13)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .selectableGradient(LinearGradient.wod(f.kind), selected: f == format, cornerRadius: 14)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(f == format ? .isSelected : [])
            }
        }
        if format == .tabata {
            Text("8 × 20″ on / 10″ off per move: \(Swift.max(2, moves.count) * 4)′").font(Theme.label(14)).foregroundStyle(Theme.muted)
        } else {
            Stepper("\(format == .fortime ? "Cap" : "Time"): \(minutes)′", value: $minutes, in: format.minuteRange).font(Theme.label(16))
        }
        Text("Moves · 2 to 5").eyebrow()
        ForEach($moves) { $m in
            HStack(spacing: 10) {
                if format != .tabata {
                    Stepper(value: $m.reps, in: 1...format.maxReps) {
                        Text("\(m.reps) \(m.name)").font(Theme.label(15))
                    }
                } else {
                    Text(m.name).font(Theme.label(15))
                    Spacer()
                }
                Button { moves.removeAll { $0.id == m.id } } label: { Image(systemName: "minus.circle.fill").font(.title3) }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel("Remove \(m.name)")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        }
        if moves.count < 5 {
            Menu {
                ForEach(live.moves.filter { n in !moves.contains { $0.name == n } }, id: \.self) { n in
                    Button(n) { moves.append(Move(name: n, reps: Swift.min(10, format.maxReps == 0 ? 10 : format.maxReps))) }
                }
            } label: {
                Label("Add a move", systemImage: "plus").font(Theme.label(15)).foregroundStyle(Theme.lime)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lime, lineWidth: 2))
            }
            .disabled(live.moves.isEmpty)
        }
        HStack(spacing: 8) {
            Text("Coach checks moves and reps").font(Theme.label(11)).padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x2A6DF4)))
            Text("Then approved, then voted").font(Theme.label(11)).padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xE8306A)))
        }
        ErrorText(message: live.error)
        Button("SEND FOR REVIEW") {
            saving = true
            Task {
                let list = moves.map { format == .tabata ? $0.name : "\($0.reps) \($0.name)" }
                let mins = format == .tabata ? moves.count * 4 : minutes
                sent = await live.suggest(name: name.trimmingCharacters(in: .whitespaces), format: format, minutes: mins, moves: list, api: model.api)
                saving = false
            }
        }
        .buttonStyle(LimeButtonStyle())
        .disabled(saving || !valid)
    }
}
