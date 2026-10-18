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
    /// The member's sports first (climbing for climbers), then every other one.
    var sportOrder: [Sport] {
        var mine = (profile?.otherSports ?? []).map(\.sport)
        if profile.map(Generator.isClimber) ?? false { mine.insert(.climbing, at: 0) }
        for log in sportLogs where !mine.contains(log.sport) { mine.append(log.sport) }
        return mine + Sport.allCases.filter { !mine.contains($0) }
    }
}

/// Lime-row button beside Start workout (#277 slot): opens the sport grid.
struct LogSportButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Log sport", systemImage: "plus.circle.fill")
                .font(Theme.label(15))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF3D8B), Color(hex: 0xFF9A5E)],
                                                          startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Log a sport session: snowboard, bike, Hyrox, climbing…")
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
    private let initial: SportLog

    /// `restoring`: the session brought back by Undo (#285).
    init(initial: SportLog, picked: Bool = false, restoring: SportLog? = nil) {
        self.initial = initial
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
                        card
                        Text(health.connected && health.writeWorkouts
                             ? "Also saved to Apple Health. Gym days around it are planned to spare \(log.sport.loadLabel)."
                             : "Saved in MonkeyWorkout. Connect Apple Health in Progress → Body & Health to also save it there.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        Text("What did you do?").eyebrow()
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(model.sportOrder) { s in
                                SportTile(sport: s, selected: picked && log.sport == s) { pick(s) }
                            }
                        }
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
                    Button { save() } label: {
                        Label("Save \(log.sport.short) · \(Climbs.duration(log.minutes)) · \(log.effort)", systemImage: "checkmark")
                    }
                    .buttonStyle(LimeButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.bg.opacity(0.95).ignoresSafeArea())
                }
            }
            .navigationTitle(picked ? "Log \(log.sport.short)" : "Log sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .undoableClose(closeGuard, offer: undoOffer)
    }

    private func pick(_ s: Sport) {
        if s == .climbing {
            climbing = true
        } else {
            log.sport = s
            picked = true
            allSports = false
        }
    }

    /// The picked sport first, then the member's order; "All" opens the full grid again.
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([log.sport] + model.sportOrder.filter { $0 != log.sport }.prefix(7)) { s in
                    SportTile(sport: s, selected: log.sport == s) { pick(s) }
                        .frame(width: 74)
                        .opacity(log.sport == s ? 1 : 0.55)
                }
                Button { allSports = true } label: {
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

    private static let feels: [(String, Int)] = [("Easy", 3), ("Solid", 6), ("Hard", 8), ("Wrecked", 10)]

    /// Design C card (#435): the sport's own colours hold when, how long and how hard.
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker("Started", selection: $log.start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .colorScheme(.dark)
                    Text(log.sport.label).font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer()
                Image(systemName: log.sport.symbol).font(.system(size: 40, weight: .bold))
            }

            HStack {
                cardStep("minus") { log.minutes = max(15, log.minutes - 15) }
                Spacer()
                Text(Climbs.duration(log.minutes)).font(Theme.display(44)).monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                cardStep("plus") { log.minutes = min(16 * 60, log.minutes + 15) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.25)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Duration \(Climbs.duration(log.minutes))")

            Text("How hard · \(log.effort) \(ClimbLog.effortLabel(log.effort))")
                .font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
            HStack(spacing: 6) {
                ForEach(Self.feels.indices, id: \.self) { i in
                    let f = Self.feels[i]
                    let on = abs(log.effort - f.1) <= 1
                    Button { log.effort = f.1 } label: {
                        Text(f.0).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .foregroundStyle(on ? Theme.ink : .white)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.25))))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

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
                if log.sport.hasDistance && !showDistance { addChip("Distance") { showDistance = true } }
                if !showNotes { addChip("Notes") { showNotes = true } }
            }
        }
        .gradientCard(log.sport.gradient, padding: 18)
        .shadow(color: log.sport.colors[0].opacity(0.35), radius: 16, y: 8)
    }

    private func cardStep(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .heavy))
                .frame(width: 50, height: 50)
                .background(Circle().fill(.white.opacity(0.22)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "15 minutes more" : "15 minutes less")
    }

    private func addChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus").font(Theme.label(13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.25)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var undoOffer: UndoOffer? {
        guard picked, log != initial else { return nil }
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

/// Bold square sport tile: icon on top, name under it.
private struct SportTile: View {
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
    @State private var scrub: Date?

