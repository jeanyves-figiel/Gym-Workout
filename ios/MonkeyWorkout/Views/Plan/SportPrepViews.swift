import SwiftUI
import WorkoutEngine

// Sport prep on planned sport days (#523, design A from `climb-row/sport-proposals.png`): one bar under Next up opens
// a page like climbing's Wall session: Before (no-kit warm-up), the sport (log or track), After (stretch).

/// Train, under Next up: shown only when today is a planned sport day (climbing keeps its Wall session).
struct SportPrepBar: View {
    @Environment(AppModel.self) private var model

    /// Today's sport (#658), dated days first; climbing has its Wall session instead.
    private var todaySport: Sport? {
        guard let sport = model.profile?.sport(onWeekday: model.todayWeekday, key: PlanCalendar.key(Date(), model.planCalendar)),
              SportPrep.family(sport) != nil else { return nil }
        return sport
    }

    var body: some View {
        if let sport = todaySport, let before = SportPrep.before(sport), let after = SportPrep.after(sport) {
            NavigationLink {
                SportPrepPage(sport: sport)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: sport.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(sport.label) prep").font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("Warm-up \(before.session.estMin) min · cool-down \(after.session.estMin) min")
                            .font(Theme.label(11)).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.heavy))
                }
                .foregroundStyle(.white)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(sport.gradient))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Warm-up before and stretch after \(sport.label.lowercased())")
        }
    }
}

/// Before, the sport, After as stacked bands; each part starts on its own.
struct SportPrepPage: View {
    let sport: Sport

    @State private var logging: SportLog?
    @State private var around = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(sport.label) prep").font(Theme.display(34))
                Text("Today · \(sport.label.lowercased()) day").eyebrow()
                if let before = SportPrep.before(sport) {
                    NavigationLink(value: before.sessionId) {
                        band("Before", detail: preview(before), symbol: "flame.fill", minutes: before.session.estMin,
                             gradient: WorkoutEngine.Category.warmup.gradient, ink: Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
                Button { logging = SportLog(sport: sport, start: Date()) } label: {
                    band(sport.label, detail: sport.watchTrackable ? "Track live or log it" : "Log it", symbol: sport.symbol,
                         minutes: nil, gradient: sport.gradient, ink: .white)
                }
                .buttonStyle(.plain)
                if let after = SportPrep.after(sport) {
                    NavigationLink(value: after.sessionId) {
                        band("After", detail: preview(after), symbol: "snowflake", minutes: after.session.estMin,
                             gradient: WorkoutEngine.Category.cardio.gradient, ink: Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
                if let before = SportPrep.before(sport) {
                    // Opens the warm-up's page, where Start workout is: the label says so.
                    NavigationLink(value: before.sessionId) {
                        Label("See warm-up", systemImage: "list.bullet").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LimeButtonStyle())
                    .padding(.top, 6)
                }
                AroundSportLink(sport: sport) { around = true }.padding(.top, 6)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $logging) { LogSportView(initial: $0, picked: true, live: sport.watchTrackable) }
        .sheet(isPresented: $around) { AroundSportView(initial: sport) }
    }

    /// First few exercises: "Leg swings · Hip CARs · Knee-to-wall".
    private func preview(_ t: WorkoutTemplate) -> String {
        t.items.prefix(3).map { Exercise.find($0.exerciseId)?.name ?? $0.exerciseId }.joined(separator: " · ")
    }

    private func band(_ title: String, detail: String, symbol: String, minutes: Int?, gradient: LinearGradient, ink: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(18))
                Text(detail).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let minutes {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    // ′ in the number's own font: a small label-font ′ read as a clipped comma, "10," (#823).
                    Text("\(minutes)′").font(Theme.display(26)).monospacedDigit()
                }
            } else {
                Image(systemName: "plus").font(.headline.weight(.heavy))
            }
        }
        .foregroundStyle(ink)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient))
    }
}
