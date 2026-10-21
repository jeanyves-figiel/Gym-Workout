import Charts
import LiftSensor
import MapKit
import SwiftUI
import WorkoutEngine

// Other sports (#416, design A + B + C): Log sport grid, My sports in the training profile, Spotted in Health.

extension Sport {
    var symbol: String {
        switch self {
        case .climbing: "figure.climbing"
        case .snowboard: "figure.snowboarding"
        case .ski: "figure.skiing.downhill"
        case .crossCountrySki: "figure.skiing.crosscountry"
        case .mountainBike: "figure.outdoor.cycle"
        case .roadBike: "bicycle"
        case .run, .trailRun: "figure.run"
        case .hike: "figure.hiking"
        case .mountaineering: "mountain.2.fill"
        case .hyrox: "figure.cross.training"
        case .crossfit: "figure.highintensity.intervaltraining"
        case .swim: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .football: "figure.soccer"
        case .basketball: "figure.basketball"
        case .volleyball: "figure.volleyball"
        case .tennis: "figure.tennis"
        case .padel: "figure.racquetball"
        case .squash: "figure.squash"
        case .martialArts: "figure.martial.arts"
        case .boxing: "figure.boxing"
        case .surf: "figure.surfing"
        case .scubaDiving: "water.waves"
        case .skate: "figure.skating"
        case .golf: "figure.golf"
        case .yoga: "figure.yoga"
        case .other: "figure.mixed.cardio"
        }
    }

    private static let palette: [[UInt32]] = [
        [0xFF5E3A, 0xFFB03D], [0x00A3C4, 0x7DF9FF], [0x00B86B, 0x7DFFB0], [0xFF3D8B, 0xFF9A5E],
        [0x3D59FF, 0x00C7FF], [0x7D4DFF, 0xE040FB], [0xFFB800, 0xFF6B3D], [0x1EC8A5, 0x3D7BFF],
    ]

    var colors: [Color] {
        let i = Sport.allCases.firstIndex(of: self) ?? 0
        return Sport.palette[i % Sport.palette.count].map { Color(hex: $0) }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }

    /// The Watch records it live (#418; Hyrox has its race mode, #426). Same list as the Watch's `TrackedSport`.
    var watchTrackable: Bool {
        [.hyrox, .snowboard, .ski, .crossCountrySki, .mountainBike, .roadBike, .run, .trailRun, .hike, .mountaineering,
         .crossfit, .rowing, .football, .tennis, .padel, .surf, .skate, .other].contains(self)
    }

    /// What the Watch dashboard shows for it (#418 design B).
    var watchShows: String {
        switch self {
        case .hyrox: "Every run and station, split by itself"
        case .snowboard, .ski: "Speed · top speed · vertical · runs"
        case .hike, .mountaineering, .trailRun: "Ascent · km · summit"
        case .mountainBike, .roadBike, .run, .crossCountrySki: "km · speed · ascent"
        case .crossfit, .rowing: "Heart rate · kcal · laps"
        default: "Heart rate · kcal"
        }
    }

    /// Distance is worth asking for.
    var hasDistance: Bool {
        [.snowboard, .ski, .crossCountrySki, .mountainBike, .roadBike, .run, .trailRun, .hike, .mountaineering, .swim, .rowing].contains(self)
    }
}

extension SportEntry {
    var durationText: String { Climbs.duration(minutes) }

