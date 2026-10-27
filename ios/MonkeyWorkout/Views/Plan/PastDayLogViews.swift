import SwiftUI
import WorkoutEngine

/// What the past day's log sheet hands back (#800): a workout to log its sets, or a sport to log.
enum PastDayPick: Identifiable {
    case workout(Session)
    case sport(Sport?)

    var id: String {
        switch self {
        case let .workout(s): s.id
        case let .sport(s): "sport-\(s?.rawValue ?? "any")"
        }
    }
}

/// "What did you do?" (#800, design B): any workout can be logged on a past day, not only this week's plan.
/// Plan sessions on top, then Explore-style cards for my workouts, the library, a custom gym session, HIIT and sport.
/// Every workout is logged as an extra copy, so a planned one never turns done.
struct PastDayLogSheet: View {
    let day: Date
    let onPick: (PastDayPick) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var library: WorkoutLibraryView.Filter?
    @State private var picking = false
    /// Picked in the library or exercise picker; handed over once that sheet is down.
    @State private var pending: PastDayPick?

    private static let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Log on \(day.formatted(.dateTime.weekday(.abbreviated).day()))")
                        .font(Theme.label(12)).tracking(1.4).textCase(.uppercase).opacity(0.75)
                    Text("What did you do?").font(Theme.display(30))
                    let sessions = model.plan?.sessions ?? []
                    if !sessions.isEmpty {
                        heading("This week's plan")
                        ForEach(sessions) { s in planRow(s) }
                    }
                    heading("Any other workout")
                    LazyVGrid(columns: Self.columns, spacing: 10) {
                        Button { library = .mine } label: {
                            PastDayCategoryCard(title: "My workouts", detail: "your own", symbol: "star.fill",
                                                value: "\(model.myLibrary.count)", colors: [Color(hex: 0xA43DFF), Color(hex: 0xFF4FD8)])
                        }
                        Button { library = .all } label: {
                            PastDayCategoryCard(title: "Library", detail: "examples · members", symbol: "books.vertical.fill",
                                                value: "\(model.builtInLibrary.count + model.memberLibrary.count)",
                                                colors: [Color(hex: 0xFF5F8F), Color(hex: 0xFF9A5C)])
                        }
                        Button { picking = true } label: {
                            PastDayCategoryCard(title: Freestyle.title, detail: "pick the exercises", symbol: "plus",
                                                value: "∞", colors: [Theme.lime, Color(hex: 0x7BE07B)], ink: Theme.ink)
                        }
                        Menu {
                            Section("HIIT · 20 min") {
                                ForEach(HiitFormat.allCases) { f in
                                    Button(f.label, systemImage: f.symbol) { pick(.workout(hiit(f))) }
                                }
                            }
                        } label: {
                            PastDayCategoryCard(title: "HIIT", detail: "rounds · timer", symbol: "bolt.fill",
                                                value: "\(HiitFormat.allCases.count)", colors: [Color(hex: 0xFF3D6B), Color(hex: 0xFFB03D)])
                        }
                        Button { pick(.sport(nil)) } label: {
                            PastDayCategoryCard(title: "Sport", detail: "climb, run, ride…", symbol: "figure.run",
                                                value: "\(Sport.allCases.count)", colors: [Color(hex: 0x1FC8A0), Color(hex: 0x3AA0F0)])
                        }
                        Menu {
                            Button(Sport.swim.label, systemImage: "figure.pool.swim") { pick(.sport(.swim)) }
                            Button(Sport.crossfit.label, systemImage: "timer") { pick(.sport(.crossfit)) }
                            Button(Sport.boxing.label, systemImage: "figure.boxing") { pick(.sport(.boxing)) }
                        } label: {
                            PastDayCategoryCard(title: "Swim · WOD", detail: "pool, timers, rounds", symbol: "figure.pool.swim",
                                                value: "3", colors: [Color(hex: 0x2F80FF), Color(hex: 0x38D6FF)])
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(item: $library, onDismiss: flush) { f in
                NavigationStack {
                    WorkoutLibraryView(filter: f) { e in
                        pending = .workout(e.session)
                        library = nil
                    }
                    .toolbar { CloseToolbarItem { library = nil } }
                }
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $picking, onDismiss: flush) {
                ExercisePickerView(limit: 12) { picked in
                    if !picked.isEmpty { pending = .workout(Self.custom(picked)) }
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(Theme.label(12)).tracking(1.4).textCase(.uppercase).opacity(0.75).padding(.top, 8)
    }

    private func planRow(_ s: Session) -> some View {
        Button { pick(.workout(s)) } label: {
            HStack(spacing: 10) {
                Image(systemName: "dumbbell.fill").font(.system(size: 15, weight: .heavy))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.displayTitle).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(s.workMuscles(3).map(\.name).joined(separator: " · ")).font(Theme.label(10)).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(s.estMin)′").font(Theme.display(22)).monospacedDigit()
                    Text("LOG ›").font(Theme.label(9)).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3D5AFF), Color(hex: 0x8A4FFF)], startPoint: .leading, endPoint: .trailing)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Hands the pick over and closes; the day card opens the log sheet once this one is gone.
    private func pick(_ p: PastDayPick) {
        switch p {
        case let .workout(s): onPick(.workout(Self.extra(s)))
        case .sport: onPick(p)
        }
        dismiss()
    }

    private func flush() {
        guard let p = pending else { return }
        pending = nil
        pick(p)
    }

    /// A copy of a session with its own id, so logging it never marks the planned (or library) one done. Library,
    /// HIIT and custom gym sessions keep their id's prefix, so the log and History keep their own name.
    static func extra(_ s: Session) -> Session {
        var c = s
        let tag = "extra-\(UUID().uuidString)"
        c.id = s.isStandalone || Freestyle.isFreestyle(s.id) || s.hiit != nil ? "\(s.id)-\(tag)" : tag
        c.weekday = nil
        return c
    }

    private func hiit(_ f: HiitFormat) -> Session {
        let spec = HiitSpec(format: f, minutes: 20, kit: .gym)
        return Hiit.build(spec, gym: model.profile?.equipment ?? []).session(id: spec.sessionId)
    }

    /// A custom gym session (#800) of the picked exercises, in the order picked.
    static func custom(_ picked: [Exercise]) -> Session {
        var s = Freestyle.session()
        for e in picked { s.blocks = Freestyle.adding(e, to: s.blocks, sessionId: s.id).blocks }
        s.estMin = max(5, Int(s.blocks.reduce(0) { $0 + $1.estMin }.rounded()))
        return s
    }
}

/// One category card of the past day's log sheet (#800): Explore look, title over a detail line, icon tile
/// bottom left, big number bottom right.
private struct PastDayCategoryCard: View {
    let title: String
    let detail: String
    let symbol: String
    let value: String
    let colors: [Color]
    var ink: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(Theme.label(10)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            HStack(alignment: .bottom) {
                Image(systemName: symbol).font(.system(size: 14, weight: .heavy))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.18)))
                Spacer(minLength: 4)
                Text(value).font(Theme.display(30)).monospacedDigit().lineLimit(1)
            }
        }
        .foregroundStyle(ink)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
