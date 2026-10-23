import SwiftUI
import WorkoutEngine

// Around sport days (#658, was Around climbing days #47): one choice for every sport (design B from
// `around-sport/proposals.png`), and a sport's own page to differ (design A, sport strip on top). Climbing keeps its
// fields and Wall session; other sports save into their `SportPlan`. Changes save on their own and rebuild the week.

/// What's picked, saved on its own (#437). nil overrides = the default for all sports.
struct AroundPicks: Equatable {
    var before: ClimbNeighbour = .light, after: ClimbNeighbour = .light, sameDay: ClimbSameDay = .avoid
    var climbBefore: ClimbNeighbour?, climbAfter: ClimbNeighbour?, climbSameDay: ClimbSameDay?
    var addon = true
    var sports: [SportPlan] = []

    init() {}

    init(_ p: Profile) {
        before = p.sportBefore ?? .light
        after = p.sportAfter ?? .light
        sameDay = p.sportSameDay ?? .avoid
        climbBefore = p.climbBefore
        climbAfter = p.climbAfter
        climbSameDay = p.climbSameDay
        addon = p.climbDayAddon ?? true
        sports = p.otherSports
    }

    var defaults: SportDefaults { SportDefaults(before: before, after: after, sameDay: sameDay) }

    func plan(_ s: Sport) -> SportPlan { sports.first { $0.sport == s } ?? SportPlan(sport: s) }

    /// This sport's own choices (nil = default).
    func own(_ s: Sport) -> (before: ClimbNeighbour?, after: ClimbNeighbour?, sameDay: ClimbSameDay?) {
        if s == .climbing { return (climbBefore, climbAfter, climbSameDay) }
        let p = plan(s)
        return (p.before, p.after, p.sameDay)
    }

    func before(_ s: Sport) -> ClimbNeighbour { own(s).before ?? (s == .climbing ? before : defaults.dayBefore(s)) }
    func after(_ s: Sport) -> ClimbNeighbour { own(s).after ?? (s == .climbing ? after : defaults.dayAfter(s)) }
    func sameDay(_ s: Sport) -> ClimbSameDay { s.allowsSameDayGym ? own(s).sameDay ?? sameDay : .avoid }
    func differs(_ s: Sport) -> Bool {
        let o = own(s)
        return o.before != nil || o.after != nil || o.sameDay != nil
    }

    mutating func set(_ s: Sport, before v: ClimbNeighbour?) {
        if s == .climbing { climbBefore = v } else { edit(s) { $0.before = v } }
    }
    mutating func set(_ s: Sport, after v: ClimbNeighbour?) {
        if s == .climbing { climbAfter = v } else { edit(s) { $0.after = v } }
    }
    mutating func set(_ s: Sport, sameDay v: ClimbSameDay?) {
        if s == .climbing { climbSameDay = v } else { edit(s) { $0.sameDay = v } }
    }
    mutating func reset(_ s: Sport) {
        set(s, before: nil)
        set(s, after: nil)
        set(s, sameDay: nil)
    }

    private mutating func edit(_ s: Sport, _ change: (inout SportPlan) -> Void) {
        guard let i = sports.firstIndex(where: { $0.sport == s }) else { return }
        change(&sports[i])
    }

    @MainActor static func store(_ k: AroundPicks, model: AppModel) {
        guard var p = model.profile else { return }
        p.sportBefore = k.before == .light ? nil : k.before
        p.sportAfter = k.after == .light ? nil : k.after
        p.sportSameDay = k.sameDay == .avoid ? nil : k.sameDay
        p.climbBefore = k.climbBefore
        p.climbAfter = k.climbAfter
        p.climbSameDay = k.climbSameDay
        // Wall session (#366) is on by default; only "off" is stored.
        p.climbDayAddon = k.addon ? (p.climbDayAddon == true ? true : nil) : false
        // Only the around-day fields: days, season and event may have changed elsewhere meanwhile.
        p.sports = p.sports?.map { sp in
            guard let edited = k.sports.first(where: { $0.sport == sp.sport }) else { return sp }
            var out = sp
            out.before = edited.before
            out.after = edited.after
            out.sameDay = edited.sameDay
            return out
        }
        if p != model.profile {
            model.updateProfile(p)
        }
    }
}