    /// "42 km · 1,120 m ↑ · 148 bpm".
    var statsText: String {
        var parts: [String] = []
        if let d = distanceKm { parts.append(d >= 10 ? "\(Int(d.rounded())) km" : String(format: "%.1f km", d)) }
        if let e = elevationM, e >= 10 { parts.append("\(Int(e.rounded()).formatted()) m ↑") }
        if let hr = avgHR { parts.append("\(Int(hr.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }
}

extension AppModel {
    /// The member's own sports: profile picks (climbing for climbers), then any they logged.
    var mySports: [Sport] {
        var mine = (profile?.otherSports ?? []).map(\.sport)
        if profile.map(Generator.isClimber) ?? false { mine.insert(.climbing, at: 0) }
        for log in sportLogs where !mine.contains(log.sport) { mine.append(log.sport) }
        return mine
    }

    /// The member's sports first (climbing for climbers), then every other one.
    var sportOrder: [Sport] {
        let mine = mySports
        return mine + Sport.allCases.filter { !mine.contains($0) }
    }
}

/// Under Start workout on Train (#462, design C from `other-sports/row-proposals.png`): one pill split in two, Log sport
/// (a past session) and Track live (on the Watch). Without a paired Watch that has MonkeyWorkout, only Log sport.
/// Build as I go (#490): `onFree` adds a first part that opens an empty workout in the player.
struct SportSplitPill: View {
    var onFree: (() -> Void)? = nil
    var freeResumes = false
    let onLog: () -> Void
    let onTrack: () -> Void
    @State private var link = WatchLink.shared

    var body: some View {
        // Equal tiles with gaps (#529): each part has its own rounded shape.
        HStack(spacing: 8) {
            if let onFree {
                half("Freestyle", detail: freeResumes ? "resume" : "add as you train",
                     symbol: "plus.square.on.square", ink: .white, action: onFree)
                    .background(LinearGradient.freestyle, in: tile)
                    .accessibilityHint("Start an empty workout and add exercises as you train")
                    .accessibilityIdentifier("train.freestyle")
            }
            half("Log sport", detail: "past session", symbol: "plus.circle.fill", ink: .white, action: onLog)
                .background(LinearGradient(colors: [Color(hex: 0xFF3D8B), Color(hex: 0xFF9A5E)], startPoint: .leading, endPoint: .trailing), in: tile)
                .accessibilityHint("Log a sport session you already did: snowboard, bike, Hyrox…")
            if link.ready {
                half("Track live", detail: "on your Watch", symbol: "applewatch.radiowaves.left.and.right", ink: Theme.ink, action: onTrack)
                    .background(Theme.lime, in: tile)
                    .accessibilityHint("Start a sport on your Apple Watch now")
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: link.ready)
    }

    private var tile: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    private func half(_ title: String, detail: String, symbol: String, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Icon over the title so three parts fit the card at any width (#526: the inline labels overflowed).
            // Content sits in an overlay so the label lengths never change a tile's size: all tiles same width and height.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .overlay {
                    VStack(spacing: 1) {
                        Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                        Text(title).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(detail).font(Theme.label(9)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 6)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log sport (design A; sheet layout B + card C, #435)

/// Sheet: what did you do (bold sport grid), when, how long, how hard. Climbing opens the climb log.
struct LogSportView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var log: SportLog
    @State private var picked: Bool
    @State private var climbing = false
    @State private var distanceText: String
    @State private var allSports = false
    @State private var showDistance: Bool
    @State private var showNotes: Bool
    @State private var closeGuard = CloseGuard()
    /// Track live on the Watch instead of logging a past session (#439, design A).
    @State private var live: Bool
    @State private var saver = false
    @State private var hyroxFormat: HyroxFormat = .full
    @State private var sent = false
    /// The Watch could not be woken: off the wrist, locked or out of reach (#462).
    @State private var noWatch = false
    @State private var link = WatchLink.shared
    private let initial: SportLog

    /// `restoring`: the session brought back by Undo (#285). `live`: opened from Track on Watch (#439).
    init(initial: SportLog, picked: Bool = false, restoring: SportLog? = nil, live: Bool = false) {
        self.initial = initial
        _live = State(initialValue: live && restoring == nil)
        _log = State(initialValue: restoring ?? initial)
        _picked = State(initialValue: picked || restoring != nil)
        _distanceText = State(initialValue: (restoring ?? initial).distanceKm.map { String(format: "%g", $0) } ?? "")
        _showDistance = State(initialValue: (restoring ?? initial).distanceKm != nil)
        _showNotes = State(initialValue: (restoring ?? initial).notes != nil)
    }

    private var notes: Binding<String> {
        Binding(get: { log.notes ?? "" }, set: { log.notes = $0.isEmpty ? nil : String($0.prefix(500)) })
    }

    var body: some View {
        if climbing {
            LogClimbView(initial: ClimbLog(start: log.start))
        } else {
            form
        }
    }

    private var form: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if picked && !allSports {
                        // Design B (#435): the grid folds into a strip, the details card sits right under it.
                        strip
                        if canTrack { modeSwitch }
                        if live && canTrack {
                            liveCard
                            if noWatch {
                                Label("Your Watch didn't answer. Put it on, unlock it, then tap Start again. Or start it on the Watch: Track a sport.",
                                      systemImage: "exclamationmark.applewatch")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime)
                            }
                            Text("Your Watch opens \(log.sport.short) and records it: heart rate, route, kcal. Keep it on your wrist; it saves to Apple Health and shows up here after.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        } else {
                            card
                            Text(health.connected && health.writeWorkouts
                                 ? "Also saved to Apple Health. Gym days around it are planned to spare \(log.sport.loadLabel)."
                                 : "Saved in MonkeyWorkout. Connect Apple Health in Progress → Body & Health to also save it there.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    } else {
                        SportPicker(sports: gridSports, mine: model.mySports, live: live,
                                    selected: picked ? log.sport : nil, pick: pick)
                    }
                }
                .padding(16)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: picked)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: allSports)
            }
            .scrollDismissesKeyboard(.interactively)
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if picked && !allSports {
                    Group {
                        if live && canTrack {
                            Button { startOnWatch() } label: {
                                Label(sent ? "Opening on your Watch…" : "Start on Watch", systemImage: "applewatch.radiowaves.left.and.right")
                            }
                            .disabled(sent)
                        } else {
                            Button { save() } label: {
                                Label("Save \(log.sport.short) · \(Climbs.duration(log.minutes)) · \(log.effort)", systemImage: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(LimeButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.bg.opacity(0.95).ignoresSafeArea())
                }
            }
            .navigationTitle(live && (canTrack || !picked) ? (picked ? "Track \(log.sport.short)" : "Track on Watch")
                             : picked ? "Log \(log.sport.short)" : "Log sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .undoableClose(closeGuard, offer: undoOffer)
    }

    /// Live mode lists the sports the Watch tracks; logging lists them all.
    private var gridSports: [Sport] {
        live ? model.sportOrder.filter(\.watchTrackable) : model.sportOrder
    }

    /// A paired Watch with MonkeyWorkout records this sport (#462: `WatchLink` redraws when the link comes up).
    private var canTrack: Bool { log.sport.watchTrackable && link.ready }

    /// Track live / Log past (#439, design A).
    private var modeSwitch: some View {
        HStack(spacing: 4) {
            ForEach([true, false], id: \.self) { on in
                Button { live = on } label: {
                    Label(on ? "Track live" : "Log past", systemImage: on ? "applewatch" : "pencil")
                        .font(Theme.label(14))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(live == on ? Theme.ink : .white)
                        .background(Capsule().fill(live == on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.clear)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(live == on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.card))
    }

    /// What the Watch shows for the picked sport, then battery (or the Hyrox race / sim).
    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On your Watch").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
                    Text(log.sport.label).font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(log.sport.watchShows).font(.subheadline.weight(.semibold)).opacity(0.9)
                }
                Spacer()
                Image(systemName: log.sport.symbol).font(.system(size: 40, weight: .bold))
            }
            if log.sport == .hyrox {
                Text("Race or sim").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
                chips([(HyroxFormat.full, "Full race"), (HyroxFormat.half(second: false), "First half"), (HyroxFormat.half(second: true), "Second half")],
                      selected: hyroxFormat) { hyroxFormat = $0 }
                Text("Steps record themselves; double tap or the big button moves on.").font(.footnote).opacity(0.9)
            } else {
                Text("Battery").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
                chips([(false, "Full GPS"), (true, "Saver")], selected: saver) { saver = $0 }
                Text(saver ? "GPS about once a minute: long days on one charge." : "GPS every few metres: best map and speed.")
                    .font(.footnote).opacity(0.9)
            }
        }
        .gradientCard(log.sport.gradient, padding: 18)
        .shadow(color: log.sport.colors[0].opacity(0.35), radius: 16, y: 8)
    }

    private func chips<T: Equatable>(_ options: [(T, String)], selected: T, pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].0 == selected
                Button { pick(options[i].0) } label: {
                    Text(options[i].1).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(on ? Theme.ink : .white)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.25))))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func startOnWatch() {
        noWatch = false
        sent = true
        let done: (Bool) -> Void = { ok in
            guard ok else {
                sent = false
                noWatch = true
                return
            }
            closeGuard.done()
            dismiss()
        }
        if log.sport == .hyrox {
            WatchSync.shared.startHyrox(hyroxFormat, done: done)
        } else {
            WatchSync.shared.startSport(log.sport, saver: saver, done: done)
        }
    }

    private func pick(_ s: Sport) {
        if s == .climbing {
            // Switching to the climb log isn't closing: no "… closed" Undo bar over it (#460).
            closeGuard.done()
            climbing = true
        } else {
            log.sport = s
            picked = true
            allSports = false
        }
    }

    private var strip: some View {
        SportStrip(selected: log.sport, sports: gridSports, pick: pick) { allSports = true }
    }

    /// Design C card (#435): the sport's own colours hold when, how long and how hard.
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTimes(start: $log.start, minutes: log.minutes)
            HStack {
                Text(log.sport.label).font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Image(systemName: log.sport.symbol).font(.system(size: 40, weight: .bold))
            }

            CardDuration(minutes: CardTimes.endAnchored($log.minutes, start: $log.start), max: 16 * 60)

            Text("How hard · \(log.effort) \(ClimbLog.effortLabel(log.effort))")
                .font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
            FeelChips(effort: $log.effort)

            if log.sport.hasDistance {
                if showDistance {
                    HStack {
                        TextField("0", text: $distanceText).keyboardType(.decimalPad).font(Theme.display(28))
                            .onChange(of: distanceText) { _, t in
                                log.distanceKm = Double(t.replacingOccurrences(of: ",", with: ".")).map { min(max($0, 0), 1000) }
                            }
                        Text("km").font(Theme.label(15)).opacity(0.8)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.25)))
                }
            }
            if showNotes {
                TextField("Where, conditions, how legs felt", text: notes, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.25)))
            }
            HStack(spacing: 8) {
                if log.sport.hasDistance && !showDistance { AddChip(title: "Distance") { showDistance = true } }
                if !showNotes { AddChip(title: "Notes") { showNotes = true } }
            }
        }
        .gradientCard(log.sport.gradient, padding: 18)
        .shadow(color: log.sport.colors[0].opacity(0.35), radius: 16, y: 8)
    }

    private var undoOffer: UndoOffer? {
        guard picked, !(live && canTrack), log != initial else { return nil }
        let kept = log
        let original = initial
        return UndoOffer(title: "\(kept.sport.short) closed", detail: undoDetail(kept.sport.label, Climbs.duration(kept.minutes)),
                         symbol: kept.sport.symbol, colors: kept.sport.colors) {
            AnyView(LogSportView(initial: original, restoring: kept))
        }
    }

    private func save() {
        let entry = log
        model.saveSport(entry)
        let weight = model.body.weightKg ?? health.snapshot.weightKg
        Task {
            if await health.saveSport(entry, kcal: Sports.kcal(entry, weightKg: weight)) {
                await health.refresh()
            }
        }
        closeGuard.done()
        dismiss()
    }
}