    private static let feels: [(String, Int)] = [("Easy", 3), ("Solid", 6), ("Hard", 8), ("Wrecked", 10)]

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
                        SportRouteMap(track: track, sport: entry.sport, source: entry.source, minutes: entry.minutes, scrub: scrub)
                        SportStatTiles(entry: entry, track: track)
                        SportElevationChart(track: track, scrub: $scrub)
                    } else {
                        header
                    }
                    SportSection(entry: entry, track: track)
                    Text("How did it feel?").eyebrow()
                    HStack(spacing: 8) {
                        ForEach(Self.feels.indices, id: \.self) { i in
                            let f = Self.feels[i]
                            let on = (effort ?? entry.effort).map { abs($0 - f.1) <= 1 } ?? false
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
        .task { if !entry.local { track = await health.track(for: entry.id)?.thinned() } }
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

/// Route coloured by speed (slow green → fast red); the dot follows the elevation chart's scrub.
private struct SportRouteMap: View {
    let track: SportTrack
    let sport: Sport
    let source: String
    let minutes: Int
    let scrub: Date?

    private struct Piece: Identifiable {
        let id: Int
        let coords: [CLLocationCoordinate2D]
        let color: Color
    }

    private static let speedColors = [Color(hex: 0x7DFFB0), Color(hex: 0xFFB800), Color(hex: 0xFF3D3D)]

    /// Consecutive points of the same speed band become one polyline (sharing the joint point).
    private var pieces: [Piece] {
        let top = max(track.points.map(\.speed).max() ?? 1, 0.1)
        func band(_ v: Double) -> Int { min(2, Int(v / top * 3)) }
        var out: [Piece] = []
        var current: [CLLocationCoordinate2D] = []
        var currentBand = band(track.points.first?.speed ?? 0)
        for p in track.points {
            let c = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
            let b = band(p.speed)
            current.append(c)
            if b != currentBand && current.count > 1 {
                out.append(Piece(id: out.count, coords: current, color: Self.speedColors[currentBand]))
                current = [c]
                currentBand = b
            }
        }
        if current.count > 1 { out.append(Piece(id: out.count, coords: current, color: Self.speedColors[currentBand])) }
        return out
    }

    var body: some View {
        let dot = scrub.flatMap { track.index(near: $0) }.map { track.points[$0] }
        Map(initialPosition: .automatic) {
            ForEach(pieces) { p in
                MapPolyline(coordinates: p.coords).stroke(p.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = track.points.first {
                Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)) {
                    Circle().fill(Theme.lime).frame(width: 12, height: 12)
                }
            }
            if let dot {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lon)) {
                    Circle().fill(Theme.lime).frame(width: 16, height: 16).overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            Label("\(sport.short) · \(Climbs.duration(minutes)) · \(source)", systemImage: sport.symbol)
                .font(Theme.label(11)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(10)
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                Text("slow").font(Theme.label(9))
                Capsule().fill(LinearGradient(colors: Self.speedColors, startPoint: .leading, endPoint: .trailing)).frame(width: 40, height: 5)
                Text("fast").font(Theme.label(9))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(10)
        }
    }
}

/// Four bold tiles: distance, vertical, top speed, heart rate.
private struct SportStatTiles: View {
    let entry: SportEntry
    let track: SportTrack

    var body: some View {
        let v = track.vertical()
        let downhill = [Sport.snowboard, .ski].contains(entry.sport)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            if let d = entry.distanceKm { tile("Distance", d >= 10 ? "\(Int(d.rounded()))" : String(format: "%.1f", d), "km", [0x00A3C4, 0x7DF9FF]) }
            tile(downhill ? "Vertical" : "Ascent", "\(Int((downhill ? v.down : entry.elevationM ?? v.up).rounded()).formatted())", "m", [0x3D59FF, 0x00C7FF])
            if let top = track.topKmh, top > 1 { tile("Top speed", "\(Int(top.rounded()))", "km/h", [0xFF3D8B, 0xFF9A5E]) }
            if let hr = entry.avgHR { tile("Avg HR", "\(Int(hr.rounded()))", "bpm", [0xFF5E3A, 0xFFB03D]) }
        }
    }

    private func tile(_ label: String, _ value: String, _ unit: String, _ hex: [UInt32]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(Theme.label(10)).tracking(1.2).opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.display(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(Theme.label(11)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: hex.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

/// Elevation over time; drag to scrub (the map dot follows) and read altitude, speed and time at that point.
private struct SportElevationChart: View {
    let track: SportTrack
    @Binding var scrub: Date?

    var body: some View {
        let low = (track.points.map(\.alt).min() ?? 0) - 10
        let picked = scrub.flatMap { track.index(near: $0) }.map { track.points[$0] }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(picked.map { $0.time.formatted(date: .omitted, time: .shortened) } ?? "Elevation").eyebrow()
                Spacer()
                if let p = picked {
                    Text("\(Int(p.alt.rounded()).formatted()) m · \(Int((p.speed * 3.6).rounded())) km/h").font(Theme.label(13)).foregroundStyle(Theme.lime)
                } else {
                    Text("Drag to replay").font(Theme.label(11)).foregroundStyle(Theme.muted)
                }
            }
            Chart {
                ForEach(Array(track.points.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Time", p.time), yStart: .value("Base", low), yEnd: .value("Altitude", p.alt))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0x3D59FF).opacity(0.8), Color(hex: 0x3D59FF).opacity(0.05)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", p.time), y: .value("Altitude", p.alt))
                        .foregroundStyle(Color(hex: 0x7DF9FF))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let picked {
                    RuleMark(x: .value("Time", picked.time)).foregroundStyle(Theme.lime).lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartYScale(domain: low...((track.highest ?? low) + 10))
            .chartXAxis(.hidden)
            .chartXSelection(value: $scrub)
            .frame(height: 120)
        }
        .card(padding: 14)
    }
}

/// What matters for this sport: runs (ski, snowboard), laps (Hyrox, intervals), summit (hike, mountaineering).
private struct SportSection: View {
    let entry: SportEntry
    let track: SportTrack?

    var body: some View {
        if let track {
            let runs = [Sport.snowboard, .ski].contains(entry.sport) ? track.runs() : []
            if !runs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Runs · \(runs.count)").eyebrow()
                    ForEach(Array(runs.enumerated()), id: \.offset) { i, r in
                        row("\(i + 1)", "\(Int(r.drop.rounded())) m down", "\(Int(r.topKmh.rounded())) km/h")
                    }
                }
                .card(padding: 14)
            } else if !track.laps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.sport == .hyrox ? "Splits · \(track.laps.count)" : "Laps · \(track.laps.count)").eyebrow()
                    ForEach(Array(track.laps.enumerated()), id: \.offset) { i, l in
                        row("\(i + 1)", Self.clock(l.minutes), l.start.formatted(date: .omitted, time: .shortened))
                    }
                }
                .card(padding: 14)
            } else if [Sport.hike, .mountaineering, .trailRun].contains(entry.sport), let top = track.highest {
                HStack {
                    Label("Summit", systemImage: "flag.fill").font(Theme.label(14))
                    Spacer()
                    Text("\(Int(top.rounded()).formatted()) m").font(Theme.display(22))
                }
                .card(padding: 14)
            }
        }
    }

    private func row(_ n: String, _ main: String, _ trailing: String) -> some View {
        HStack {
            Text(n).font(Theme.label(13)).foregroundStyle(Theme.lime).frame(width: 24, alignment: .leading)
            Text(main).font(Theme.label(14))
            Spacer()
            Text(trailing).font(Theme.label(13)).foregroundStyle(Theme.muted)
        }
    }

    static func clock(_ minutes: Double) -> String {
        let s = Int((minutes * 60).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
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

// MARK: - My sports (design B)

/// Training profile: the member's other sports, each with days, season or event, and the rules around it.
struct MySportsEditor: View {
    @Binding var sports: [SportPlan]?
    /// Shows the Snow ready link (#428) for skiers and snowboarders; off during onboarding.
    var programmeLink = false
    @State private var editing: SportPlan?
    @State private var snow: ProgrammeRoute?

    var body: some View {
        let list = (sports ?? []).filter { $0.sport != .climbing }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("My other sports", systemImage: "figure.mixed.cardio").font(Theme.label(13)).foregroundStyle(Theme.muted)
                Spacer()
                Button { editing = SportPlan(sport: firstFree(list)) } label: {
                    Label("Add", systemImage: "plus").font(Theme.label(13)).foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
            }
            ForEach(list) { sp in
                Button { editing = sp } label: { SportPlanCard(plan: sp) }.buttonStyle(.plain)
            }
            if list.isEmpty {
                Text("Snowboard, bike, Hyrox… Gym days are planned around them.").font(.caption).foregroundStyle(Theme.muted)
            }
            if programmeLink, let ride = SnowRide.from(sports) {
                Button { snow = ProgrammeRoute(id: ride.programmeId) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "snowflake").font(.system(size: 14, weight: .bold))
                        Text("Snow ready programme").font(Theme.label(14))
                        Spacer(minLength: 4)
                        Text("Get ready for the season ›").font(.footnote.weight(.bold)).foregroundStyle(Theme.lime)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $snow) { ProgrammeSheet(id: $0.id) }
        .sheet(item: $editing) { sp in
            SportPlanEditor(plan: sp, isNew: !(sports ?? []).contains { $0.sport == sp.sport }) { saved, removed in
                var all = (sports ?? []).filter { $0.sport != sp.sport && $0.sport != saved.sport }
                if !removed { all.append(saved) }
                sports = all.isEmpty ? nil : all
            }
        }
    }

    private func firstFree(_ list: [SportPlan]) -> Sport {
        Sport.allCases.first { s in s != .climbing && !list.contains { $0.sport == s } } ?? .other
    }
}

private struct SportPlanCard: View {
    let plan: SportPlan

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: plan.sport.symbol).font(.system(size: 17, weight: .bold))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 1) {
                Text(plan.sport.label).font(Theme.display(17)).lineLimit(1)
                Text(detail).font(Theme.label(11)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(plan.sport.loadLabel).font(Theme.label(10)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.25)))
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(plan.sport.gradient))
    }

    private var detail: String {
        let days = WeekSchedule.normalized(plan.weekdays).map(WeekSchedule.shortName).joined(separator: " · ")
        var parts = [days.isEmpty ? "No set days" : days]
        if let m = plan.seasonMonths, !m.isEmpty { parts.append(SportPlanEditor.seasonText(m)) }
        if let e = plan.event { parts.append("Event \(e.formatted(.dateTime.day().month(.abbreviated)))") }
        return parts.joined(separator: " · ")
    }
}

