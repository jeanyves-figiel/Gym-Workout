import SceneKit
import SwiftUI
import UIKit
import WorkoutEngine

/// Position guide (#402, design A+B): the exercise's start, middle and end positions on a 3D clay figure the
/// member turns (Side · ¾ · Front · Back snaps or drag). Numbered pins mark the technique checkpoints (cue cards
/// below), arcs measure the two joints that move most with the range that counts as right, and a red ghost
/// shows the exercise's most common mistake. Poses come from the same key poses the animation is drawn from.
struct PositionGuideView: View {
    let exercise: Exercise
    let position: ExercisePosition

    @State private var key: Int
    @State private var yaw: Double
    @State private var dragBase: Double?
    @State private var showMistake = false
    @State private var snapFrom: (yaw: Double, at: Date)?
    @State private var snapTarget: Double?
    /// Pinch / button zoom of the stage (1 = whole movement framed).
    @State private var zoom = 1.0
    @State private var pinchBase: Double?
    /// Step the camera zooms on (design C, #959); nil = all callouts.
    @State private var focus: Int?

    init(exercise: Exercise, position: ExercisePosition, key: Int? = nil, demoMistake: Bool = false) {
        self.exercise = exercise
        self.position = position
        _key = State(initialValue: key ?? position.mainKey)
        _showMistake = State(initialValue: demoMistake)
        _yaw = State(initialValue: Snap.home(position.view).yaw)
    }

    enum Snap: CaseIterable {
        case side, threeQuarter, front, back
        var label: String {
            switch self {
            case .side: "Side"
            case .threeQuarter: "¾"
            case .front: "Front"
            case .back: "Back"
            }
        }
        /// Turn of the figure (it faces +x; the camera looks from +z).
        var yaw: Double {
            switch self {
            case .side: 0
            case .threeQuarter: -.pi / 4
            case .front: -.pi / 2
            case .back: .pi / 2
            }
        }
        static func home(_ view: ExercisePosition.View) -> Snap {
            switch view {
            case .side: .threeQuarter
            case .front: .front
            case .back: .back
            }
        }
    }

    private var technique: Technique? { exercise.technique }
    /// Checkpoints with a pin (one per body part, first four).
    private var pins: [(Int, Checkpoint)] {
        var seen = Set<BodyPart>()
        return (technique?.position ?? []).enumerated().compactMap { i, c in
            guard seen.insert(c.part).inserted, seen.count <= 4 else { return nil }
            return (i + 1, c)
        }
    }
    private var checks: [PositionCheck] { position.checks(at: key) }

    /// One technique step on the stage: a callout by default, the camera's focus when tapped.
    struct Step: Identifiable {
        let n: Int
        let part: String
        let cue: String
        let joint: String
        let color: Color
        let check: PositionCheck?
        var id: Int { n }
    }

    /// The pinned checkpoints (with the angle check on their joint, if any), then angle checks no pin covers.
    private var steps: [Step] {
        var out = pins.map { n, c in
            let check = checks.first { Self.checkJoint(for: c.part) == $0.joint }
            return Step(n: n, part: c.part.label, cue: c.cue,
                        joint: check.map { $0.joint.points($0.side).1 } ?? ExercisePosition.joint(for: c.part),
                        color: Self.pinColors[(n - 1) % 4], check: check)
        }
        for (i, c) in checks.enumerated() where !out.contains(where: { $0.check == c }) {
            out.append(Step(n: (out.map(\.n).max() ?? 0) + 1, part: c.joint.label, cue: "Hold \(c.rangeText) here",
                            joint: c.joint.points(c.side).1, color: Self.arcColors[i % 2], check: c))
        }
        return out
    }

    static func checkJoint(for part: BodyPart) -> PositionJoint? {
        switch part {
        case .knees: .knee
        case .hips: .hip
        case .elbows: .elbow
        case .shoulders: .shoulder
        case .feet: .ankle
        default: nil
        }
    }
    private var mistake: PositionMistake? { PositionMistake.pick(technique?.mistakes ?? []) }
    private var ghost: ExercisePosition.Key? {
        guard showMistake, let mistake else { return nil }
        return mistake.apply(to: position.keys[key], view: position.view, start: position.keys[0])
    }

    static let pinColors: [Color] = [Color(red: 1, green: 0.24, blue: 0.47), Color(red: 1, green: 0.62, blue: 0.11),
                                     Color(red: 0.09, green: 0.78, blue: 0.6), Color(red: 0.36, green: 0.42, blue: 1)]
    static let arcColors: [Color] = [Theme.lime, Color(red: 0.24, green: 0.84, blue: 1)]
    static let mistakeColor = Color(red: 1, green: 0.31, blue: 0.37)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                stage
                stepChips
                keyChips
                cards
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Position")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    // MARK: Stage

