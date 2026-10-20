import SwiftUI
import WorkoutEngine

// Session flow (#198): which blocks a workout runs and how its time is split. Edit plan sets the default for every
// workout, a workout can override it, and custom workouts carry their own warm-up, mobility, cardio and cool-down.

/// One block of the time bar.
struct FlowSegment: Identifiable, Equatable {
    let kind: BlockKind
    var minutes: Int
    var id: BlockKind { kind }
}

extension Array where Element == FlowSegment {
    var minutesByKind: [BlockKind: Int] { Dictionary(uniqueKeysWithValues: map { ($0.kind, $0.minutes) }) }
}

/// Large proportional time bar. Drag a divider to move minutes between the two blocks beside it; the total stays
/// the same. A `fixed` block (a custom workout's own exercises) keeps its time: dragging beside it resizes the other.
struct FlowBar: View {
    let segments: [FlowSegment]
    var fixed: BlockKind? = nil
    var fixedLabel = "YOURS"
    var height: CGFloat = 84
    var editable = true
    var onChange: ([BlockKind: Int]) -> Void = { _ in }
    var onCommit: () -> Void = {}

    @State private var start: [BlockKind: Int]?
    private static let gap: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let total = max(1, segments.reduce(0) { $0 + $1.minutes })
            let usable = max(1, geo.size.width - Self.gap * CGFloat(max(0, segments.count - 1)))
            let widths = segments.map { usable * CGFloat($0.minutes) / CGFloat(total) }
            ZStack(alignment: .topLeading) {
                HStack(spacing: Self.gap) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { i, s in
                        segment(s, width: widths[i]).frame(width: widths[i])
                    }
                }
                if editable {
                    ForEach(0..<max(0, segments.count - 1), id: \.self) { i in
                        let x = widths.prefix(i + 1).reduce(0, +) + Self.gap * CGFloat(i) + Self.gap / 2
                        handle
                            .position(x: x, y: height / 2)
                            .gesture(drag(i, minutesPerPoint: CGFloat(total) / usable))
                    }
                }
            }
            .coordinateSpace(name: "flowBar")
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: segments.map(\.minutes))
    }

    private func segment(_ s: FlowSegment, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            if width > 30 {
                Text("\(s.minutes)′").font(Theme.display(width > 60 ? 20 : 15)).lineLimit(1).minimumScaleFactor(0.6)
            }
            if width > 64 {
                Text(s.kind == fixed ? fixedLabel : s.kind.flowLabel.uppercased())
                    .font(Theme.label(8)).tracking(1).lineLimit(1).minimumScaleFactor(0.7).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, width > 30 ? 7 : 0)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(s.kind.gradient))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.kind == fixed ? "Your exercises" : s.kind.flowLabel), \(s.minutes) minutes")
        .accessibilityAdjustableAction { dir in
            guard editable, s.kind != fixed else { return }
            nudge(s.kind, dir == .increment ? 1 : -1)
        }
    }

    private var handle: some View {
        Capsule()
            .fill(.white)
            .frame(width: 6, height: height * 0.46)
            .shadow(color: .black.opacity(0.45), radius: 3)
            .frame(width: 30, height: height)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }

    private func drag(_ i: Int, minutesPerPoint: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("flowBar"))
            .onChanged { v in
                let base = start ?? segments.minutesByKind
                if start == nil { start = base }
                let a = segments[i].kind, b = segments[i + 1].kind
                var delta = Int((v.translation.width * minutesPerPoint).rounded())
                var next = base
                if a == fixed {
                    next[b] = max(SessionFlow.minimum(b), (base[b] ?? 0) - delta)
                } else if b == fixed {
                    next[a] = max(SessionFlow.minimum(a), (base[a] ?? 0) + delta)
                } else {
                    delta = min(delta, (base[b] ?? 0) - SessionFlow.minimum(b))
                    delta = max(delta, SessionFlow.minimum(a) - (base[a] ?? 0))
                    next[a] = (base[a] ?? 0) + delta
                    next[b] = (base[b] ?? 0) - delta
                }
                if next != segments.minutesByKind { onChange(next) }
            }
            .onEnded { _ in
                start = nil
                onCommit()
            }
    }

    /// VoiceOver: one minute more or less, taken from or given to the largest other movable block.
    private func nudge(_ k: BlockKind, _ by: Int) {
        var m = segments.minutesByKind
        if fixed != nil {
            m[k] = max(SessionFlow.minimum(k), (m[k] ?? 0) + by)
        } else {
            guard let other = segments.filter({ $0.kind != k }).max(by: { $0.minutes < $1.minutes })?.kind else { return }
            let nk = (m[k] ?? 0) + by, no = (m[other] ?? 0) - by
            guard nk >= SessionFlow.minimum(k), no >= SessionFlow.minimum(other) else { return }
            m[k] = nk
            m[other] = no
        }
        onChange(m)
        onCommit()
    }
}

