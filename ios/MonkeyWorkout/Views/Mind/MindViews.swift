import SwiftUI
import WorkoutEngine

// Mental health & relaxation (#834, designs A + B + C from `mental-health/proposals.png`): A, the check-in card on
// Train; B, Explore → Ready-made → Calm; C, the Mind score card and page. Sessions play in `BreathingPlayer`.

extension Breath {
    var gradient: LinearGradient {
        LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var ink: Color { lightGradient ? Theme.ink : .white }
}

/// Device prefs for the Train card.
enum MindPrefs {
    /// false = no check-in card on Train (Explore → Calm switch).
    static let onTrainKey = "mindOnTrain"
    /// Card closes, "<day number>:<closes>" like the daily Coach pick: closed today or three times = not shown.
    static let closesKey = "mindCardCloses"

    static let gradient = LinearGradient(colors: [Color(hex: 0xFF3D9A), Color(hex: 0x7A2CFF), Color(hex: 0x2E8BFF)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let scoreGradient = LinearGradient(colors: [Color(hex: 0x3B3F8F), Color(hex: 0x7A2CFF)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: A · Check-in on Train

/// Under the Daily row. No check-in today: mood squares and what it is about. Checked in: the Mind score tile (→ page)
/// and Coach's breathing pick (→ player). ✕ hides it for today; the third ✕ stops it (Explore → Calm brings it back).
struct MindTrainCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(MindPrefs.onTrainKey) private var onTrain = true
    @AppStorage(MindPrefs.closesKey) private var closes = ""
    @State private var playing: Breath?

    var body: some View {
        let store = MindStore.shared
        if onTrain && RoutinePrefs.coachOffers(closes, today: today) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mind").eyebrow()
                if store.checkIn() == nil {
                    MindCheckInCard(close: close)
                } else {
                    checkedIn
                }
            }
            .fullScreenCover(item: $playing) { BreathingPlayer(breath: $0) }
            .onAppear { model.recordMindScore() }
        }
    }

    private var checkedIn: some View {
        let pick = model.mindPick
        return HStack(spacing: 8) {
            NavigationLink { MindView() } label: {
                MindScoreTile(score: model.mindScore)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mind.score")
            Button { playing = pick.breath } label: {
                BreathTile(breath: pick.breath, eyebrow: "Coach pick · \(pick.why)", minutes: pick.breath.defaultMinutes)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mind.pick")
        }
    }

    private var today: Int { RoutinePrefs.dayNumber(Date(), calendar: model.planCalendar) }

    private func close() {
        let before = closes
        let next = RoutinePrefs.closingCoach(closes, today: today)
        withAnimation(.snappy) { closes = next }
        let stopped = !RoutinePrefs.coachOffers(next, today: today + 1)
        UndoCloseCenter.shared.deleted(stopped ? "Check-in card stopped" : "Check-in hidden for today",
                                       detail: "Explore → Calm brings it back", symbol: "eye.slash.fill") {
            UserDefaults.standard.set(before, forKey: MindPrefs.closesKey)
        }
    }
}

/// Five mood squares, then what it is about and Save. Saved to the device and Apple Health (State of Mind).
struct MindCheckInCard: View {
    @Environment(AppModel.self) private var model
    var close: (() -> Void)?
    var onSaved: (() -> Void)?
    @State private var mood: Feel?
    @State private var feelings: [MindFeeling] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoutineIcon(symbol: "sun.horizon.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How do you feel?").font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(Theme.label(10)).tracking(1.1).textCase(.uppercase).opacity(0.9)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: close == nil ? 0 : 36)
            }
            HStack(spacing: 6) {
                ForEach(Feel.allCases, id: \.self) { f in moodSquare(f) }
            }
            .sensoryFeedback(.selection, trigger: mood)
            if mood != nil {
                FlowLayout(spacing: 6) {
                    ForEach(MindFeeling.allCases) { f in
                        SelectChip(title: f.label, on: feelings.contains(f), offFill: AnyShapeStyle(.black.opacity(0.25)),
                                   offInk: .white, size: 12, height: 30, fills: false) {
                            if let i = feelings.firstIndex(of: f) { feelings.remove(at: i) } else { feelings.append(f) }
                        }
                    }
                }
                Button(action: save) {
                    Label("Save check-in", systemImage: "checkmark")
                        .font(Theme.label(14)).foregroundStyle(Color(hex: 0x7A2CFF))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mind.save")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MindPrefs.gradient))
        .overlay(alignment: .topTrailing) {
            if let close { CardClose(label: "Not today", action: close).accessibilityIdentifier("mind.close") }
        }
    }

    private var subtitle: String {
        let hour = model.planCalendar.component(.hour, from: Date())
        return (hour < 12 ? "Morning check-in" : "Check-in") + " · 10 sec · saved to Health"
    }

    private func moodSquare(_ f: Feel) -> some View {
        let on = mood == f
        return Button {
            withAnimation(.snappy) { mood = f }
        } label: {
            VStack(spacing: 3) {
                Text(f.emoji).font(.system(size: 24))
                Text(f.label).font(Theme.label(9)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(on ? Color(hex: 0x7A2CFF) : .white)
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.25))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f.label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("mind.mood.\(f.rawValue)")
    }

    private func save() {
        guard let mood else { return }
        Haptics.success()
        withAnimation(.snappy) { model.checkIn(mood: mood.rawValue, feelings: feelings) }
        onSaved?()
    }
}

/// Square-ish tile: Mind score, its level and the last 7 days as bars.
struct MindScoreTile: View {
    let score: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                RoutineIcon(symbol: "brain.head.profile", size: 30)
                Spacer(minLength: 4)
                Text(score.map { "\($0)" } ?? "–").font(Theme.display(30)).monospacedDigit()
            }
            Text("Mind · \(score.map { MindScore.Level.of($0).title } ?? "No data")")
                .font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
            MindWeekBars(height: 22, labels: false)
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MindPrefs.scoreGradient))
        .contentShape(Rectangle())
    }
}

/// One breathing session on a gradient tile.
struct BreathTile: View {
    let breath: Breath
    var eyebrow: String?
    var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                RoutineIcon(symbol: breath.symbol, size: 30)
                Spacer(minLength: 4)
                Image(systemName: "play.fill").font(.system(size: 18, weight: .heavy))
            }
            Spacer(minLength: 0)
            if let eyebrow {
                Text(eyebrow).font(Theme.label(9)).tracking(0.8).textCase(.uppercase).opacity(0.9)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(breath.label).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(breath.purpose) · \(minutes) min").font(Theme.label(10)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(breath.ink)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(breath.gradient))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(breath.label), \(breath.purpose), \(minutes) minutes")
    }
}