    private var stage: some View {
        TimelineView(.animation(paused: snapFrom == nil)) { ctx in
            let y = currentYaw(at: ctx.date)
            GeometryReader { geo in
                let focusPoint = steps.first { $0.n == focus }.flatMap { position.keys[key].point($0.joint) }
                let camera = PositionCamera(position: position, size: geo.size, zoom: zoom, focus: focusPoint)
                ZStack {
                    PositionFigureView(exerciseId: exercise.id, position: position, key: key, ghost: ghost,
                                       highlight: exercise.primary, yaw: y, camera: camera)
                    overlay(camera: camera, yaw: y)
                }
            }
        }
        .frame(height: 400)
        .background(exercise.category.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { v in
                snapFrom = nil
                let base = dragBase ?? yaw
                dragBase = base
                yaw = base + Double(v.translation.width) * 0.012
            }
            .onEnded { _ in dragBase = nil })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in
                let base = pinchBase ?? zoom
                pinchBase = base
                zoom = Self.clampZoom(base * Double(v.magnification))
            }
            .onEnded { _ in pinchBase = nil })
        .overlay(alignment: .top) { snaps.padding(.top, 12) }
        .overlay(alignment: .bottomTrailing) { zoomButtons.padding(10) }
        .overlay(alignment: .bottomLeading) {
            Label("Drag to turn", systemImage: "rotate.3d")
                .font(Theme.label(10)).tracking(1.5).textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
                .padding(14)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(exercise.name), \(ExerciseMotionView.label(key, of: position.keys.count)) position in 3D")
    }

    static let zoomRange = 1.0...3.0
    static func clampZoom(_ z: Double) -> Double { min(zoomRange.upperBound, max(zoomRange.lowerBound, z)) }

    /// Zoom out / in buttons (pinch does the same); the level shows between them and resets on tap.
    private var zoomButtons: some View {
        HStack(spacing: 2) {
            zoomButton("minus", label: "Zoom out", enabled: zoom > Self.zoomRange.lowerBound + 0.01) {
                zoom = Self.clampZoom(zoom / 1.4)
            }
            Button { withAnimation(.snappy) { zoom = 1 } } label: {
                Text(String(format: "%.1f×", zoom))
                    .font(Theme.label(11)).monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(minWidth: 34, minHeight: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset zoom")
            zoomButton("plus", label: "Zoom in", enabled: zoom < Self.zoomRange.upperBound - 0.01) {
                zoom = Self.clampZoom(zoom * 1.4)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.3)))
    }

    private func zoomButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func currentYaw(at date: Date) -> Double {
        guard let from = snapFrom, let target = snapTarget else { return yaw }
        let t = min(1, date.timeIntervalSince(from.at) / 0.45)
        let e = 1 - pow(1 - t, 3)
        if t >= 1 {
            DispatchQueue.main.async {
                yaw = target
                snapFrom = nil
            }
        }
        return from.yaw + (target - from.yaw) * e
    }

    private func snap(to s: Snap) {
        var target = s.yaw
        while target - yaw > .pi { target -= 2 * .pi }
        while yaw - target > .pi { target += 2 * .pi }
        snapTarget = target
        snapFrom = (yaw, Date())
    }

    private var snaps: some View {
        HStack(spacing: 2) {
            ForEach(Snap.allCases, id: \.self) { s in
                let on = abs(remainder(yaw - s.yaw, 2 * .pi)) < 0.05 && snapFrom == nil
                Button { snap(to: s) } label: {
                    Text(s.label)
                        .font(Theme.label(12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(on ? Theme.ink : .white)
                        .background(Capsule().fill(on ? .white : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.label == "¾" ? "Three quarter" : s.label) view")
            }
        }
        .padding(3)
        .background(Capsule().fill(.black.opacity(0.3)))
    }

    /// Callouts (design B, #959): each technique step is a plain-language callout in a column beside the figure,
    /// a dashed leader to its joint and a ring where it is; the angle arcs stay on the joints. With a step in focus
    /// (design C) only that step shows: its ring, its arc and a big gauge.
    private func overlay(camera: PositionCamera, yaw: Double) -> some View {
        let k = position.keys[key]
        let focused = steps.first { $0.n == focus }
        let anchors: [(Step, CGPoint)] = (focused.map { [$0] } ?? steps).compactMap { s in
            k.point(s.joint).map { (s, camera.project($0, yaw: yaw)) }
        }
        let boxes = focused == nil
            ? Self.layoutCallouts(anchors.map(\.1), in: camera.size, top: showMistake ? 86 : 56) : []
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for (i, c) in checks.enumerated() {
                    if let focused, focused.check != c { continue }
                    let (a, j, b) = c.joint.points(c.side)
                    guard let pa = k.point(a), let pj = k.point(j), let pb = k.point(b) else { continue }
                    let A = camera.project(pa, yaw: yaw), J = camera.project(pj, yaw: yaw),
                        B = camera.project(pb, yaw: yaw)
                    var a1 = atan2(A.y - J.y, A.x - J.x), a2 = atan2(B.y - J.y, B.x - J.x)
                    if a2 - a1 > .pi { a2 -= 2 * .pi } else if a1 - a2 > .pi { a1 -= 2 * .pi }
                    var path = Path()
                    path.addArc(center: J, radius: focused == nil ? 24 : 36, startAngle: .radians(a1),
                                endAngle: .radians(a2), clockwise: a2 < a1)
                    ctx.stroke(path, with: .color(focused?.color ?? Self.arcColors[i % 2]),
                               style: StrokeStyle(lineWidth: focused == nil ? 4 : 6, lineCap: .round))
                }
                for (i, (s, p)) in anchors.enumerated() {
                    if i < boxes.count {
                        var leader = Path()
                        leader.move(to: boxes[i].edge)
                        leader.addLine(to: p)
                        ctx.stroke(leader, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)),
                               with: .color(s.color), lineWidth: 3)
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 15, y: p.y - 15, width: 30, height: 30)),
                               with: .color(s.color.opacity(0.35)), lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
            ForEach(Array(anchors.enumerated()), id: \.offset) { i, item in
                if i < boxes.count {
                    callout(item.0).position(boxes[i].center)
                }
            }
            if let focused {
                gauge(focused)
                    .padding(.top, showMistake ? 86 : 52).padding(.leading, 12)
                    .allowsHitTesting(false)
            }
            if showMistake, let mistake, ghost != nil {
                tag("✕ " + Self.short(mistake), color: Self.mistakeColor, dark: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 52).padding(.trailing, 12)
                    .allowsHitTesting(false)
            }
        }
    }

    static let calloutSize = CGSize(width: 118, height: 40)

    /// Callout boxes in two columns (left / right of the stage, by the side their joint is on), in the joints'
    /// vertical order, pushed apart so none overlap, kept between the snaps and the zoom buttons.
    static func layoutCallouts(_ anchors: [CGPoint], in size: CGSize, top: Double) -> [(center: CGPoint, edge: CGPoint)] {
        let w = calloutSize.width, h = calloutSize.height, gap = 6.0, bottom = size.height - 54
        var out = [(center: CGPoint, edge: CGPoint)](repeating: (.zero, .zero), count: anchors.count)
        for left in [true, false] {
            let idx = anchors.indices.filter { (anchors[$0].x < size.width / 2) == left }.sorted { anchors[$0].y < anchors[$1].y }
            guard !idx.isEmpty else { continue }
            var ys = idx.map { min(max(anchors[$0].y - h / 2, top), bottom - h) }
            for i in ys.indices.dropFirst() { ys[i] = max(ys[i], ys[i - 1] + h + gap) }
            if let last = ys.last, last > bottom - h {
                ys[ys.count - 1] = bottom - h
                for i in ys.indices.reversed().dropFirst() { ys[i] = min(ys[i], ys[i + 1] - h - gap) }
            }
            let x = left ? 8 + w / 2 : size.width - 8 - w / 2
            for (j, i) in idx.enumerated() {
                let c = CGPoint(x: x, y: ys[j] + h / 2)
                out[i] = (c, CGPoint(x: left ? x + w / 2 : x - w / 2, y: c.y))
            }
        }
        return out
    }

    private func callout(_ s: Step) -> some View {
        Button { setFocus(s.n) } label: {
            HStack(alignment: .top, spacing: 5) {
                Text("\(s.n)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.3)))
                Text(s.cue)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .frame(width: Self.calloutSize.width, height: Self.calloutSize.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(s.color))
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.part): \(s.cue)")
        .accessibilityHint("Zooms on this step")
    }

    /// The focused step's big gauge: its angle and the range that counts as right, or its cue.
    private func gauge(_ s: Step) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(s.n) · \(s.part.uppercased())")
                .font(Theme.label(10)).tracking(1.5)
                .foregroundStyle(s.color)
            if let c = s.check {
                Text("\(c.degrees)°").font(.system(size: 34, weight: .black, design: .rounded))
                Text("Good: \(c.rangeText) here").font(.caption2.weight(.heavy)).opacity(0.85)
            } else {
                Text(s.cue).font(.caption.weight(.heavy)).lineLimit(3)
                    .frame(maxWidth: 170, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.4)))
    }

    private func setFocus(_ n: Int?) {
        withAnimation(.snappy) {
            focus = n
            zoom = n == nil ? 1 : max(zoom, 2.2)
        }
    }

    private func tag(_ text: String, color: Color, dark: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(dark ? .white : Theme.ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color))
            .fixedSize()
    }

    /// First few words of the mistake for the ghost's tag.
    static func short(_ m: PositionMistake) -> String {
        switch m.kind {
        case .kneesIn: "Knees caving"
        case .roundedBack: "Rounded back"
        case .archedBack: "Arched back"
        case .hipsSag: "Hips sagging"
        case .hipsHigh: "Hips too high"
        case .elbowsFlared: "Elbows flared"
        case .shrug: "Shrugging"
        case .headForward: "Head forward"
        case .halfRange: "Half range"
        }
    }

    // MARK: Below the stage

    /// All + one chip per step (design C): a chip zooms the camera on that step; its cue shows under the chips.
    @ViewBuilder private var stepChips: some View {
        if !steps.isEmpty {
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        stepChip("All", color: .white, on: focus == nil) { setFocus(nil) }
                        ForEach(steps) { s in
                            stepChip("\(s.n) \(s.part)", color: s.color, on: focus == s.n) { setFocus(focus == s.n ? nil : s.n) }
                        }
                    }
                }
                if let f = steps.first(where: { $0.n == focus }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(f.part.uppercased()) · \(ExerciseMotionView.label(key, of: position.keys.count).uppercased())")
                            .font(Theme.label(10)).tracking(1.2).opacity(0.85)
                        Text(f.cue).font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [f.color, f.color.opacity(0.7)], startPoint: .leading, endPoint: .trailing)))
                }
            }
        }
    }

    private func stepChip(_ title: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.label(12))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(on ? Theme.ink : .white)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? AnyShapeStyle(color) : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var keyChips: some View {
        HStack(spacing: 8) {
            ForEach(0..<position.keys.count, id: \.self) { i in
                let on = i == key
                Button { key = i } label: {
                    Text(ExerciseMotionView.label(i, of: position.keys.count))
                        .font(Theme.label(13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(on ? AnyShapeStyle(exercise.category.gradient) : AnyShapeStyle(Theme.cardStrong)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var cards: some View {
        VStack(spacing: 8) {
            if !checks.isEmpty {
                // the angles in one line (design B); tap zooms on the first one
                Button { setFocus(steps.first { $0.check != nil }?.n) } label: {
                    row(icon: Text("✓"), iconColor: Theme.lime,
                        title: checks.map(\.label).joined(separator: " · "),
                        detail: checks.count > 1 ? "Both in the right range for this position. Tap a step to zoom in."
                            : "In the right range for this position. Tap a step to zoom in.",
                        background: AnyShapeStyle(Theme.cardStrong))
                }
                .buttonStyle(.plain)
            }
            if let mistake {
                Button { showMistake.toggle() } label: {
                    row(icon: Text("!"), iconColor: Self.mistakeColor,
                        title: showMistake ? "Hide the common mistake" : "Show the common mistake",
                        detail: mistake.text, background: AnyShapeStyle(showMistake
                            ? AnyShapeStyle(Self.mistakeColor.opacity(0.28)) : AnyShapeStyle(Theme.cardStrong)))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the mistake as a red figure over the right position")
            }
            ForEach(Array((technique?.position ?? []).enumerated()), id: \.offset) { i, c in
                let n = i + 1
                let pinned = pins.contains { $0.0 == n }
                let color = pinned ? Self.pinColors[(n - 1) % 4] : Color.white.opacity(0.12)
                HStack(spacing: 10) {
                    Text(pinned ? "\(n)" : "•")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.25)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.part.label.uppercased()).font(Theme.label(10)).tracking(1).opacity(0.85)
                        Text(c.cue).font(.subheadline.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .leading, endPoint: .trailing)))
                .contentShape(Rectangle())
                .onTapGesture { if pinned { setFocus(n) } }
                .accessibilityAddTraits(pinned ? .isButton : [])
            }
        }
    }

    private func row(icon: Text, iconColor: Color, title: String, detail: String, background: AnyShapeStyle) -> some View {
        HStack(spacing: 10) {
            icon.font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(iconColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.bold))
                Text(detail).font(.caption.weight(.semibold)).opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(background))
    }
}

/// Camera framing all three key positions, and the projection the overlay shares with SceneKit.
struct PositionCamera: Equatable {
    static let fov = 30.0
    static let pitch = 0.16
    let center: SIMD3<Double>
    let distance: Double
    let size: CGSize

    init(position: ExercisePosition, size: CGSize, zoom: Double = 1, focus: SIMD3<Double>? = nil) {
        var lo = SIMD3<Double>(repeating: .greatestFiniteMagnitude), hi = -lo
        for k in position.keys {
            for p in k.joints.values {
                lo = pointwiseMin(lo, p)
                hi = pointwiseMax(hi, p)
            }
        }
        lo.y = min(lo.y, 0)
        center = focus ?? (lo + hi) / 2
        let ext = hi - lo
        // the figure turns: its widest horizontal extent can face the camera
        let horizontal = max(ext.x, ext.z, 120)
        let height = max(ext.y, 120)
        let aspect = max(0.3, Double(size.width / max(size.height, 1)))
        let need = max(height, horizontal / aspect) * 0.5 + 44
        distance = (need / tan(Self.fov * .pi / 360) + max(ext.x, ext.z) * 0.5) / max(zoom, 0.1)
        self.size = size
    }

    /// Screen point of a model point with the figure turned by `yaw`.
    func project(_ p: SIMD3<Double>, yaw: Double) -> CGPoint {
        let q = p - center
        let x = q.x * cos(yaw) + q.z * sin(yaw)
        let z = -q.x * sin(yaw) + q.z * cos(yaw)
        let yc = q.y * cos(Self.pitch) - z * sin(Self.pitch)
        let zc = q.y * sin(Self.pitch) + z * cos(Self.pitch) - distance
        let f = Double(size.height) / 2 / tan(Self.fov * .pi / 360)
        return CGPoint(x: Double(size.width) / 2 + x / -zc * f, y: Double(size.height) / 2 - yc / -zc * f)
    }

    var cameraPosition: SCNVector3 {
        SCNVector3(Float(center.x), Float(center.y + distance * sin(Self.pitch)), Float(center.z + distance * cos(Self.pitch)))
    }
}

/// The posed body (grey anatomy figure, worked muscles in orange-red tissue), the equipment and the red
/// mistake ghost. Poses are skinned off the main thread and kept per exercise / key / ghost; the clay mannequin
/// stands in while a pose is being built or when the body resource is missing.
struct PositionFigureView: UIViewRepresentable {
    let exerciseId: String
    let position: ExercisePosition
    let key: Int
    let ghost: ExercisePosition.Key?
    let highlight: [Muscle]
    let yaw: Double
    let camera: PositionCamera

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        view.isUserInteractionEnabled = false
        context.coordinator.setUp(view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(exerciseId: exerciseId, position: position, key: key, ghost: ghost,
                                   highlight: highlight, yaw: yaw, camera: camera)
    }

    @MainActor final class Coordinator {
        private let scene = SCNScene()
        private let turntable = SCNNode()
        private let cameraNode = SCNNode()
        private var built: String?
        private var building: Task<Void, Never>?
        private weak var view: SCNView?
        /// Skinned poses by exercise | key | ghost | worked muscles (a pose is ~50 ms to build).
        private static var poses: [String: BodyStage.Mesh] = [:]

        func setUp(_ view: SCNView) {
            self.view = view
            view.scene = scene
            let cam = SCNCamera()
            cam.fieldOfView = PositionCamera.fov
            cam.zNear = 5
            cam.zFar = 5000
            cameraNode.camera = cam
            scene.rootNode.addChildNode(cameraNode)
            scene.rootNode.addChildNode(turntable)
            view.pointOfView = cameraNode
            for n in BodyStage.lights() { scene.rootNode.addChildNode(n) }
        }

        func update(exerciseId: String, position: ExercisePosition, key: Int, ghost: ExercisePosition.Key?,
                    highlight: [Muscle], yaw: Double, camera: PositionCamera) {
            let worked = highlight.map(\.rawValue).sorted().joined(separator: ",")
            let ghostSig = ghost.map { "\($0.joints.count)\($0.joints["hip"] ?? .zero)\($0.joints["kneeN"] ?? .zero)" } ?? ""
            let id = "\(exerciseId)|\(key)|\(ghostSig)|\(worked)"
            if id != built {
                built = id
                building?.cancel()
                let k = position.keys[key]
                turntable.childNodes.forEach { $0.removeFromParentNode() }
                turntable.addChildNode(Mannequin.floor(around: k))
                turntable.addChildNode(Mannequin.props(k.props))
                if let mesh = Self.poses[id] {
                    turntable.addChildNode(BodyStage.node(mesh))
                } else if let rig = BodyRig.shared {
                    // clay stands in until the skinned pose is ready
                    let stand = Mannequin.figure(k, highlight: Mannequin.tinted(highlight), ghost: false)
                    turntable.addChildNode(stand)
                    if let ghost { turntable.addChildNode(Mannequin.figure(ghost, highlight: [], ghost: true)) }
                    let muscles = highlight
                    building = Task { [weak self] in
                        let mesh = await Task.detached(priority: .userInitiated) {
                            BodyStage.build(rig, key: k, ghost: ghost, worked: muscles)
                        }.value
                        guard let self, !Task.isCancelled, self.built == id else { return }
                        Self.poses[id] = mesh
                        if Self.poses.count > 24 { Self.poses.removeValue(forKey: Self.poses.keys.first!) }
                        self.turntable.childNodes.forEach { $0.removeFromParentNode() }
                        self.turntable.addChildNode(Mannequin.floor(around: k))
                        self.turntable.addChildNode(Mannequin.props(k.props))
                        self.turntable.addChildNode(BodyStage.node(mesh))
                        self.view?.setNeedsDisplay()
                    }
                } else {
                    turntable.addChildNode(Mannequin.figure(k, highlight: Mannequin.tinted(highlight), ghost: false))
                    if let ghost { turntable.addChildNode(Mannequin.figure(ghost, highlight: [], ghost: true)) }
                }
            }
            // the turntable turns around the framing centre
            turntable.simdTransform = Self.turn(yaw, around: camera.center)
            cameraNode.position = camera.cameraPosition
            cameraNode.look(at: SCNVector3(Float(camera.center.x), Float(camera.center.y), Float(camera.center.z)))
            view?.setNeedsDisplay()
        }

        /// Rotation about the vertical axis through `c`, mapping `c` to itself. Matches `PositionCamera.project`.
        static func turn(_ yaw: Double, around c: SIMD3<Double>) -> simd_float4x4 {
            let r = simd_float4x4(simd_quatf(angle: Float(yaw), axis: SIMD3(0, 1, 0)))
            let cf = SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z))
            var t1 = matrix_identity_float4x4, t2 = matrix_identity_float4x4
            t1.columns.3 = SIMD4(-cf.x, -cf.y, -cf.z, 1)
            t2.columns.3 = SIMD4(cf.x, cf.y, cf.z, 1)
            return t2 * r * t1
        }
    }
}

/// The skinned body on stage (look B, anatomy): a grey sculpted figure with dark grooves between muscles and fibres on
/// every muscle, the worked muscles in orange-red tissue, black shorts, studio key light with shadows. Built from `BodyRig`.
enum BodyStage {
    /// A posed body ready to turn into geometry: vertex attributes packed for the shader.
    struct Mesh: Sendable {
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        /// (cavity −1…1, fibre phase 0…2π)
        var tex0: [SIMD2<Float>]
        /// (worked-muscle weight 0…1, shorts 0/1)
        var tex1: [SIMD2<Float>]
        var triangles: [UInt16]
        /// The mistake ghost, posed on the same body.
        var ghost: [SIMD3<Float>]?
        var ghostNormals: [SIMD3<Float>]?
    }

    static func build(_ rig: BodyRig, key: ExercisePosition.Key, ghost: ExercisePosition.Key?, worked: [Muscle]) -> Mesh {
        let pose = rig.pose(key)
        let work = rig.work(worked)
        var tex0 = [SIMD2<Float>](), tex1 = [SIMD2<Float>]()
        tex0.reserveCapacity(rig.vertexCount); tex1.reserveCapacity(rig.vertexCount)
        for i in 0..<rig.vertexCount {
            tex0.append(SIMD2(rig.cavity[i], rig.phase[i]))
            // y: 0 plain skin (head, hands, feet), 0.5 muscle, 1 shorts
            tex1.append(SIMD2(work[i], rig.shorts[i] ? 1 : (rig.muscle[i] > 0 ? 0.5 : 0)))
        }
        let g = ghost.map { rig.pose($0, mush: 4) }
        return Mesh(positions: pose.positions, normals: pose.normals, tex0: tex0, tex1: tex1, triangles: rig.triangles,
                    ghost: g?.positions, ghostNormals: g?.normals)
    }

    static func source<T>(_ a: [T], _ semantic: SCNGeometrySource.Semantic, components: Int) -> SCNGeometrySource {
        let data = a.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: a.count, usesFloatComponents: true,
                                 componentsPerVector: components, bytesPerComponent: MemoryLayout<Float>.size,
                                 dataOffset: 0, dataStride: MemoryLayout<T>.stride)
    }

    static func geometry(_ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>], tex0: [SIMD2<Float>]?,
                         tex1: [SIMD2<Float>]?, triangles: [UInt16]) -> SCNGeometry {
        var sources = [source(positions, .vertex, components: 3), source(normals, .normal, components: 3)]
        if let tex0 { sources.append(source(tex0, .texcoord, components: 2)) }
        if let tex1 { sources.append(source(tex1, .texcoord, components: 2)) }
        let element = SCNGeometryElement(data: triangles.withUnsafeBufferPointer { Data(buffer: $0) },
                                         primitiveType: .triangles, primitiveCount: triangles.count / 3,
                                         bytesPerIndex: MemoryLayout<UInt16>.size)
        return SCNGeometry(sources: sources, elements: [element])
    }

    /// Body (and ghost) nodes for a built pose.
    static func node(_ m: Mesh) -> SCNNode {
        let root = SCNNode()
        let body = SCNNode(geometry: geometry(m.positions, m.normals, tex0: m.tex0, tex1: m.tex1, triangles: m.triangles))
        body.geometry?.firstMaterial = skin()
        body.castsShadow = true
        root.addChildNode(body)
        if let g = m.ghost, let gn = m.ghostNormals {
            let ghost = SCNNode(geometry: geometry(g, gn, tex0: nil, tex1: nil, triangles: m.triangles))
            ghost.geometry?.firstMaterial = Mannequin.material(Mannequin.ghostRed, ghost: true)
            ghost.castsShadow = false
            ghost.renderingOrder = 10
            root.addChildNode(ghost)
        }
        return root
    }

    /// Anatomy material (look B, #408): grey sculpted figure, dark grooves between muscles, fine fibres on every
    /// muscle, worked muscles in orange-red tissue, black shorts. Colours in the shader are linear.
    static func skin() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.71, green: 0.72, blue: 0.75, alpha: 1)
        m.roughness.contents = 0.62
        m.metalness.contents = 0.0
        m.isDoubleSided = false
        m.shaderModifiers = [.geometry: geometryModifier, .surface: surfaceModifier]
        return m
    }

    static let geometryModifier = """
    #pragma varyings
    float4 vAtt;
    #pragma body
    out.vAtt = float4(_geometry.texcoords[0].x, _geometry.texcoords[0].y, _geometry.texcoords[1].x, _geometry.texcoords[1].y);
    """

    static let surfaceModifier = """
    #pragma body
    float cav = in.vAtt.x;
    float ph = in.vAtt.y;
    float w = in.vAtt.z;
    float sh = step(0.75, in.vAtt.w);
    float mu = step(0.25, in.vAtt.w) * (1.0 - sh);
    float cv = smoothstep(-0.95, 0.4, cav);
    // grey sculpt: grooves and muscle borders go dark (borders are baked into the cavity)
    float3 col = float3(0.456, 0.474, 0.52) * mix(float3(0.22, 0.22, 0.25), float3(1.0), pow(cv, 0.8));
    // fine fibres on every muscle; the phase wraps at 2 pi, so only whole multiples of it stay seamless
    float f1 = pow(0.5 + 0.5 * sin(ph * 3.0), 4.0);
    col *= 1.0 - 0.13 * f1 * mu * smoothstep(0.0, 0.5, cv);
    // worked muscles: orange-red tissue with the same fibres
    float wq = smoothstep(0.1, 0.8, w);
    float3 tissue = mix(float3(0.62, 0.10, 0.05), float3(1.0, 0.40, 0.18), pow(0.5 + 0.5 * sin(ph * 3.0), 1.2));
    tissue *= mix(0.55, 1.0, cv);
    col = mix(col, tissue, wq * 0.95 * (1.0 - sh));
    float3 shorts = float3(0.07, 0.07, 0.08) * mix(0.6, 1.0, cv);
    col = mix(col, shorts, sh);
    _surface.diffuse.rgb = col;
    _surface.roughness = mix(0.62, 0.85, sh);
    _surface.emission.rgb += float3(0.55, 0.08, 0.03) * wq * 0.10 * (1.0 - sh);
    """

    /// Studio lighting: warm key with soft shadows, cool fill, two rims to carve the muscles, a little ambient.
    static func lights() -> [SCNNode] {
        var out = [SCNNode]()
        func add(_ type: SCNLight.LightType, _ color: UIColor, _ intensity: CGFloat, _ pos: SCNVector3) -> SCNLight {
            let l = SCNLight()
            l.type = type
            l.color = color
            l.intensity = intensity
            let n = SCNNode()
            n.light = l
            n.position = pos
            n.look(at: SCNVector3(0, 90, 0))
            out.append(n)
            return l
        }
        let key = add(.spot, UIColor(red: 1, green: 0.94, blue: 0.86, alpha: 1), 2600, SCNVector3(-260, 470, 260))
        key.spotInnerAngle = 25
        key.spotOuterAngle = 70
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.shadowSampleCount = 8
        key.shadowRadius = 3
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        key.zNear = 50
        key.zFar = 1500
        _ = add(.directional, UIColor(red: 0.62, green: 0.71, blue: 1, alpha: 1), 180, SCNVector3(420, 120, 180))
        _ = add(.directional, UIColor(red: 1, green: 0.84, blue: 0.72, alpha: 1), 1100, SCNVector3(180, 300, -420))
        _ = add(.directional, UIColor(red: 0.87, green: 0.91, blue: 1, alpha: 1), 650, SCNVector3(-420, 220, -260))
        _ = add(.ambient, UIColor(red: 1, green: 0.93, blue: 0.9, alpha: 1), 160, SCNVector3Zero)
        return out
    }
}