/// The picked sport first, then the member's order; "All" opens the full grid again. Shared by Log sport and Log climb (#460).
struct SportStrip: View {
    let selected: Sport
    let sports: [Sport]
    let pick: (Sport) -> Void
    let all: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([selected] + sports.filter { $0 != selected }.prefix(7)) { s in
                    SportTile(sport: s, selected: selected == s) { pick(s) }
                        .frame(width: 74)
                        .opacity(selected == s ? 1 : 0.55)
                }
                Button(action: all) {
                    VStack(spacing: 6) {
                        Image(systemName: "square.grid.3x3.fill").font(.system(size: 22, weight: .bold)).frame(height: 28)
                        Text("All").font(Theme.label(12))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All sports")
            }
            .padding(.vertical, 3)
        }
        .scrollClipDisabled()
    }
}

/// Day, Started → Ended inside a log card: the end is the start plus the duration, and editing it moves the start.
struct CardTimes: View {
    @Binding var start: Date
    let minutes: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            DatePicker("Day", selection: $start, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
            labelled("Started") {
                DatePicker("Started", selection: $start, in: ...Date(), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Image(systemName: "arrow.right").font(.system(size: 13, weight: .heavy)).padding(.bottom, 10)
            labelled("Ended") {
                DatePicker("Ended", selection: end, in: ...Date(), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
        .colorScheme(.dark)
    }

    /// Picking an end time keeps the duration and moves the start.
    private var end: Binding<Date> {
        Binding(get: { start.addingTimeInterval(Double(minutes) * 60) },
                set: { start = $0.addingTimeInterval(-Double(minutes) * 60) })
    }

    private func labelled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.label(9)).tracking(1).textCase(.uppercase).opacity(0.85)
            content()
        }
    }

    /// Duration binding that keeps the end where it is: − / + moves the start, so "finished now" stays now.
    static func endAnchored(_ minutes: Binding<Int>, start: Binding<Date>) -> Binding<Int> {
        Binding(get: { minutes.wrappedValue },
                set: { m in
                    start.wrappedValue = start.wrappedValue.addingTimeInterval(Double(minutes.wrappedValue - m) * 60)
                    minutes.wrappedValue = m
                })
    }
}

/// Duration stepper inside a sport-coloured log card (#435), 15 min steps.
struct CardDuration: View {
    @Binding var minutes: Int
    let max: Int

