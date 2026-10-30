import SwiftUI
import WorkoutEngine

// Mind in Progress (#852, mix of A + C from `mental-health/progress/proposals.png`): today's Body + Mind pair with
// Coach's call on top of the board (C), and the 28-day mood calendar on the Mind page (A). The Mind widget itself is
// `MindScoreCard` / the Mind part tile.

/// Body (auto-tune ready score → auto-tune sheet) and Mind (Mind score → Mind page) side by side, Coach's line below.
struct TodayBodyMindWidget: View {
    var openMind: () -> Void
    @Environment(AppModel.self) private var model
    @State private var tuning = false

    var body: some View {
        let verdict = model.tuneVerdict
        let mind = model.mindScore
        VStack(alignment: .leading, spacing: 8) {
            Text("Today").eyebrow()
            HStack(alignment: .top, spacing: 12) {
                Button { tuning = true } label: {
                    HubTile(symbol: "bolt.heart.fill", colors: [Theme.lime, Color(hex: 0x2EE6A0)], label: "Body", ink: Theme.ink) {
                        HubValue("\(verdict.score)")
                        HubNote("Ready · \(verdict.level.title)")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Body ready score \(verdict.score), \(verdict.level.title)")
                .accessibilityHint("Opens auto-tune")
                Button(action: openMind) {
                    HubTile(symbol: ProgressSection.mind.symbol, colors: ProgressSection.mind.colors, label: "Mind") {
                        HubValue(mind.map { "\($0)" } ?? "–")
                        HubNote(mind.map { MindScore.Level.of($0).title } ?? "Check in")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mind score \(mind.map { "\($0)" } ?? "not known")")
                .accessibilityHint("Opens Mind")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                MonkeyFace(mood: .happy, scale: 0.3)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.lime))
                    .accessibilityHidden(true)
                Text(MindScore.todayCall(body: verdict.score, mind: mind))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        }
        .sheet(isPresented: $tuning) { AutoTuneSheet().presentationDetents([.large]) }
        .onAppear { model.recordMindScore() }
    }
}

/// Last 4 weeks of check-ins, a square a day coloured by mood, today last. Days without one stay dark.
struct MindMoodCalendar: View {
    @Environment(AppModel.self) private var model

    static func color(_ mood: Int) -> Color {
        switch mood {
        case 1: Color(hex: 0x3B3F8F)
        case 2: Color(hex: 0x2E8BFF)
        case 3: Color(hex: 0x13C6A3)
        case 4: Theme.lime
        default: Color(hex: 0xFF3D9A)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let cal = model.planCalendar
        let today = cal.startOfDay(for: Date())
        let days = (0..<28).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let byDay = MindScore.lastPerDay(MindStore.shared.saved.checkIns, calendar: cal)
        let count = days.filter { byDay[$0] != nil }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mood · 4 weeks").eyebrow()
                Spacer()
                Text("\(count)/28 check-ins").font(Theme.label(11)).foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { d in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(byDay[d].map { Self.color($0.mood) } ?? Theme.cardStrong)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if d == today {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white, lineWidth: 2)
                            }
                        }
                }
            }
            HStack(spacing: 8) {
                ForEach(Feel.allCases, id: \.rawValue) { f in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(Self.color(f.rawValue)).frame(width: 9, height: 9)
                        Text(f.label).font(Theme.label(9)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mood over 4 weeks: \(count) check-ins")
    }
}
