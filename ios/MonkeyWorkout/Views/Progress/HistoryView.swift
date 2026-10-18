import SwiftUI
import WorkoutEngine

// History page (#442, design C from `history-page/proposal-c.png`): every session in one timeline
// (gym workouts, climbs, other sports and Hyrox), totals, search and a sport filter.
// Progress shows a Recent sessions strip with See all; the History card and section chip open this page.

/// One past session of any kind.
enum HistoryItem: Identifiable, Equatable {
    case gym(WorkoutRecord)
    case climb(ClimbEntry)
    case sport(SportEntry)

    var id: UUID {
        switch self {
        case .gym(let r): r.id
        case .climb(let c): c.id
        case .sport(let s): s.id
        }
    }

    var start: Date {
        switch self {
        case .gym(let r): r.startedAt
        case .climb(let c): c.start
        case .sport(let s): s.start
        }
    }

    var minutes: Int {
        switch self {
        case .gym(let r): r.durationSec / 60
        case .climb(let c): c.minutes
        case .sport(let s): s.minutes
        }
    }

    var filter: HistoryFilter {
        switch self {
        case .gym: .gym
        case .climb: .sport(.climbing)
        case .sport(let s): .sport(s.sport)
        }
    }

    var title: String {
        switch self {
        case .gym(let r): r.title
        case .climb(let c): c.kind?.label ?? "Climbing"
        case .sport(let s): s.sport.label
        }
    }

    var subtitle: String {
        switch self {
        case .gym(let r):
            var parts = ["\(r.totalSets) sets"]
            if r.volumeKg > 0 { parts.append(Format.volume(r.volumeKg)) }
            if let hr = r.avgHeartRate { parts.append("\(Int(hr)) bpm") }
            return parts.joined(separator: " · ")
        case .climb(let c):
            return [c.topGrade.map { "top \($0)" }, c.detail, c.effort.map { "effort \($0)" }, c.source == "MonkeyWorkout" ? nil : c.source]
                .compactMap { $0 }.joined(separator: " · ")
        case .sport(let s):
            let stats = s.statsText
            return [stats.isEmpty ? nil : stats, s.effort.map { "effort \($0)" }, s.source == "MonkeyWorkout" ? nil : s.source]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }

    var symbol: String {
        switch self {
        case .gym: "dumbbell.fill"
        case .climb(let c): c.kind?.symbol ?? Sport.climbing.symbol
        case .sport(let s): s.sport.symbol
        }
    }

    /// Lower-cased words the search looks in: title, sport, exercises, grade, source.
    var searchText: String {
        var words = [title, subtitle]
        switch self {
        case .gym(let r):
            words.append("gym workout \(r.focus.rawValue)")
            words += r.exercises.map { Exercise.find($0.exerciseId)?.name ?? $0.exerciseId }
        case .climb(let c):
            words += ["climbing climb", c.source, c.kind?.rawValue ?? ""]
        case .sport(let s):
            words += [s.sport.rawValue, s.source]
        }
        return words.joined(separator: " ").lowercased()
    }
}

/// Sport filter chip on the History page.
enum HistoryFilter: Hashable, Identifiable {
    case all, gym, sport(Sport)

    var id: String {
        switch self {
        case .all: "all"
        case .gym: "gym"
        case .sport(let s): s.rawValue
        }
    }

    var label: String {
        switch self {
        case .all: "All"
        case .gym: "Gym"
        case .sport(let s): s.short
        }
    }

    var symbol: String? {
        switch self {
        case .all: nil
        case .gym: "dumbbell.fill"
        case .sport(let s): s.symbol
        }
    }

    var colors: [Color] {
        switch self {
        case .all: [Theme.lime, Theme.lime]
        case .gym: ProgressSection.training.colors
        case .sport(let s): s.colors
        }
    }
}

enum History {
    /// Every session, newest first.
    static func items(records: [WorkoutRecord], climbs: [ClimbEntry], sports: [SportEntry]) -> [HistoryItem] {
        (records.map(HistoryItem.gym) + climbs.map(HistoryItem.climb) + sports.filter { $0.sport != .climbing }.map(HistoryItem.sport))
            .sorted { $0.start > $1.start }
    }

    /// All, then Gym, then each sport present, most sessions first.
    static func filters(_ items: [HistoryItem]) -> [HistoryFilter] {
        var counts: [HistoryFilter: Int] = [:]
        for i in items { counts[i.filter, default: 0] += 1 }
        let kinds = counts.keys.sorted { a, b in
            counts[a]! != counts[b]! ? counts[a]! > counts[b]! : a.label < b.label
        }
        let gym = kinds.filter { $0 == .gym }
        return [.all] + gym + kinds.filter { $0 != .gym }
    }

    /// Filtered by sport and search words (every word must match).
    static func filter(_ items: [HistoryItem], by filter: HistoryFilter, query: String) -> [HistoryItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return items.filter { i in
            (filter == .all || i.filter == filter) && words.allSatisfy { i.searchText.contains($0) }
        }
    }

    /// "1h40", "52′".
    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : String(format: "%02d", minutes % 60))" : "\(minutes)′"
    }
}