/// Wrapping row of block chips: in the flow = vivid gradient, left out = dashed outline with a plus.
struct FlowChips: View {
    let kinds: [BlockKind]
    let included: (BlockKind) -> Bool
    let toggle: (BlockKind) -> Void
    var label: (BlockKind) -> String = { $0.flowLabel }
    /// Blocks whose chip, when included, opens their options instead of leaving them out (#293).
    var opens: (BlockKind) -> Bool = { _ in false }
    var open: (BlockKind) -> Void = { _ in }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(kinds, id: \.self) { k in
                let on = included(k)
                let opening = on && opens(k)
                Button { if opening { open(k) } else { toggle(k) } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: on ? k.symbol : "plus")
                        Text(label(k))
                        if opening { Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)) }
                    }
                    .font(Theme.label(13))
                    .foregroundStyle(on ? .white : Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if on {
                            Capsule().fill(k.gradient)
                        } else {
                            Capsule().strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(k))
                .accessibilityValue(on ? "In the flow" : "Left out")
                .accessibilityHint(opening ? "Opens its style and moves" : on ? "Removes it; its time goes to the other blocks" : "Adds it")
            }
        }
        .sensoryFeedback(.selection, trigger: kinds.map(included))
    }
}

/// Time bar plus chips for a generated session of `focus` and `minutes`.
struct SessionFlowEditor: View {
    let profile: Profile
    let focus: Focus
    let minutes: Int
    @Binding var flow: SessionFlow

    private var segments: [FlowSegment] {
        Generator.flowMinutes(profile, focus: focus, minutes: minutes, flow: flow).map { FlowSegment(kind: $0.kind, minutes: $0.minutes) }
    }

    var body: some View {
        let segs = segments
        VStack(alignment: .leading, spacing: 10) {
            FlowBar(segments: segs, onChange: { m in
                var f = flow
                f.shares = m
                flow = f
            })
            FlowChips(kinds: BlockKind.allCases, included: { k in segs.contains { $0.kind == k } }) { k in
                let on = segs.contains { $0.kind == k }
                let auto = Generator.autoFlowMinutes(profile, focus: focus, minutes: minutes)
                withAnimation(.spring(duration: 0.3)) { flow = flow.setting(k, !on, autoMinutes: auto) }
            }
        }
        .animation(.interactiveSpring(), value: segs)
    }
}

extension SessionFlow {
    /// Short summary for cards: the preset's name, or the blocks in the flow.
    func summary(_ profile: Profile) -> String {
        if let preset { return preset.label }
        let kinds = Generator.flowMinutes(profile, focus: Generator.referenceFocus(profile), minutes: Generator.sessionMinutes(profile), flow: self)
        return "Custom · " + kinds.map { $0.kind.flowLabel }.joined(separator: ", ")
    }
}

// MARK: - Edit plan

/// Training profile → Session flow: presets, the time bar of a typical workout and the block chips.
struct SessionFlowSection: View {
    @Binding var profile: Profile

    private var flow: Binding<SessionFlow> {
        Binding(get: { profile.sessionFlow ?? SessionFlow() },
                set: { f in profile.sessionFlow = f.isAuto ? nil : f.sanitized })
    }

    private var focus: Focus { Generator.referenceFocus(profile) }
    private var minutes: Int { Generator.sessionMinutes(profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick what every workout runs. Drag the bar to move time between blocks; the session stays \(minutes) min.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(SessionFlow.Preset.allCases) { p in
                    presetCard(p)
                }
            }
            Text("Typical workout · \(minutes)′").eyebrow().padding(.top, 6)
            SessionFlowEditor(profile: profile, focus: focus, minutes: minutes, flow: flow)
            Text("Conditioning days keep their cardio-led split; blocks you leave out stay out there too. Each workout can still change its own flow.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            BlockPicksList(profile: $profile)
        }
    }