/// One sport: which one, days, season, event, and the gym days around it.
struct SportPlanEditor: View {
    @State private var plan: SportPlan
    let isNew: Bool
    /// (plan, removed)
    let onDone: (SportPlan, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasEvent: Bool
    @State private var event: Date

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
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sport").eyebrow()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Sport.allCases.filter { $0 != .climbing }) { s in
                            Button { plan.sport = s } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: s.symbol).font(.system(size: 18, weight: .bold))
                                    Text(s.short).font(Theme.label(10)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .selectableGradient(s.gradient, selected: plan.sport == s, cornerRadius: 14)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(s.label)
                        }
                    }
                    Text("Usual days").eyebrow()
                    DayTiles(days: days, symbol: plan.sport.symbol, fill: AnyShapeStyle(plan.sport.gradient), ink: .white)

                    Text("Season").eyebrow()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
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

                    Toggle(isOn: $hasEvent) {
                        Text("Race or event").font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .tint(Theme.lime)
                    if hasEvent {
                        DatePicker("Event day", selection: $event, in: Date()..., displayedComponents: .date)
                            .font(.body.weight(.semibold))
                    }

                    Text("Day before").eyebrow()
                    neighbourChips(Binding(get: { plan.before ?? plan.sport.defaultBefore }, set: { plan.before = $0 == plan.sport.defaultBefore ? nil : $0 }))
                    Text("Day after").eyebrow()
                    neighbourChips(Binding(get: { plan.after ?? plan.sport.defaultAfter }, set: { plan.after = $0 == plan.sport.defaultAfter ? nil : $0 }))
                    Text("Same day").eyebrow()
                    if plan.sport.allowsSameDayGym {
                        HStack(spacing: 8) {
                            SportChip(title: "Skip gym", selected: plan.sameDay != .allow) { plan.sameDay = nil }
                            SportChip(title: "Gym allowed", selected: plan.sameDay == .allow) { plan.sameDay = .allow }
                        }
                    } else {
                        Text("No gym on dive days, and rest the day after: hard exercise after diving raises the risk of decompression sickness.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime)
                    }
                    Text("Light keeps \(plan.sport.loadLabel) easy next to \(plan.sport.short.lowercased()) days. Saving rebuilds this week's plan.")
                        .font(.footnote).foregroundStyle(Theme.muted)

                    Button { finish(removed: false) } label: { Label("Done", systemImage: "checkmark") }
                        .buttonStyle(LimeButtonStyle())
                    if !isNew {
                        Button(role: .destructive) { finish(removed: true) } label: { Label("Remove \(plan.sport.short)", systemImage: "trash") }
                            .font(Theme.label(14))
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isNew ? "Add sport" : plan.sport.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
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