    var body: some View {
        HStack {
            step("minus") { minutes = Swift.max(15, minutes - 15) }
            Spacer()
            Text(Climbs.duration(minutes)).font(Theme.display(44)).monospacedDigit()
                .contentTransition(.numericText())
            Spacer()
            step("plus") { minutes = Swift.min(max, minutes + 15) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.25)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Duration \(Climbs.duration(minutes))")
    }

    private func step(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .heavy))
                .frame(width: 50, height: 50)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.22)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "15 minutes more" : "15 minutes less")
    }
}

/// How hard as four feel chips (Easy 3, Solid 6, Hard 8, Wrecked 10) inside a log card (#435).
struct FeelChips: View {
    @Binding var effort: Int
    static let feels: [(String, Int)] = [("Easy", 3), ("Solid", 6), ("Hard", 8), ("Wrecked", 10)]

    /// The one chip an effort lights: the nearest feel, a tie going to the lower one (7 → Solid, like its label).
    static func chip(for effort: Int) -> Int {
        feels.map(\.1).min { abs(effort - $0) < abs(effort - $1) } ?? 6
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.feels.indices, id: \.self) { i in
                let f = Self.feels[i]
                let on = Self.chip(for: effort) == f.1
                CardChip(title: f.0, on: on) { effort = f.1 }
            }
        }
    }
}