/// SceneKit pieces of the guide's figure: capsule limbs on a clay body, headband, equipment.
enum Mannequin {
    enum Part: Hashable { case thigh, shin, upperArm, forearm, torso }

    static let clay = UIColor(red: 0.93, green: 0.89, blue: 0.85, alpha: 1)
    static let load = UIColor(red: 1, green: 0.29, blue: 0.45, alpha: 1)
    static let ghostRed = UIColor(red: 1, green: 0.2, blue: 0.25, alpha: 1)

    /// Body parts that light up for the worked muscles.
    static func tinted(_ muscles: [Muscle]) -> Set<Part> {
        var out = Set<Part>()
        for m in muscles {
            switch m {
            case .quads, .hamstrings, .glutes, .gluteMed, .adductors, .hipFlexors: out.insert(.thigh)
            case .calves, .soleus, .tibialis: out.insert(.shin)
            case .frontDelts, .sideDelts, .rearDelts, .rotatorCuff, .biceps, .triceps, .brachialis: out.insert(.upperArm)
            case .forearms, .forearmExtensors: out.insert(.forearm)
            default: out.insert(.torso)
            }
        }
        return out
    }

    static func material(_ color: UIColor, ghost: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = 0.6
        m.metalness.contents = 0.0
        if ghost {
            m.transparency = 0.42
            m.writesToDepthBuffer = false
            m.blendMode = .alpha
        }
        return m
    }

