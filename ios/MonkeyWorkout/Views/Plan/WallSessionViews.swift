import SwiftUI
import WorkoutEngine

// Wall session on climbing days (#366, design A + C): day-type tiles pick the parts, shown as stacked bands
// (Before, Climb or Hangboard, After) that each start on their own. Explore → Climbing lists the climbing exercises.

extension WallDay {
    var colors: [Color] {
        switch self {
        case .bouldering: ClimbKind.lead.colors
        case .hangboard: [Color(red: 1.0, green: 0.24, blue: 0.54), Color(red: 1.0, green: 0.48, blue: 0.24)]
        case .rope: [Color(red: 1.0, green: 0.48, blue: 0.24), Color(red: 1.0, green: 0.76, blue: 0.24)]
        case .rest: [Color(red: 0.18, green: 0.77, blue: 0.71), Color(red: 0.31, green: 0.70, blue: 1.0)]
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

extension WallPart {
    var title: String {
        switch self {
        case .before: "Before"
        case .climb: "Climb"
        case .session(let t): t.name
        case .after: "After"
        }
    }

    var symbol: String {
        switch self {
        case .before: "flame.fill"
        case .climb: "figure.climbing"
        case .session(let t): t.id == "wall-rest" ? "figure.mind.and.body" : "hand.raised.fill"
        case .after: "snowflake"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .before: WorkoutEngine.Category.warmup.gradient
        case .climb: ClimbKind.topRope.gradient
        case .session(let t): t.id == "wall-rest" ? WallDay.rest.gradient : WallDay.hangboard.gradient
        case .after: WorkoutEngine.Category.cardio.gradient
        }
    }

    /// Dark type on the light bands.
    var ink: Color {
        switch self {
        case .before, .after: Theme.ink
        default: .white
        }
    }
}

/// MonkeyGrade tag on climbing drills that share MonkeyGrade's name.
struct MonkeyGradeTag: View {
    static let color = Color(red: 0.70, green: 0.24, blue: 1.0)

    var body: some View {
        Text("MG")
            .font(Theme.label(9))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Self.color))
            .accessibilityLabel("Also in MonkeyGrade")
    }
}

/// Train → Climbing → Wall session: day types, parts and start on their own page.
struct WallSessionPage: View {
    let today: Bool
    let climbedToday: Bool

    @Environment(AppModel.self) private var model
    @State private var logging: ClimbLog?
    @State private var settings = false
    @State private var gate: ProGate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Wall session").font(Theme.display(34))
                WallSessionCard(today: today, climbedToday: climbedToday,
                                locked: ProStore.shared.locked, onGate: { gate = .climbing },
                                onLogClimb: { logging = ClimbLog(start: Date().addingTimeInterval(-90 * 60)) })
                AroundClimbingLink { ProStore.shared.run(.climbing, $gate) { settings = true } }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $logging) { LogClimbView(initial: $0) }
        .sheet(isPresented: $settings) { ClimbSettingsView() }
        .proPaywall($gate)
    }
}

/// Wall session page: pick the day type, then start each part.
struct WallSessionCard: View {
    /// Today is one of the member's climbing days.
    let today: Bool
    /// A climb is already logged or synced today.
    let climbedToday: Bool
    let locked: Bool
    let onGate: () -> Void
    let onLogClimb: () -> Void

    @AppStorage("wallDay") private var dayRaw = WallDay.bouldering.rawValue
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var model

    private var day: WallDay { WallDay(rawValue: dayRaw) ?? .bouldering }
    private var monkeyGradeConnected: Bool { MonkeyGradeLink.shared.isConnected(for: model.user?.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if today { Text("Today · climbing day").eyebrow() }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(WallDay.allCases) { d in tile(d) }
            }
            ForEach(day.parts) { part in band(part) }
            if let first = day.parts.first?.template {
                start(first) {
                    Label("Start \(first.name.lowercased())", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle())
            }
        }
    }