/// White-when-picked chip inside a log card.
struct CardChip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(on ? Theme.ink : .white)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.25))))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// "+ Notes" style chip that opens an optional field in a log card.
struct AddChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus").font(Theme.label(13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.25)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Sport picker of Log sport and Track on Watch (#473, design C from `other-sports/picker-proposals.png`): the member's
/// sports as big Explore-style cards on top, every other one as a vivid tile grouped by kind.
struct SportPicker: View {
    let sports: [Sport]
    let mine: [Sport]
    let live: Bool
    let selected: Sport?
    let pick: (Sport) -> Void
    @Environment(AppModel.self) private var model

    private var heroes: [Sport] { Array(mine.filter { sports.contains($0) }.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !heroes.isEmpty {
                Text("Your sports").eyebrow()
                ForEach(heroes) { s in hero(s) }
            }
            ForEach(Sport.PickerGroup.allCases, id: \.self) { g in
                let list = sports.filter { $0.pickerGroup == g && !heroes.contains($0) }
                if !list.isEmpty {
                    Text(g.title).eyebrow().padding(.top, 6)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(list) { s in tile(s) }
                    }
                }
            }
        }
    }

    private func hero(_ s: Sport) -> some View {
        Button { pick(s) } label: {
            HStack(spacing: 14) {
                Image(systemName: s.symbol).font(.system(size: 26, weight: .bold))
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.label).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(lastLine(s)).font(.footnote.weight(.semibold)).opacity(0.9).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(live ? "Start" : "Log").font(Theme.label(14))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.white))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(s.gradient))
            .overlay(ring(s, cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(live ? "Track" : "Log") \(s.label)")
        .accessibilityAddTraits(selected == s ? .isSelected : [])
    }

    private func tile(_ s: Sport) -> some View {
        Button { pick(s) } label: {
            VStack(spacing: 6) {
                Image(systemName: s.symbol).font(.system(size: 24, weight: .bold)).frame(height: 28)
                Text(s.short).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(s.gradient))
            .overlay(ring(s, cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.label)
        .accessibilityAddTraits(selected == s ? .isSelected : [])
    }

    private func ring(_ s: Sport, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white, lineWidth: selected == s ? 3 : 0)
    }

    /// "Last: Sat · 2 h · 32 km", or what to do when never logged.
    private func lastLine(_ s: Sport) -> String {
        guard let last = model.sportLogs.first(where: { $0.sport == s }) else {
            return live ? "Your Watch records it" : "Not logged yet"
        }
        let days = Calendar.current.dateComponents([.day], from: last.start, to: .now).day ?? 0
        let when = Calendar.current.isDateInToday(last.start) ? "Today"
            : days < 6 ? last.start.formatted(.dateTime.weekday(.abbreviated))
            : last.start.formatted(.dateTime.day().month(.abbreviated))
        var parts = ["Last: \(when)", Climbs.duration(last.minutes)]
        if let d = last.distanceKm { parts.append(d >= 10 ? "\(Int(d.rounded())) km" : String(format: "%.1f km", d)) }
        return parts.joined(separator: " · ")
    }
}

extension Sport {
    /// Sections of the sport picker (#473).
    enum PickerGroup: CaseIterable {
        case snow, feet, water, court

        var title: String {
            switch self {
            case .snow: "Snow & mountain"
            case .feet: "Wheels & feet"
            case .water: "Water"
            case .court: "Gym, court & more"
            }
        }
    }

    var pickerGroup: PickerGroup {
        switch self {
        case .snowboard, .ski, .crossCountrySki, .mountaineering, .climbing: .snow
        case .mountainBike, .roadBike, .run, .trailRun, .hike, .skate: .feet
        case .swim, .rowing, .surf, .scubaDiving: .water
        default: .court
        }
    }
}

/// Bold square sport tile: icon on top, name under it.
struct SportTile: View {
    let sport: Sport
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: sport.symbol).font(.system(size: 24, weight: .bold)).frame(height: 28)
                Text(sport.short).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 74)
            .selectableGradient(sport.gradient, selected: selected, cornerRadius: 18)
            .scaleEffect(selected ? 1 : 0.97)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sport.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Spotted in Health (design C)