extension AppModel {
    /// Gym workouts, climbs and other sports for the History page and the Recent sessions strip.
    func historyItems(health: HealthManager) -> [HistoryItem] {
        History.items(records: history,
                      climbs: Climbs.merged(local: climbLogs, health: health.snapshot.recentClimbs,
                                            monkeyGrade: MonkeyGradeLink.shared.climbs(for: user?.id)),
                      sports: Sports.merged(local: sportLogs, health: health.snapshot.recentSports))
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var query = ""
    @State private var picked: HistoryFilter = .all
    @State private var sport: SportEntry?

    /// `initial`: the sport chip lit on opening (a sport widget, #444).
    init(initial: HistoryFilter = .all) { _picked = State(initialValue: initial) }

    var body: some View {
        let all = model.historyItems(health: health)
        let shown = History.filter(all, by: picked, query: query)
        let days = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.start) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if all.isEmpty {
                    empty
                } else {
                    chips(History.filters(all) + (picked == .all || History.filters(all).contains(picked) ? [] : [picked]))
                    totals(shown)
                    if shown.isEmpty {
                        Text(query.isEmpty ? "No \(picked.label.lowercased()) sessions yet." : "Nothing matches “\(query)”.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(days.keys.sorted(by: >), id: \.self) { day in
                        Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .eyebrow()
                            .padding(.top, 6)
                        ForEach(days[day] ?? []) { row($0) }
                    }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Sessions, exercises, places")
        .navigationTitle("History")
        .toolbarTitleDisplayMode(.inlineLarge)
        .sheet(item: $sport) { SportSessionSheet(entry: $0) }
        .sensoryFeedback(.selection, trigger: picked)
    }

    private var empty: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.lime)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.lime.opacity(0.12)))
            Text("Finish a session or log a sport and it shows up here with everything you did.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func chips(_ filters: [HistoryFilter]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { f in
                    let on = f == picked
                    Button { picked = f } label: {
                        HStack(spacing: 5) {
                            if let s = f.symbol { Image(systemName: s) }
                            Text(f.label)
                        }
                        .font(Theme.label(13))
                        .foregroundStyle(on && f == .all ? Theme.ink : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient(colors: f.colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Theme.card)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }

    private func totals(_ items: [HistoryItem]) -> some View {
        let minutes = items.reduce(0) { $0 + $1.minutes }
        let kinds = Set(items.map(\.filter)).count
        return HStack {
            total("\(items.count)", "sessions")
            total(minutes >= 60 ? "\(minutes / 60) h" : "\(minutes) min", "time")
            total("\(kinds)", kinds == 1 ? "sport" : "sports")
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(22))
            Text(label.uppercased()).font(Theme.label(10)).tracking(1.4).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func row(_ item: HistoryItem) -> some View {
        switch item {
        case .gym(let r):
            // Opens the session page, where Undo workout still lives.
            NavigationLink(value: r.id) { HistoryTile(item: item) }.buttonStyle(.plain)
        case .sport(let s):
            Button { sport = s } label: { HistoryTile(item: item) }.buttonStyle(.plain)
        case .climb(let c):
            // Logged here: long press deletes it (moved from Train's Recent climbs).
            HistoryTile(item: item)
                .contextMenu {
                    if c.local {
                        Button("Delete climb", systemImage: "trash", role: .destructive) { deleteClimb(c.id) }
                    }
                }
        }
    }
}

extension HistoryView {
    fileprivate func deleteClimb(_ id: UUID) {
        model.deleteClimb(id)
        Task {
            await health.deleteClimb(id)
            await health.refresh()
        }
    }
}

/// Gradient row: icon tile, title + stats, big duration right.
struct HistoryTile: View {
    let item: HistoryItem

    var body: some View {
        let colors = item.filter.colors
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.25)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(.headline, design: .rounded).weight(.heavy)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(History.duration(item.minutes)).font(Theme.display(20))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.start.formatted(date: .abbreviated, time: .omitted)), \(item.minutes) minutes")
    }
}

/// Progress: the last sessions as a swipe strip, See all opens History.
struct RecentSessionsStrip: View {
    let items: [HistoryItem]
    let seeAll: () -> Void
    @State private var sport: SportEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent sessions").eyebrow()
                Spacer()
                Button(action: seeAll) {
                    Text("See all \(items.count) ›").font(Theme.label(12)).foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items.prefix(8)) { item in
                        switch item {
                        case .gym(let r): NavigationLink(value: r.id) { card(item) }.buttonStyle(.plain)
                        case .sport(let s): Button { sport = s } label: { card(item) }.buttonStyle(.plain)
                        case .climb: Button(action: seeAll) { card(item) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
        .sheet(item: $sport) { SportSessionSheet(entry: $0) }
    }

    private func card(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.25)))
            Spacer(minLength: 0)
            Text(item.title).font(Theme.display(17)).lineLimit(1)
            Text(item.start.formatted(.relative(presentation: .named)) + " · " + History.duration(item.minutes))
                .font(Theme.label(11)).opacity(0.9).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 150, height: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: item.filter.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}