    private func tile(_ d: WallDay) -> some View {
        Button { dayRaw = d.rawValue } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: d.symbol).font(.system(size: 18, weight: .bold))
                Text(d.label).font(Theme.display(16))
                Text(d.summary).font(Theme.label(10)).opacity(0.85).lineLimit(2).multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .padding(10)
            .selectableGradient(d.gradient, selected: d == day, cornerRadius: 18, ring: Theme.lime)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(d == day ? .isSelected : [])
    }

    @ViewBuilder private func band(_ part: WallPart) -> some View {
        if let t = part.template {
            start(t) { bandLabel(part, detail: preview(t), minutes: "\(t.session.estMin)", done: false) }
                .buttonStyle(.plain)
        } else {
            Button { monkeyGradeConnected ? openMonkeyGrade() : onLogClimb() } label: {
                bandLabel(part, detail: climbedToday ? "Logged today" : monkeyGradeConnected ? "Log in MonkeyGrade · syncs back" : "Log your climb",
                          minutes: nil, done: climbedToday)
            }
            .buttonStyle(.plain)
        }
    }

    /// First few exercises of a part: "Finger & forearm ramp · Wrist & finger prep · Shoulder CARs".
    private func preview(_ t: WorkoutTemplate) -> String {
        t.items.prefix(3).map { Exercise.find($0.exerciseId)?.name ?? $0.exerciseId }.joined(separator: " · ")
    }

    private func bandLabel(_ part: WallPart, detail: String, minutes: String?, done: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark" : part.symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(part.title).font(Theme.display(18))
                Text(detail).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let minutes {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(minutes).font(Theme.display(26)).monospacedDigit()
                    Text("′").font(Theme.label(13))
                }
            } else {
                Image(systemName: monkeyGradeConnected && !done ? "arrow.up.right" : "plus").font(.headline.weight(.heavy))
            }
        }
        .foregroundStyle(part.ink)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(part.gradient))
    }

    /// Opens the part's session, or the Pro gate when locked.
    @ViewBuilder private func start<L: View>(_ t: WorkoutTemplate, @ViewBuilder label: () -> L) -> some View {
        if locked {
            Button(action: onGate, label: label)
        } else {
            NavigationLink(value: t.sessionId, label: label)
        }
    }

    private func openMonkeyGrade() {
        // Universal link: opens the MonkeyGrade app when installed, else the web app.
        if let url = URL(string: "https://app.monkeygrade.cloud/") { openURL(url) }
    }
}

// MARK: - Explore → Climbing

/// Navigation value for Explore → Climbing.
struct ClimbingRoute: Hashable {}

/// Explore → Categories card for the climbing exercises.
struct ClimbingCategoryCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.climbing")
                .font(.system(size: 30, weight: .bold))
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Climbing").font(Theme.display(24))
                Text("Wall warm-up, hangboard and cool-down. Same names as MonkeyGrade.")
                    .font(.footnote.weight(.medium)).opacity(0.85).multilineTextAlignment(.leading)
            }
            Spacer()
            Text("\(Climbing.ids.count)").font(Theme.display(22)).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ClimbKind.topRope.gradient))
    }
}

struct ClimbingCategoryView: View {
    @State private var open: ExerciseRef?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "figure.climbing").font(.system(size: 40, weight: .bold))
                    Text("Climbing").font(Theme.display(40))
                    Text("For the climbing gym: get the fingers ready, train them on the hangboard, bring them down after. Drills tagged MG have the same name in MonkeyGrade.")
                        .font(.body.weight(.medium)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(ClimbKind.topRope.gradient))

                ForEach(Climbing.Group.allCases) { g in
                    Text("\(g.label) · \(g.exercises.count)").eyebrow().padding(.top, 4)
                    ForEach(g.exercises) { e in row(e) }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { ref in NavigationStack { ExerciseDetailView(exerciseId: ref.exerciseId) } }
    }

    private func row(_ e: Exercise) -> some View {
        Button { open = ExerciseRef(exerciseId: e.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(e.name).font(.system(.headline, design: .rounded).weight(.heavy)).multilineTextAlignment(.leading)
                    if e.monkeyGradeSlug != nil { MonkeyGradeTag() }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
                }
                MuscleChips(primary: e.primary, secondary: e.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }
}