/// Settings → Around sport days, the Wall session and Sport prep pages. `initial` opens that sport's page first.
struct AroundSportView: View {
    var initial: Sport? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picks = AroundPicks()
    @State private var path: [Sport] = []
    @State private var loaded = false

    /// Climbing (for climbers) first, then the member's other sports.
    private var sports: [Sport] {
        guard let p = model.profile else { return [] }
        return (Generator.isClimber(p) ? [.climbing] : []) + p.otherSports.map(\.sport)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Day before any sport").eyebrow()
                    ForEach(ClimbNeighbour.allCases) { o in
                        OptionCard(symbol: o.symbol, title: Self.label(o), blurb: Self.blurb(o, before: true), colors: o.colors,
                                   selected: picks.before == o) { picks.before = o }
                    }
                    Text("Day after any sport").eyebrow().padding(.top, 8)
                    ForEach(ClimbNeighbour.allCases) { o in
                        OptionCard(symbol: o.symbol, title: Self.label(o), blurb: Self.blurb(o, before: false), colors: o.colors,
                                   selected: picks.after == o) { picks.after = o }
                    }
                    Text("On sport days").eyebrow().padding(.top, 8)
                    ForEach(ClimbSameDay.allCases) { o in
                        OptionCard(symbol: o == .avoid ? "figure.mixed.cardio" : "dumbbell.fill",
                                   title: o == .avoid ? "Sport only" : "Gym allowed",
                                   blurb: o == .avoid ? "Gym sessions go on sport days only when the week has no room."
                                                      : "A gym session can share the day, e.g. gym in the morning, sport in the evening.",
                                   colors: o == .avoid ? ClimbKind.boulder.colors : ClimbKind.lead.colors,
                                   selected: picks.sameDay == o) { picks.sameDay = o }
                    }
                    Text("Your sports").eyebrow().padding(.top, 8)
                    if sports.isEmpty {
                        Text("Add a sport in Train → Edit plan or on a Calendar day; tap it here to plan it differently.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    }
                    ForEach(sports) { s in
                        NavigationLink(value: s) { SportRow(sport: s, detail: detail(s)) }
                            .buttonStyle(.plain)
                    }
                    Text("Changes save on their own and rebuild this week's plan around your sport days.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Around sport days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .navigationDestination(for: Sport.self) { s in
                AroundOneSportPage(sport: s, sports: sports, picks: $picks) { dismiss() }
            }
            .autoSave(loaded ? picks : nil, title: "Sport days", symbol: "figure.mixed.cardio",
                      detail: { _ in "This week's plan rebuilt" },
                      save: { [model] in AroundPicks.store($0, model: model) })
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded, let p = model.profile else { return }
            picks = AroundPicks(p)
            if let initial, sports.contains(initial) { path = [initial] }
            loaded = true
        }
    }

    /// "Default · legs spared", "Before: Strong upper body", "Rest after · kept for safety".
    private func detail(_ s: Sport) -> String {
        let own = picks.own(s)
        var parts: [String] = []
        if let b = own.before { parts.append("Before: \(s.aroundLabel(b))") }
        if let a = own.after { parts.append("After: \(s.aroundLabel(a))") }
        if let d = own.sameDay, s.allowsSameDayGym { parts.append(s.sameDayLabel(d)) }
        if s == .scubaDiving && own.after == nil { parts.append("Rest after · kept for safety") }
        if parts.isEmpty { return s.isLightLoad ? "Default" : "Default · \(s.loadLabel) spared" }
        return parts.joined(separator: " · ")
    }

    static func label(_ o: ClimbNeighbour) -> String {
        switch o {
        case .light: "Keep it light"
        case .strong: "Strong elsewhere"
        case .rest: "Rest"
        case .any: "No adjustment"
        }
    }

    static func blurb(_ o: ClimbNeighbour, before: Bool) -> String {
        switch o {
        case .light: before ? "Spare what the sport works: legs before a run, grip before climbing." : "Light on what the sport worked while you recover."
        case .strong: "Hard day on what the sport doesn't use."
        case .rest: "Keep this day free of gym sessions when the week allows."
        case .any: "Plan gym sessions as if there were no sport."
        }
    }
}

/// One sport's own choices (design A): sport strip to switch, cards worded from its load, Use default.
private struct AroundOneSportPage: View {
    @State var sport: Sport
    let sports: [Sport]
    @Binding var picks: AroundPicks
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if sports.count > 1 { strip }
                Text("Day before \(sport.activity)").eyebrow()
                ForEach(ClimbNeighbour.allCases) { o in
                    OptionCard(symbol: o.symbol, title: sport.aroundLabel(o), blurb: sport.aroundBlurb(o, before: true), colors: o.colors,
                               selected: picks.before(sport) == o) { picks.set(sport, before: o) }
                }
                Text("Day after \(sport.activity)").eyebrow().padding(.top, 8)
                if sport == .scubaDiving {
                    Text("Rest is advised the day after diving: hard exercise after a dive raises the risk of decompression sickness.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime)
                }
                ForEach(ClimbNeighbour.allCases) { o in
                    OptionCard(symbol: o.symbol, title: sport.aroundLabel(o), blurb: sport.aroundBlurb(o, before: false), colors: o.colors,
                               selected: picks.after(sport) == o) { picks.set(sport, after: o) }
                }
                Text("On \(sport.activity) days").eyebrow().padding(.top, 8)
                if sport.allowsSameDayGym {
                    ForEach(ClimbSameDay.allCases) { o in
                        OptionCard(symbol: o == .avoid ? sport.symbol : "dumbbell.fill", title: sport.sameDayLabel(o),
                                   blurb: sport.sameDayBlurb(o), colors: o == .avoid ? sport.colors : ClimbKind.lead.colors,
                                   selected: picks.sameDay(sport) == o) { picks.set(sport, sameDay: o) }
                    }
                } else {
                    Text("No gym on dive days.").font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime)
                }
                if sport == .climbing {
                    Toggle(isOn: $picks.addon) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wall session").font(Theme.display(18))
                            Text("Show warm-up, hangboard and after-climb sessions for the climbing gym on Train.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.lime)
                    .card(padding: 16)
                    .padding(.top, 8)
                }
                if picks.differs(sport) {
                    Button { withAnimation(.snappy) { picks.reset(sport) } } label: {
                        Label("Use the default for all sports", systemImage: "arrow.uturn.backward")
                    }
                    .font(Theme.label(14)).foregroundStyle(Theme.lime)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Around \(sport.activity)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CloseToolbarItem { close() } }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sports) { s in
                    Button { withAnimation(.snappy) { sport = s } } label: {
                        Label(s.short, systemImage: s.symbol)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(sport == s ? AnyShapeStyle(s.gradient) : AnyShapeStyle(Theme.cardStrong)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: sport == s ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(sport == s ? .isSelected : [])
                }
            }
            .padding(2)
        }
        .scrollClipDisabled()
    }
}

/// A sport in Your sports: gradient row, icon tile, what differs from the default.
private struct SportRow: View {
    let sport: Sport
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sport.symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(sport.label).font(Theme.display(18))
                Text(detail).font(.footnote.weight(.semibold)).opacity(0.9).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.subheadline.weight(.heavy))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(sport.gradient))
        .contentShape(Rectangle())
    }
}