    static func v(_ p: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(p.x), Float(p.y), Float(p.z)) }

    /// Capsule from a to b.
    static func capsule(_ a: SIMD3<Double>, _ b: SIMD3<Double>, r: Double, _ m: SCNMaterial) -> SCNNode {
        let d = v(b) - v(a)
        let len = simd_length(d)
        let g = SCNCapsule(capRadius: CGFloat(r), height: CGFloat(Double(len) + 2 * r))
        g.radialSegmentCount = 18
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = (v(a) + v(b)) / 2
        if len > 0.01 { n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: d / len) }
        return n
    }

    static func cylinder(_ a: SIMD3<Double>, _ b: SIMD3<Double>, r: Double, _ m: SCNMaterial) -> SCNNode {
        let d = v(b) - v(a)
        let len = simd_length(d)
        let g = SCNCylinder(radius: CGFloat(r), height: CGFloat(len))
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = (v(a) + v(b)) / 2
        if len > 0.01 { n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: d / len) }
        return n
    }

    static func figure(_ k: ExercisePosition.Key, highlight: Set<Part>, ghost: Bool) -> SCNNode {
        let root = SCNNode()
        let base = material(ghost ? ghostRed : clay, ghost: ghost)
        let lit = material(ghost ? ghostRed : load, ghost: ghost)
        func mat(_ p: Part) -> SCNMaterial { highlight.contains(p) ? lit : base }
        func bone(_ a: String, _ b: String, _ r: Double, _ m: SCNMaterial) {
            guard let pa = k[a], let pb = k[b] else { return }
            root.addChildNode(capsule(pa, pb, r: r, m))
        }
        for s in ["N", "F"] {
            bone("hip" + s, "knee" + s, 8.5, mat(.thigh))
            bone("knee" + s, "ankle" + s, 6.2, mat(.shin))
            bone("ankle" + s, "toe" + s, 4.2, base)
            bone("shoulder" + s, "elbow" + s, 5.6, mat(.upperArm))
            bone("elbow" + s, "wrist" + s, 4.6, mat(.forearm))
            bone("wrist" + s, "hand" + s, 3.8, base)
        }
        bone("hipN", "hipF", 9.5, mat(.torso))
        bone("shoulderN", "shoulderF", 8, mat(.torso))
        if let hip = k["hip"], let sh = k["shoulder"] {
            root.addChildNode(capsule(hip + (sh - hip) * 0.12, sh - (sh - hip) * 0.08, r: 12.5, mat(.torso)))
        }
        bone("shoulder", "neck", 5, base)
        if let head = k["head"] {
            let h = SCNNode(geometry: SCNSphere(radius: 13))
            h.geometry?.firstMaterial = base
            h.simdPosition = v(head)
            root.addChildNode(h)
            if !ghost, let neck = k["neck"] {
                // headband: pink ring around the forehead, square to the neck → head line
                let band = SCNTorus(ringRadius: 12.6, pipeRadius: 2.2)
                band.firstMaterial = material(UIColor(red: 1, green: 0.18, blue: 0.58, alpha: 1), ghost: false)
                let b = SCNNode(geometry: band)
                let up = simd_normalize(v(head) - v(neck))
                b.simdPosition = v(head) + up * 3
                b.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: up)
                root.addChildNode(b)
            }
        }
        return root
    }

    static func floor(around k: ExercisePosition.Key) -> SCNNode {
        let xs = k.joints.values.map(\.x), zs = k.joints.values.map(\.z)
        let cx = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, cz = ((zs.min() ?? 0) + (zs.max() ?? 0)) / 2
        // studio disc: dark, matte, catches the key light's shadow
        let g = SCNCylinder(radius: 150, height: 1)
        let m = material(UIColor(red: 0.16, green: 0.17, blue: 0.2, alpha: 1), ghost: false)
        m.roughness.contents = 0.95
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = SIMD3(Float(cx), -0.6, Float(cz))
        n.castsShadow = false
        return n
    }

    static func props(_ props: [ExercisePosition.Prop]) -> SCNNode {
        let root = SCNNode()
        let steel = material(UIColor(red: 0.36, green: 0.39, blue: 0.43, alpha: 1), ghost: false)
        steel.metalness.contents = 0.7
        steel.roughness.contents = 0.35
        let pad = material(UIColor(red: 0.16, green: 0.17, blue: 0.2, alpha: 1), ghost: false)
        let iron = material(UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1), ghost: false)
        let wood = material(UIColor(red: 0.36, green: 0.27, blue: 0.2, alpha: 1), ghost: false)
        let mat = material(UIColor(red: 0.18, green: 0.43, blue: 0.56, alpha: 1), ghost: false)
        for p in props {
            switch p {
            case let .rod(a, b, r, _):
                root.addChildNode(cylinder(a, b, r: max(r, 1.6), steel))
            case let .pad(a, b, normal, halfWidth):
                let along = v(b) - v(a)
                let len = simd_length(along)
                guard len > 1 else { continue }
                let n = SIMD3<Float>(Float(normal.x), Float(normal.y), 0)
                let t = simd_length(n)
                let depth = halfWidth > 0 ? Float(halfWidth * 2) : 34
                let g = SCNBox(width: CGFloat(len), height: CGFloat(max(t, 4)), length: CGFloat(depth), chamferRadius: 3)
                g.firstMaterial = pad
                let node = SCNNode(geometry: g)
                let x = along / len
                let y = t > 0 ? n / t : SIMD3<Float>(0, 1, 0)
                var z = simd_cross(x, y)
                if simd_length(z) < 0.01 { z = SIMD3(0, 0, 1) }
                z = simd_normalize(z)
                let yy = simd_cross(z, x)
                node.simdOrientation = simd_quatf(simd_float3x3(columns: (x, yy, z)))
                node.simdPosition = (v(a) + v(b)) / 2 + n / 2
                root.addChildNode(node)
            case let .box(lo, hi, isMat):
                let s = v(hi) - v(lo)
                let g = SCNBox(width: CGFloat(max(s.x, 1)), height: CGFloat(max(s.y, 1)), length: CGFloat(max(s.z, 1)),
                               chamferRadius: isMat ? 1 : 3)
                g.firstMaterial = isMat ? mat : (s.y > 60 ? iron : wood)
                let node = SCNNode(geometry: g)
                node.simdPosition = (v(lo) + v(hi)) / 2
                root.addChildNode(node)
            case let .disc(c, r, alongX):
                let g = SCNCylinder(radius: CGFloat(r), height: 5)
                g.firstMaterial = iron
                let node = SCNNode(geometry: g)
                node.simdPosition = v(c)
                node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: alongX ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1))
                root.addChildNode(node)
            case let .weight(kind, c, r0, axis, _):
                let r = r0 > 0 ? min(r0, 9) : 8
                if kind == "db" {
                    // knurled handle along the grip axis, a head at each end
                    let ax = axis.map(simd_normalize) ?? SIMD3(0, 0, 1)
                    let hw = r * 1.15, hr = r * 0.62, hl = r * 0.6
                    root.addChildNode(cylinder(c - ax * hw, c + ax * hw, r: 1.6, steel))
                    for s in [-1.0, 1.0] {
                        let mid = c + ax * (s * (hw - hl / 2))
                        root.addChildNode(cylinder(mid - ax * (hl / 2), mid + ax * (hl / 2), r: hr, iron))
                    }
                } else if kind == "kb" {
                    // bell below the hand, half-torus handle through it
                    let rb = r * 0.8
                    let ball = SCNNode(geometry: SCNSphere(radius: CGFloat(rb)))
                    ball.geometry?.firstMaterial = iron
                    ball.simdPosition = v(c) + SIMD3(0, Float(-rb * 0.9), 0)
                    root.addChildNode(ball)
                    let handle = SCNTorus(ringRadius: CGFloat(rb * 0.75), pipeRadius: 1.5)
                    handle.firstMaterial = steel
                    let h = SCNNode(geometry: handle)
                    h.simdPosition = v(c) + SIMD3(0, Float(-rb * 0.1), 0)
                    h.simdOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
                    root.addChildNode(h)
                } else if kind == "roller" || kind == "foam" {
                    // padded machine roller / foam roller across the machine
                    let ax = axis.map(simd_normalize) ?? SIMD3(0, 0, 1)
                    let half = kind == "foam" ? 30.0 : 18.0
                    let foam = material(UIColor(red: 0.17, green: 0.44, blue: 0.72, alpha: 1), ghost: false)
                    root.addChildNode(cylinder(c - ax * half, c + ax * half, r: r0 > 0 ? r0 : 7, kind == "foam" ? foam : pad))
                } else {
                    let g = SCNSphere(radius: CGFloat(r))
                    g.firstMaterial = kind == "ball"
                        ? material(UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1), ghost: false) : iron
                    let node = SCNNode(geometry: g)
                    node.simdPosition = v(c)
                    root.addChildNode(node)
                }
            }
        }
        return root
    }
}

/// Wide gradient button that opens the guide (exercise page and the player's Form sheet).
struct PositionGuideLink: View {
    let exercise: Exercise

    var body: some View {
        if let position = exercise.position {
            NavigationLink {
                PositionGuideView(exercise: exercise, position: position)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "rotate.3d")
                        .font(.title3.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Position guide").font(Theme.display(19))
                        Text("Right position in 3D, joint angles, common mistake")
                            .font(.caption.weight(.semibold)).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.body.weight(.heavy))
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(
                    LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 1), Color(red: 0.65, green: 0.3, blue: 1),
                                            Color(red: 1, green: 0.31, blue: 0.64)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("position-guide")
        }
    }
}