/// Last 7 days of Mind scores, today last; a day with no score is a stub.
struct MindWeekBars: View {
    var height: CGFloat = 46
    var labels = true

    var body: some View {
        let week = MindStore.shared.week()
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(week, id: \.day) { d in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(d.score == nil ? 0.2 : (d.score ?? 0) < 55 ? 0.45 : 0.9))
                        .frame(height: max(3, height * CGFloat(d.score ?? 6) / 100))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)
            if labels {
                HStack(spacing: 4) {
                    ForEach(week, id: \.day) { d in
                        Text(d.day.formatted(.dateTime.weekday(.narrow))).font(Theme.label(9)).opacity(0.8).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 7 days: " + week.map { $0.score.map { "\($0)" } ?? "none" }.joined(separator: ", "))
    }
}

// MARK: B · Explore → Calm

struct CalmLibrarySection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(MindPrefs.onTrainKey) private var onTrain = true
    @AppStorage(MindPrefs.closesKey) private var closes = ""
    @State private var playing: Breath?

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            NavigationLink { MindView() } label: { MindScoreCard(score: model.mindScore) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calm.score")
            ForEach(Breath.Group.allCases, id: \.self) { g in
                VStack(alignment: .leading, spacing: 8) {
                    Text(g.label).eyebrow()
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Breath.allCases.filter { $0.group == g }) { b in
                            Button { playing = b } label: { BreathTile(breath: b, minutes: b.defaultMinutes) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("calm.\(b.rawValue)")
                        }
                    }
                }
            }
            Toggle(isOn: Binding(get: { onTrain && RoutinePrefs.coachOffers(closes, today: -1) }, set: { on in
                onTrain = on
                if on { closes = "" }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check-in on Train").font(Theme.label(15))
                    Text("Mood, Mind score and Coach's breathing pick under Daily").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.lime)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        }
        .fullScreenCover(item: $playing) { BreathingPlayer(breath: $0) }
        .onAppear { model.recordMindScore() }
    }

    private var hero: some View {
        HStack(spacing: 12) {
            RoutineIcon(symbol: "figure.mind.and.body", size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Calm").font(Theme.display(24))
                Text("Mindful minutes this week").font(Theme.label(10)).tracking(1).textCase(.uppercase).opacity(0.9)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Text("\(MindStore.shared.weekMinutes)").font(Theme.display(40)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Breath.bodyScan.gradient))
    }
}

// MARK: C · Mind score

/// Wide card: score, level, what it is made of and the 7-day bars. Opens the Mind page.
struct MindScoreCard: View {
    let score: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.map { "\(MindScore.Level.of($0).title) today" } ?? "Mind score").font(Theme.display(22))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(score == nil ? "Check in or connect Health" : "Mood · HRV · sleep · load")
                        .font(Theme.label(10)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                VStack(spacing: 0) {
                    Text(score.map { "\($0)" } ?? "–").font(Theme.display(32)).monospacedDigit()
                    Text("/100").font(Theme.label(10)).opacity(0.8)
                }
                .frame(width: 76, height: 70)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.25)))
            }
            MindWeekBars()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MindPrefs.scoreGradient))
        .contentShape(Rectangle())
    }
}

