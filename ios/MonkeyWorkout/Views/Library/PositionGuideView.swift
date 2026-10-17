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
                let camera = PositionCamera(position: position, size: geo.size)
                ZStack {
                    PositionFigureView(position: position, key: key, ghost: ghost, highlight: exercise.primary,
                                       yaw: y, camera: camera)
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
        .overlay(alignment: .top) { snaps.padding(.top, 12) }
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

    /// Pins, angle arcs and the mistake label, placed on the projected joints.
    private func overlay(camera: PositionCamera, yaw: Double) -> some View {
        let k = position.keys[key]
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for (i, c) in checks.enumerated() {
                    let (a, j, b) = c.joint.points(c.side)
                    guard let pa = k.point(a), let pj = k.point(j), let pb = k.point(b) else { continue }
                    let A = camera.project(pa, yaw: yaw), J = camera.project(pj, yaw: yaw),
                        B = camera.project(pb, yaw: yaw)
                    var a1 = atan2(A.y - J.y, A.x - J.x), a2 = atan2(B.y - J.y, B.x - J.x)
                    if a2 - a1 > .pi { a2 -= 2 * .pi } else if a1 - a2 > .pi { a1 -= 2 * .pi }
                    var path = Path()
                    path.addArc(center: J, radius: 24, startAngle: .radians(a1), endAngle: .radians(a2),
                                clockwise: a2 < a1)
                    ctx.stroke(path, with: .color(Self.arcColors[i % 2]),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
            .allowsHitTesting(false)
            ForEach(Array(checks.enumerated()), id: \.offset) { i, c in
                if let pj = k.point(c.joint.points(c.side).1) {
                    let p = camera.project(pj, yaw: yaw)
                    tag(c.label, color: Self.arcColors[i % 2], dark: false)
                        .position(x: p.x + (i == 0 ? 52 : -52), y: p.y - 22)
                }
            }
            ForEach(pins, id: \.0) { n, c in
                if let pj = k.point(ExercisePosition.joint(for: c.part)) {
                    let p = camera.project(pj, yaw: yaw)
                    Text("\(n)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white))
                        .overlay(Circle().strokeBorder(Self.pinColors[(n - 1) % 4], lineWidth: 3))
                        .shadow(color: .black.opacity(0.35), radius: 4)
                        .position(x: p.x + 16, y: p.y - 4)
                }
            }
            if showMistake, let mistake, ghost != nil {
                tag("✕ " + Self.short(mistake), color: Self.mistakeColor, dark: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 52).padding(.trailing, 12)
            }
        }
        .allowsHitTesting(false)
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
            ForEach(Array(checks.enumerated()), id: \.offset) { i, c in
                row(icon: Text("✓"), iconColor: Self.arcColors[i % 2], title: "\(c.joint.label) \(c.rangeText)",
                    detail: "This position: \(c.degrees)°. The arc shows the angle to hold.",
                    background: AnyShapeStyle(Theme.cardStrong))
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
                        .background(Circle().fill(.white.opacity(0.25)))
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
            }
        }
    }

    private func row(icon: Text, iconColor: Color, title: String, detail: String, background: AnyShapeStyle) -> some View {
        HStack(spacing: 10) {
            icon.font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(iconColor))
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

    init(position: ExercisePosition, size: CGSize) {
        var lo = SIMD3<Double>(repeating: .greatestFiniteMagnitude), hi = -lo
        for k in position.keys {
            for p in k.joints.values {
                lo = pointwiseMin(lo, p)
                hi = pointwiseMax(hi, p)
            }
        }
        lo.y = min(lo.y, 0)
        center = (lo + hi) / 2
        let ext = hi - lo
        // the figure turns: its widest horizontal extent can face the camera
        let horizontal = max(ext.x, ext.z, 120)
        let height = max(ext.y, 120)
        let aspect = max(0.3, Double(size.width / max(size.height, 1)))
        let need = max(height, horizontal / aspect) * 0.5 + 34
        distance = need / tan(Self.fov * .pi / 360) + max(ext.x, ext.z) * 0.5
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

/// The posed clay figure (headband head, worked muscles tinted), the equipment and the red mistake ghost.
struct PositionFigureView: UIViewRepresentable {
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
        context.coordinator.update(position: position, key: key, ghost: ghost, highlight: highlight, yaw: yaw,
                                   camera: camera)
    }

    @MainActor final class Coordinator {
        private let scene = SCNScene()
        private let turntable = SCNNode()
        private let cameraNode = SCNNode()
        private var built: String?
        private weak var view: SCNView?

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
            for (type, color, intensity, pos) in [
                (SCNLight.LightType.ambient, UIColor.white, CGFloat(450), SCNVector3Zero),
                (.directional, .white, 1250, SCNVector3(-300, 500, 500)),
                (.directional, UIColor(red: 1, green: 0.55, blue: 0.85, alpha: 1), 550, SCNVector3(400, 150, -400)),
            ] {
                let l = SCNLight()
                l.type = type
                l.color = color
                l.intensity = intensity
                let n = SCNNode()
                n.light = l
                n.position = pos
                n.look(at: SCNVector3Zero)
                scene.rootNode.addChildNode(n)
            }
        }

        func update(position: ExercisePosition, key: Int, ghost: ExercisePosition.Key?, highlight: [Muscle], yaw: Double,
                    camera: PositionCamera) {
            let id = "\(key)|\(ghost.map { "\($0.joints.count)\($0.joints["hip"] ?? .zero)\($0.joints["kneeN"] ?? .zero)" } ?? "")"
            if id != built {
                built = id
                turntable.childNodes.forEach { $0.removeFromParentNode() }
                let k = position.keys[key]
                turntable.addChildNode(Mannequin.floor(around: k))
                turntable.addChildNode(Mannequin.props(k.props))
                turntable.addChildNode(Mannequin.figure(k, highlight: Mannequin.tinted(highlight), ghost: false))
                if let ghost { turntable.addChildNode(Mannequin.figure(ghost, highlight: [], ghost: true)) }
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
        let g = SCNCylinder(radius: 150, height: 1)
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(white: 0, alpha: 0.22)
        m.lightingModel = .constant
        m.writesToDepthBuffer = false
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = SIMD3(Float(cx), -1, Float(cz))
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
            case let .rod(a, b, r):
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
            case let .weight(kind, c, r):
                if kind == "db" {
                    for s in [-1.0, 1.0] {
                        let a = c + SIMD3(0, 0, s * 9), b = c + SIMD3(0, 0, s * 15)
                        root.addChildNode(cylinder(a, b, r: r, iron))
                    }
                    root.addChildNode(cylinder(c - SIMD3(0, 0, 10), c + SIMD3(0, 0, 10), r: 2, steel))
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