    private func presetCard(_ p: SessionFlow.Preset) -> some View {
        let selected = flow.wrappedValue == p.flow
        let segs = Generator.flowMinutes(profile, focus: focus, minutes: minutes, flow: p.flow).map { FlowSegment(kind: $0.kind, minutes: $0.minutes) }
        let total = max(1, segs.reduce(0) { $0 + $1.minutes })
        return Button { withAnimation(.spring(duration: 0.3)) { flow.wrappedValue = p.flow } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.label).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.8)
                Text(p.detail).font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(segs) { s in
                            RoundedRectangle(cornerRadius: 3).fill(s.kind.gradient)
                                .frame(width: max(2, (geo.size.width - CGFloat(segs.count - 1) * 2) * CGFloat(s.minutes) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 8)
                .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardStrong))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Theme.lime : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(p.label): \(p.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - One workout

/// A plan workout's flow: same bar and chips, applied to this workout only or to every workout.
struct SessionFlowSheet: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var flow = SessionFlow()
    @State private var allWorkouts = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            if let profile = model.profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(session.displayTitle).font(Theme.display(30))
                        Text("Drag the bar to move time between blocks. Tap a block to add or remove it; the workout stays \(session.targetMin) min.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        SessionFlowEditor(profile: profile, focus: session.focus, minutes: session.targetMin, flow: $flow)
                        HStack(spacing: 8) {
                            scopeButton("This workout", selected: !allWorkouts) { allWorkouts = false }
                            scopeButton("All workouts", selected: allWorkouts) { allWorkouts = true }
                        }
                        .padding(.top, 4)
                        Button {
                            if allWorkouts { model.setPlanFlow(flow, clearing: session.id) } else { model.setSessionFlow(session.id, flow) }
                            dismiss()
                        } label: { Text("APPLY") }
                            .buttonStyle(LimeButtonStyle())
                        if model.sessionStyle(session.id).flow != nil {
                            Button { model.setSessionFlow(session.id, profile.sessionFlow ?? SessionFlow()); dismiss() } label: {
                                Label("Back to plan flow", systemImage: "arrow.uturn.backward")
                            }
                            .font(Theme.label(14))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                        }
                        Text("Exercises are re-picked for the new time; the main lift stays when strength does.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(16)
                }
                .readableWidth()
                .background(Theme.bg.ignoresSafeArea())
                .toolbar { CloseToolbarItem { dismiss() } }
                .onAppear {
                    guard !loaded else { return }
                    loaded = true
                    flow = model.sessionStyle(session.id).flow ?? profile.sessionFlow ?? SessionFlow()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func scopeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.label(13))
                .foregroundStyle(selected ? Theme.ink : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(selected ? Theme.lime : Theme.cardStrong))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Custom workouts

/// Builder: blocks played around the member's own exercises. Their exercises keep their time ("YOURS");
/// dragging beside them resizes the extra block, dragging between two extras moves time between them.
struct CustomFlowEditor: View {
    @Binding var minutes: [BlockKind: Int]
    /// Estimated minutes of the member's own exercises.
    let yours: Int
    /// Opens a warm-up / cool-down's style and moves (#293); nil = their chips toggle like the others.
    var open: ((BlockKind) -> Void)?

    static let kinds: [BlockKind] = [.warmup, .power, .mobility, .cardio, .cooldown]
    static let defaults: [BlockKind: Int] = [.warmup: 6, .power: 6, .mobility: 6, .cardio: 10, .cooldown: 5]

    private var segments: [FlowSegment] {
        BlockKind.allCases.compactMap { k in
            k == .strength ? Optional(FlowSegment(kind: .strength, minutes: max(1, yours))) : minutes[k].map { FlowSegment(kind: k, minutes: $0) }
        }
    }

    var body: some View {
        let segs = segments
        VStack(alignment: .leading, spacing: 10) {
            FlowBar(segments: segs, fixed: .strength, onChange: { m in
                var next = m
                next[.strength] = nil
                minutes = next
            })
            FlowChips(kinds: Self.kinds, included: { minutes[$0] != nil }, toggle: { k in
                withAnimation(.spring(duration: 0.3)) { minutes[k] = minutes[k] == nil ? Self.defaults[k] : nil }
            }, opens: { open != nil && FlowTweaks.kinds.contains($0) }, open: { open?($0) })
        }
        .animation(.interactiveSpring(), value: segs)
    }
}

extension CustomWorkout {
    /// Minutes per flow block, as stored.
    var flowMinutes: [BlockKind: Int] { Dictionary(flow.map { ($0.kind, $0.targetMin) }, uniquingKeysWith: { a, _ in a }) }

    /// Stable seed per workout, so re-saving keeps the same warm-up and cool-down picks.
    var flowSeed: UInt32 {
        let u = id.uuid
        return UInt32(u.0) << 24 | UInt32(u.1) << 16 | UInt32(u.2) << 8 | UInt32(u.3)
    }

    /// Copy with its flow blocks picked again for `minutes` around the current exercises.
    func withFlow(_ minutes: [BlockKind: Int], profile: Profile) -> CustomWorkout {
        var w = self
        w.flow = Generator.flowBlocks(profile, around: playableItems.compactMap(\.exercise), minutes: minutes, seed: flowSeed)
        return w
    }

    /// Minutes of the member's own exercises (without flow blocks).
    var ownMinutes: Int {
        var w = self
        w.flow = []
        return w.session.estMin
    }
}

// MARK: - My picks per block (#204)

/// Block whose picks are being edited (sheet item).
struct PickTarget: Identifiable {
    let kind: BlockKind
    var id: String { kind.rawValue }
}

/// Edit plan → Session flow: one vivid card per block with the member's pinned exercises.
struct BlockPicksList: View {
    @Binding var profile: Profile
    @State private var editing: PickTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My picks · every workout").eyebrow().padding(.top, 6)
            ForEach(BlockPicks.kinds, id: \.self) { k in
                Button { editing = PickTarget(kind: k) } label: { card(k, profile.picks(k)) }
                    .buttonStyle(.plain)
            }
            Text("Optional. Pinned exercises go first in their block with their own time; the rest is picked for the day. Strength keeps its picks through Swap.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .sheet(item: $editing) { t in
            BlockPicksSheet(kind: t.kind, picks: Binding(
                get: { profile.blockPicks?[t.kind.rawValue] ?? BlockPicks() },
                set: { profile.setPicks($0, for: t.kind) }))
        }
    }

    private func card(_ k: BlockKind, _ picks: BlockPicks?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: k.symbol)
                Text(picks == nil ? k.flowLabel : "\(k.flowLabel) · my picks").font(Theme.display(17))
                Spacer()
                if let picks { Text(picks.only ? "\(picks.minutes)′ ONLY" : "\(picks.minutes)′").font(Theme.label(12)) }
                Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
            }
            if let picks {
                ForEach(picks.items) { p in
                    HStack {
                        Text(Exercise.find(p.exerciseId)?.name ?? p.exerciseId).font(Theme.label(13)).lineLimit(1)
                        Spacer()
                        Text("\(p.minutes)′").font(Theme.display(15))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
                }
            } else {
                Text("Picked for the day · tap to pin").font(.footnote.weight(.semibold)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(k.gradient))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your picks for this block")
    }
}

/// One block's picks: pinned exercises with their minutes, Only my picks, and whether own workouts use them.
struct BlockPicksSheet: View {
    let kind: BlockKind
    @Binding var picks: BlockPicks
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    static let maxItems = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(kind.flowLabel).font(Theme.display(30))
                    Text("My picks · every workout").eyebrow()
                    ForEach($picks.items) { $item in row($item) }
                    if picks.items.count < Self.maxItems {
                        Button { adding = true } label: {
                            Label("Add exercise", systemImage: "plus.circle.fill")
                                .font(Theme.label(15))
                                .foregroundStyle(Theme.lime)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        }
                        .buttonStyle(.plain)
                    }
                    if !picks.items.isEmpty {
                        Toggle(isOn: $picks.only) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Only my picks").font(Theme.label(15))
                                Text(picks.only ? "The block lasts \(picks.minutes) min." : "The rest of the block is picked for the day.")
                                    .font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                        .tint(Theme.lime)
                        .padding(.top, 6)
                        Toggle(isOn: Binding(get: { picks.inCustom != false }, set: { picks.inCustom = $0 ? nil : false })) {
                            Text("Also in my own workouts").font(Theme.label(15))
                        }
                        .tint(Theme.lime)
                    }
                    Text("Exercises your gym doesn't have are skipped on that day.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(isPresented: $adding) {
                ExercisePickerView(limit: Self.maxItems - picks.items.count) { exs in
                    let have = Set(picks.items.map(\.exerciseId))
                    picks.items += exs.filter { !have.contains($0.id) }
                        .map { BlockPick(exerciseId: $0.id, minutes: BlockPicks.defaultMinutes($0, in: kind)) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ item: Binding<BlockPick>) -> some View {
        let range = BlockPick.minutesRange
        return HStack(spacing: 10) {
            if let e = Exercise.find(item.wrappedValue.exerciseId) { ExerciseThumbnail(exercise: e, size: 44) }
            Text(Exercise.find(item.wrappedValue.exerciseId)?.name ?? item.wrappedValue.exerciseId)
                .font(Theme.label(15)).lineLimit(2)
            Spacer(minLength: 4)
            stepButton("minus", enabled: item.wrappedValue.minutes > range.lowerBound) { item.wrappedValue.minutes -= 1 }
            Text("\(item.wrappedValue.minutes)′").font(Theme.display(22)).frame(minWidth: 40)
            stepButton("plus", enabled: item.wrappedValue.minutes < range.upperBound) { item.wrappedValue.minutes += 1 }
            Button { picks.items.removeAll { $0.exerciseId == item.wrappedValue.exerciseId } } label: {
                Image(systemName: "xmark").font(.footnote.bold()).padding(8).background(Circle().fill(.black.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(kind.gradient))
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.bold()).frame(width: 32, height: 32).background(Circle().fill(.white.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(symbol == "plus" ? "One minute more" : "One minute less")
    }
}