/// A sport session (design A + C from `other-sports/session-proposals.png`): speed-coloured route map, stat tiles,
/// elevation chart you scrub (the map dot follows), the sport's own section, how it felt and a swap for today.
struct SportSessionSheet: View {
    let entry: SportEntry
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var effort: Int?
    @State private var swapped = false
    @State private var track: SportTrack?
    /// Point the elevation chart is scrubbed to; the map dot follows.
    @State private var scrub: Int?
    @State private var selectedRun: Int?
    @State private var colour: RouteColour = .speed
    @State private var runs: [SportTrack.Run] = []

    /// Today's workout, when not started or done, and the type that spares what this session loaded.
    private var swap: (Session, Focus)? {
        guard let s = model.nextSession, s.weekday == model.todayWeekday, model.canChangeFocus(s),
              (effort ?? entry.effort ?? 6) >= 6, Calendar.current.isDateInYesterday(entry.start) || Calendar.current.isDateInToday(entry.start),
              let to = Sports.swap(for: s.focus, after: entry.sport) else { return nil }
        return (s, to)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let race = model.sportLogs.first(where: { $0.id == entry.id })?.hyrox {
                        // Hyrox race recorded on the Watch (#426): the race report.
                        HyroxReportView(race: race)
                    } else if let track, track.points.count >= 2 {
                        SportRouteMap(track: track, sport: entry.sport, source: entry.source, minutes: entry.minutes,
                                      scrub: scrub, runs: runs, selected: selectedRun, colour: $colour)
                        SportStatTiles(entry: entry, track: track, runs: runs.count)
                        if entry.sport.downhill { SkiDayCard(track: track) }
                        SportElevationChart(track: track, byDistance: !entry.sport.downhill, scrub: $scrub)
                    } else {
                        header
                    }
                    SportSection(entry: entry, track: track, runs: runs, selected: $selectedRun)
                    Text("How did it feel?").eyebrow()
                    HStack(spacing: 8) {
                        ForEach(FeelChips.feels.indices, id: \.self) { i in
                            let f = FeelChips.feels[i]
                            let on = (effort ?? entry.effort).map { FeelChips.chip(for: $0) == f.1 } ?? false
                            Button { rate(f.1) } label: {
                                Text(f.0).font(Theme.label(14)).frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(on ? Theme.ink : .white)
                                    .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.15))))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let sw = swap, !swapped {
                        let s = sw.0
                        let to = sw.1
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ease in · \(entry.sport.loadLabel) loaded").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                            Text("Today: \(s.focus.dayLabel) → \(to.dayLabel)").font(Theme.display(22))
                            Text("Spares what \(entry.sport.short.lowercased()) worked. This week only; change it back on the workout page.")
                                .font(.footnote).opacity(0.9)
                            Button {
                                model.swapAfterSport(s, to: to)
                                swapped = true
                            } label: { Label("Swap today", systemImage: "arrow.triangle.swap") }
                                .buttonStyle(LimeButtonStyle())
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x00B86B), Color(hex: 0x7DFFB0)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    } else if swapped {
                        Label("Today's workout swapped", systemImage: "checkmark.circle.fill").font(Theme.label(14)).foregroundStyle(Theme.lime)
                    }
                    if entry.local {
                        Button(role: .destructive) { delete() } label: { Label("Delete session", systemImage: "trash") }
                            .font(Theme.label(14))
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(entry.sport.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !entry.local else { return }
            track = await health.track(for: entry.id)?.thinned()
            runs = entry.sport.downhill ? track?.runs() ?? [] : []
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: entry.sport.symbol).font(.system(size: 22, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(entry.source)".uppercased())
                        .font(Theme.label(10)).tracking(1).opacity(0.85)
                    Text("\(entry.sport.short) · \(entry.durationText)").font(Theme.display(24))
                }
            }
            if !entry.statsText.isEmpty { Text(entry.statsText).font(Theme.label(15)) }
            HStack(spacing: 6) {
                if let s = entry.avgSpeed, entry.sport.hasDistance { chip(String(format: "%.1f km/h avg", s)) }
                if let m = entry.maxHR { chip("max \(Int(m.rounded())) bpm") }
                if let k = entry.kcal { chip("\(Int(k.rounded())) kcal") }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(entry.sport.gradient))
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(Theme.label(11)).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.black.opacity(0.25)))
    }

    private func rate(_ e: Int) {
        effort = e
        if entry.local, var log = model.sportLogs.first(where: { $0.id == entry.id }) {
            log.effort = e
            model.saveSport(log)
        } else {
            model.rateSport(entry, effort: e)
        }
    }

    private func delete() {
        model.deleteSport(entry.id)
        Task {
            await health.deleteSport(entry.id)
            await health.refresh()
        }
        dismiss()
    }
}