/// The Mind page: score card, HRV / sleep / mood tiles, Coach's pattern, Breathe now, the parts and the check-in.
struct MindView: View {
    @Environment(AppModel.self) private var model
    @State private var playing: Breath?
    @State private var checkingIn = false

    var body: some View {
        let inputs = model.mindInputs()
        let pick = model.mindPick
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MindScoreCard(score: model.mindScore)
                stats(inputs)
                coachTip
                Button { playing = pick.breath } label: {
                    BreathTile(breath: pick.breath, eyebrow: "Breathe now · \(pick.why)", minutes: pick.breath.defaultMinutes)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mind.breathe")
                if MindStore.shared.checkIn() == nil || checkingIn {
                    MindCheckInCard(onSaved: { checkingIn = false })
                } else {
                    Button { withAnimation(.snappy) { checkingIn = true } } label: {
                        Label("Check in again", systemImage: "sun.horizon.fill")
                            .font(Theme.label(14)).frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                parts(inputs)
                if let topic = HowItWorks.topic("mind") {
                    NavigationLink { HowItWorksTopicView(topic: topic) } label: {
                        Label("How the Mind score works", systemImage: "questionmark.circle.fill")
                            .font(Theme.label(14)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("Mood check-ins and sessions stay on this iPhone. With Health connected they are also saved there as State of Mind and mindful minutes. Not medical advice: if you feel low for weeks, talk to someone you trust or a doctor.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Mind")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { BreathingPlayer(breath: $0) }
        .onAppear { model.recordMindScore() }
    }

    private func stats(_ i: MindScore.Inputs) -> some View {
        let mood = MindScore.averageMood(lastWeekCheckIns, calendar: model.planCalendar)
        let hrvDelta = i.hrv.flatMap { h in i.hrvBaseline.map { Int((h - $0).rounded()) } }
        return HStack(spacing: 8) {
            stat(i.hrv.map { "\(Int($0.rounded())) ms" } ?? "–",
                 hrvDelta.map { "HRV \($0 >= 0 ? "+" : "")\($0)" } ?? "HRV")
            stat(i.sleepHours.map(Self.hours) ?? "–", "Sleep")
            stat(mood.map { Feel(rawValue: Int($0.rounded()))?.emoji ?? "–" } ?? "–", "Mood 7d")
        }
    }

    private var lastWeekCheckIns: [MindCheckIn] {
        let since = Date().addingTimeInterval(-7 * 86_400)
        return MindStore.shared.saved.checkIns.filter { $0.date >= since }
    }

    static func hours(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60)h\(String(format: "%02d", m % 60))"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.label(10)).foregroundStyle(Theme.muted).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }

    private var coachTip: some View {
        HStack(alignment: .top, spacing: 10) {
            MonkeyFace(mood: .happy, scale: 0.36)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
                .accessibilityHidden(true)
            Text(model.mindPattern ?? "Check in for \(MindScore.patternMin) mornings and Coach starts spotting what lifts your mood and what drags it.")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    private func parts(_ i: MindScore.Inputs) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What makes today's score").eyebrow()
            ForEach(MindScore.parts(i), id: \.name) { p in
                HStack(spacing: 10) {
                    Text(p.name).font(Theme.label(13)).frame(width: 52, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.card)
                            Capsule().fill(MindPrefs.gradient).frame(width: max(6, g.size.width * p.points))
                        }
                    }
                    .frame(height: 10)
                    Text("\(Int((p.points * 100).rounded()))").font(Theme.label(12)).monospacedDigit().frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(p.name) \(Int((p.points * 100).rounded())) of 100")
            }
            if i.calmMinutes > 0 {
                Text("+\(min(MindScore.calmBonusMax, i.calmMinutes)) for \(i.calmMinutes) calm min today").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}