/// Progress: the last sport sessions as bold tiles; tap for stats and how it felt.
struct SportsCard: View {
    let entries: [SportEntry]
    @State private var open: SportEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Other sports").eyebrow()
                Spacer()
                Text("\(Sports.thisWeek(entries)) this week").font(Theme.label(12)).foregroundStyle(Theme.lime)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(entries.prefix(10)) { e in
                        Button { open = e } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: e.sport.symbol).font(.system(size: 18, weight: .bold))
                                Spacer(minLength: 0)
                                Text(e.sport.short).font(Theme.display(17)).lineLimit(1)
                                Text("\(e.start.formatted(.dateTime.weekday(.abbreviated).day())) · \(e.durationText)").font(Theme.label(11)).opacity(0.9)
                                if !e.statsText.isEmpty { Text(e.statsText).font(Theme.label(10)).opacity(0.8).lineLimit(1) }
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                            .frame(width: 150, height: 120, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(e.sport.gradient))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .sheet(item: $open) { SportSessionSheet(entry: $0) }
    }
}

// MARK: - My sports (cards in PlanSportViews.swift, #474)

/// One sport: which one, days, season, event, and the gym days around it.
struct SportPlanEditor: View {
    @State private var plan: SportPlan
    let isNew: Bool
    /// (plan, removed)
    let onDone: (SportPlan, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var hasEvent: Bool
    @State private var event: Date
    @State private var showsSeason = false

    init(plan: SportPlan, isNew: Bool, onDone: @escaping (SportPlan, Bool) -> Void) {
        _plan = State(initialValue: plan)
        self.isNew = isNew
        self.onDone = onDone
        _hasEvent = State(initialValue: plan.event != nil)
        _event = State(initialValue: plan.event ?? Date().addingTimeInterval(60 * 86_400))
    }

    static func seasonText(_ months: [Int]) -> String {
        let names = Calendar.current.shortMonthSymbols
        let m = months.sorted()
        guard let first = m.first, let last = m.last, m.count < 12 else { return "All year" }
        // Wrapping seasons (Dec–Apr): start after the gap.
        if let gap = zip(m, m.dropFirst()).first(where: { $1 - $0 > 1 }) {
            return "\(names[gap.1 - 1])–\(names[gap.0 - 1])"
        }
        return first == last ? names[first - 1] : "\(names[first - 1])–\(names[last - 1])"
    }

    private var days: Binding<[Int]> { Binding(get: { WeekSchedule.normalized(plan.weekdays) }, set: { plan.weekdays = $0 }) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Design C (#474): one swipeable sport strip instead of a full grid, the form fits under it.
                    SportStripPicker(selected: $plan.sport, sports: sportChoices)
                    Text("Usual days").eyebrow().padding(.top, 4)
                    DayTiles(days: days, symbol: plan.sport.symbol, fill: AnyShapeStyle(plan.sport.gradient), ink: .white)

                    Button { showsSeason = true } label: {
                        formRow("Season", value: plan.seasonMonths.map(Self.seasonText) ?? "All year")
                    }
                    .buttonStyle(.plain)
                    Toggle(isOn: $hasEvent) {
                        Text("Race or event").font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .tint(Theme.lime)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                    if hasEvent {
                        DatePicker("Event day", selection: $event, in: Date()..., displayedComponents: .date)
                            .font(.body.weight(.semibold))
                    }

                    Text("Gym around it").eyebrow().padding(.top, 4)
                    labelled("Day before") {
                        neighbourChips(Binding(get: { plan.before ?? plan.sport.defaultBefore }, set: { plan.before = $0 == plan.sport.defaultBefore ? nil : $0 }))
                    }
                    labelled("Day after") {
                        neighbourChips(Binding(get: { plan.after ?? plan.sport.defaultAfter }, set: { plan.after = $0 == plan.sport.defaultAfter ? nil : $0 }))
                    }
                    if plan.sport.allowsSameDayGym {
                        labelled("Same day") {
                            HStack(spacing: 8) {
                                SportChip(title: "Skip gym", selected: plan.sameDay != .allow) { plan.sameDay = nil }
                                SportChip(title: "Gym allowed", selected: plan.sameDay == .allow) { plan.sameDay = .allow }
                            }
                        }
                    } else {
                        Text("No gym on dive days, and rest the day after: hard exercise after diving raises the risk of decompression sickness.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime)
                    }
                    Text("Light keeps \(plan.sport.loadLabel) easy next to \(plan.sport.short.lowercased()) days. Trips and one-off days: tap a day in Calendar.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    if !isNew {
                        Button(role: .destructive) { finish(removed: true) } label: { Label("Remove \(plan.sport.short)", systemImage: "trash") }
                            .font(Theme.label(14))
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button { finish(removed: false) } label: { Label("Done", systemImage: "checkmark") }
                    .buttonStyle(LimeButtonStyle())
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.bg.opacity(0.95).ignoresSafeArea())
            }
            .navigationTitle(isNew ? "Add sport" : plan.sport.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(isPresented: $showsSeason) { seasonSheet }
        }
        .preferredColorScheme(.dark)
    }

    /// Any sport but climbing (it has its own card), the member's own first.
    private var sportChoices: [Sport] { model.sportOrder.filter { $0 != .climbing } }

    private func formRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .heavy, design: .rounded))
            Spacer()
            Text(value).font(Theme.label(14)).foregroundStyle(Theme.lime)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.lime)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private var seasonSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(1...12, id: \.self) { m in
                        let on = plan.seasonMonths?.contains(m) ?? false
                        SportChip(title: String(Calendar.current.shortMonthSymbols[m - 1].prefix(3)), selected: on) {
                            var months = plan.seasonMonths ?? []
                            if on { months.removeAll { $0 == m } } else { months.append(m) }
                            plan.seasonMonths = months.isEmpty ? nil : months.sorted()
                        }
                    }
                }
                Text(plan.seasonMonths.map(Self.seasonText) ?? "All year: no months picked.").font(.caption).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("\(plan.sport.short) season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { showsSeason = false } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private func neighbourChips(_ value: Binding<ClimbNeighbour>) -> some View {
        HStack(spacing: 8) {
            ForEach([ClimbNeighbour.light, .strong, .rest, .any]) { o in
                SportChip(title: Self.neighbourLabel(o), selected: value.wrappedValue == o) { value.wrappedValue = o }
            }
        }
    }

    private static func neighbourLabel(_ o: ClimbNeighbour) -> String {
        switch o {
        case .light: "Light"
        case .strong: "Strong"
        case .rest: "Rest"
        case .any: "Any"
        }
    }

    private func finish(removed: Bool) {
        var p = plan
        if hasEvent {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            p.eventDate = f.string(from: event)
        } else {
            p.eventDate = nil
        }
        onDone(p, removed)
        dismiss()
    }
}

struct SportChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(selected ? Theme.ink : .white)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
