import SceneKit
import SwiftUI
import UIKit
import WorkoutEngine

/// Look of the 3D body map (#225); designs in project files `3d-body-map/`.
enum BodyMap3DStyle: String, CaseIterable, Identifiable {
    /// Dark sculpted figure in the 2D map's heat colours.
    case clay
    /// Neon body on a dark stage, slow auto-spin.
    case holo
    /// Glossy white figure on a bold gradient.
    case studio
    var id: String { rawValue }
    static let storageKey = "bodyMap3DStyle"
}

/// 2D or 3D body map on Explore → Muscles (#225). Member setting; 2D is the default.
enum BodyMapMode: String, CaseIterable, Identifiable {
    case flat = "2d", solid = "3d"
    var id: String { rawValue }
    var label: String { self == .flat ? "2D" : "3D" }
    static let storageKey = "bodyMapMode"
}

/// 3D figure built from the 2D body map (`BodyMesh`): drag to turn, pinch to zoom, double-tap to reset, tap a muscle to
/// pick it. Colours are the 2D map's, drawn onto the figure as textures.
struct BodyMap3DView: UIViewRepresentable {
    var heat: [Muscle: Double]
    var selected: Muscle?
    var style: BodyMap3DStyle = .clay
    /// Turn to show a side: 0 front, 90 right side, 180 back (snap buttons). Changing it animates.
    var yaw: Double = 0
    var onTap: (Muscle) -> Void
    @Environment(\.bodyFigure) private var figure

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        let c = context.coordinator
        c.view = view
        c.onTap = onTap
        c.setUp(style: style)
        view.addGestureRecognizer(UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))))
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.reset(_:)))
        double.numberOfTapsRequired = 2
        view.addGestureRecognizer(double)
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: double)
        view.addGestureRecognizer(tap)
        c.update(figure: figure, heat: heat, selected: selected, style: style, yaw: yaw)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.update(figure: figure, heat: heat, selected: selected, style: style, yaw: yaw)
    }

    @MainActor final class Coordinator: NSObject {
        weak var view: SCNView?
        var onTap: ((Muscle) -> Void)?
        private let scene = SCNScene()
        /// Turns (yaw); holds the body centred on its middle.
        private let turntable = SCNNode()
        /// Tilts (pitch) inside the turntable.
        private let tilt = SCNNode()
        private let frontNode = SCNNode(), backNode = SCNNode()
        private let cameraNode = SCNNode()
        private var figure: BodyFigure?
        private var key: String?
        private var style: BodyMap3DStyle?
        private var yaw = 0.0, pitch = 0.0, distance = Coordinator.homeDistance
        private var requestedYaw: Double?
        private var build: Task<Void, Never>?

        static let homeDistance = 1060.0

        func setUp(style: BodyMap3DStyle) {
            view?.scene = scene
            let camera = SCNCamera()
            camera.fieldOfView = 28
            camera.zNear = 10
            camera.zFar = 4000
            cameraNode.camera = camera
            scene.rootNode.addChildNode(cameraNode)
            placeCamera()
            view?.pointOfView = cameraNode
            tilt.position = SCNVector3(0, -Float(BodyMapLayout.height) / 2, 0)
            tilt.addChildNode(frontNode)
            tilt.addChildNode(backNode)
            turntable.addChildNode(tilt)
            scene.rootNode.addChildNode(turntable)
        }

        private func placeCamera() {
            cameraNode.position = SCNVector3(0, 6, Float(distance))
            cameraNode.look(at: SCNVector3(0, 6, 0))
        }

        func update(figure: BodyFigure, heat: [Muscle: Double], selected: Muscle?, style: BodyMap3DStyle, yaw: Double) {
            if self.style != style {
                self.style = style
                applyLights(style)
                key = nil
            }
            if requestedYaw != yaw {
                let first = requestedYaw == nil
                requestedYaw = yaw
                turn(to: yaw * .pi / 180, animated: !first)
            }
            if self.figure != figure {
                self.figure = figure
                key = nil
                let fig = figure
                build?.cancel()
                build = Task { [weak self] in
                    let mesh = await Task.detached(priority: .userInitiated) { BodyMesh.of(fig) }.value
                    guard let self, !Task.isCancelled, self.figure == fig else { return }
                    self.frontNode.geometry = Self.geometry(mesh.front)
                    self.backNode.geometry = Self.geometry(mesh.back)
                    self.key = nil
                    self.paint(figure: fig, heat: heat, selected: selected, style: style)
                    if style == .holo { self.spin() }
                }
                return
            }
            paint(figure: figure, heat: heat, selected: selected, style: style)
        }

        private func paint(figure: BodyFigure, heat: [Muscle: Double], selected: Muscle?, style: BodyMap3DStyle) {
            guard frontNode.geometry != nil else { return }
            let newKey = "\(figure)|\(style)|\(selected?.rawValue ?? "")|" + heat.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue)=\(Int($0.value * 100))" }.joined(separator: ",")
            guard newKey != key else { return }
            key = newKey
            for (node, side) in [(frontNode, BodySide.front), (backNode, .back)] {
                let image = BodyTexture.image(side: side, figure: figure, heat: heat, selected: selected, style: style)
                node.geometry?.firstMaterial = Self.material(image, style: style)
            }
        }

        private static func material(_ image: UIImage, style: BodyMap3DStyle) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = image
            m.isDoubleSided = false
            switch style {
            case .clay:
                m.roughness.contents = 0.62
                m.metalness.contents = 0.0
            case .holo:
                m.roughness.contents = 0.3
                m.metalness.contents = 0.35
                m.emission.contents = image
                m.emission.intensity = 0.75
                m.transparency = 0.95
            case .studio:
                m.roughness.contents = 0.32
                m.metalness.contents = 0.0
                m.clearCoat.contents = 0.8
                m.clearCoatRoughness.contents = 0.2
            }
            return m
        }

        private func applyLights(_ style: BodyMap3DStyle) {
            scene.rootNode.childNodes.filter { $0.light != nil }.forEach { $0.removeFromParentNode() }
            scene.rootNode.childNodes.filter { $0.name == "stage" }.forEach { $0.removeFromParentNode() }
            func add(_ type: SCNLight.LightType, _ color: UIColor, _ intensity: CGFloat, _ position: SCNVector3? = nil) {
                let l = SCNLight()
                l.type = type
                l.color = color
                l.intensity = intensity
                let n = SCNNode()
                n.light = l
                if let position {
                    n.position = position
                    n.look(at: SCNVector3Zero)
                }
                scene.rootNode.addChildNode(n)
            }
            switch style {
            case .clay:
                add(.ambient, UIColor(white: 1, alpha: 1), 420)
                add(.directional, .white, 1300, SCNVector3(-300, 400, 500))
                add(.directional, UIColor(red: 0.6, green: 0.42, blue: 1, alpha: 1), 700, SCNVector3(400, 100, -400))
            case .holo:
                add(.ambient, UIColor(red: 0.55, green: 0.55, blue: 1, alpha: 1), 380)
                add(.directional, UIColor(red: 0.4, green: 1, blue: 1, alpha: 1), 900, SCNVector3(300, 200, 500))
                // Floor rings under the feet.
                let stage = SCNNode()
                stage.name = "stage"
                for i in 1...4 {
                    let ring = SCNTube(innerRadius: CGFloat(i) * 28, outerRadius: CGFloat(i) * 28 + 1.5, height: 0.5)
                    let m = SCNMaterial()
                    m.lightingModel = .constant
                    m.diffuse.contents = UIColor(red: 0.23, green: 0.84, blue: 1, alpha: 0.5 - 0.1 * CGFloat(i))
                    m.blendMode = .add
                    ring.firstMaterial = m
                    stage.addChildNode(SCNNode(geometry: ring))
                }
                stage.position = SCNVector3(0, -Float(BodyMapLayout.height) / 2 - 1, 0)
                scene.rootNode.addChildNode(stage)
            case .studio:
                add(.ambient, UIColor(red: 1, green: 0.85, blue: 0.9, alpha: 1), 520)
                add(.directional, .white, 1400, SCNVector3(300, 500, 500))
                add(.directional, UIColor(red: 1, green: 0.48, blue: 0.66, alpha: 1), 500, SCNVector3(-400, 0, -300))
                let shadow = SCNNode(geometry: SCNCylinder(radius: 90, height: 0.5))
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.diffuse.contents = UIColor(white: 0, alpha: 0.18)
                shadow.geometry?.firstMaterial = m
                shadow.name = "stage"
                shadow.position = SCNVector3(0, -Float(BodyMapLayout.height) / 2 - 2, 0)
                scene.rootNode.addChildNode(shadow)
            }
        }

        // MARK: Gestures

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            stopSpin()
            let d = g.translation(in: view)
            g.setTranslation(.zero, in: view)
            yaw += Double(d.x) * 0.012
            pitch = max(-0.35, min(0.35, pitch + Double(d.y) * 0.006))
            applyRotation()
            if g.state == .ended {
                // A flick keeps turning a little.
                let v = Double(g.velocity(in: view).x) * 0.012 * 0.25
                turn(to: yaw + v, animated: true, duration: 0.6)
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            stopSpin()
            distance = max(420, min(1300, distance / Double(g.scale)))
            g.scale = 1
            placeCamera()
        }

        @objc func reset(_ g: UITapGestureRecognizer) {
            stopSpin()
            distance = Self.homeDistance
            pitch = 0
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            placeCamera()
            SCNTransaction.commit()
            turn(to: (requestedYaw ?? 0) * .pi / 180, animated: true)
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let view = g.view as? SCNView, let figure else { return }
            let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first(where: { $0.node === frontNode || $0.node === backNode }) else { return }
            let p = hit.localCoordinates
            // Which surface was hit decides the sheet, even right at the contour.
            var point = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
            point.z = hit.node === frontNode ? max(point.z, 0.001) : min(point.z, -0.001)
            if let m = BodyMesh.muscle(atModel: point, figure: figure) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap?(m)
            }
        }

        private func applyRotation() {
            turntable.eulerAngles = SCNVector3(0, Float(yaw), 0)
            tilt.eulerAngles = SCNVector3(Float(pitch), 0, 0)
        }

        private func turn(to target: Double, animated: Bool, duration: Double = 0.5) {
            stopSpin()
            // Shortest way round.
            var t = target
            while t - yaw > .pi { t -= 2 * .pi }
            while yaw - t > .pi { t += 2 * .pi }
            yaw = t
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? duration : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            applyRotation()
            SCNTransaction.commit()
        }

        /// Slow turntable (holo style) until the member touches the figure; off with Reduce Motion.
        private func spin() {
            guard !UIAccessibility.isReduceMotionEnabled, turntable.action(forKey: "spin") == nil else { return }
            turntable.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)), forKey: "spin")
        }

        private func stopSpin() {
            guard turntable.action(forKey: "spin") != nil else { return }
            yaw = Double(turntable.presentation.eulerAngles.y)
            turntable.removeAction(forKey: "spin")
            applyRotation()
        }

        static func geometry(_ s: BodyMesh.Surface) -> SCNGeometry {
            let v = SCNGeometrySource(vertices: s.positions.map { SCNVector3($0.x, $0.y, $0.z) })
            let n = SCNGeometrySource(normals: s.normals.map { SCNVector3($0.x, $0.y, $0.z) })
            let t = SCNGeometrySource(textureCoordinates: s.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
            let e = SCNGeometryElement(indices: s.indices, primitiveType: .triangles)
            return SCNGeometry(sources: [v, n, t], elements: [e])
        }
    }
}

/// Sheet art for the 3D figure: the 2D map drawn into an image (front or back), in the style's colours.
enum BodyTexture {
    /// Pixels per design unit.
    static let scale: CGFloat = 3

    static func image(side: BodySide, figure: BodyFigure, heat: [Muscle: Double], selected: Muscle?, style: BodyMap3DStyle) -> UIImage {
        let size = CGSize(width: CGFloat(BodyMapLayout.width) * scale, height: CGFloat(BodyMapLayout.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { r in
            let ctx = r.cgContext
            let (skin, empty, stroke, detail) = palette(style)
            ctx.setFillColor(skin.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            for shape in BodyMapLayout.shapes(side, figure: figure) {
                let path = BodyMapView.smooth(shape.points, s: scale).cgPath
                let h = heat[shape.muscle] ?? 0
                ctx.addPath(path)
                ctx.setFillColor((h > 0 ? color(h, style: style) : empty).cgColor)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.setStrokeColor(stroke.cgColor)
                ctx.setLineWidth(0.8 * scale)
                ctx.strokePath()
            }
            for line in BodyMapLayout.details(side, figure: figure) {
                guard let first = line.first else { continue }
                ctx.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                for p in line.dropFirst() { ctx.addLine(to: CGPoint(x: p.x * scale, y: p.y * scale)) }
                ctx.setStrokeColor(detail.cgColor)
                ctx.setLineWidth(0.8 * scale)
                ctx.strokePath()
            }
            if let selected {
                for shape in BodyMapLayout.shapes(side, figure: figure) where shape.muscle == selected {
                    ctx.addPath(BodyMapView.smooth(shape.points, s: scale).cgPath)
                    ctx.setStrokeColor(UIColor.white.cgColor)
                    ctx.setLineWidth(2.2 * scale)
                    ctx.strokePath()
                }
            }
        }
    }

    private static func palette(_ style: BodyMap3DStyle) -> (UIColor, UIColor, UIColor, UIColor) {
        switch style {
        case .clay:
            (UIColor(red: 0.20, green: 0.20, blue: 0.25, alpha: 1), UIColor(red: 0.27, green: 0.27, blue: 0.34, alpha: 1),
             UIColor(white: 0, alpha: 0.45), UIColor(white: 0, alpha: 0.3))
        case .holo:
            (UIColor(red: 0.04, green: 0.06, blue: 0.19, alpha: 1), UIColor(red: 0.08, green: 0.10, blue: 0.27, alpha: 1),
             UIColor(red: 0.31, green: 0.86, blue: 1, alpha: 0.55), UIColor(red: 0.31, green: 0.86, blue: 1, alpha: 0.35))
        case .studio:
            (UIColor(red: 0.96, green: 0.95, blue: 0.97, alpha: 1), UIColor(red: 0.89, green: 0.86, blue: 0.92, alpha: 1),
             UIColor(red: 0.24, green: 0.08, blue: 0.31, alpha: 0.25), UIColor(red: 0.24, green: 0.08, blue: 0.31, alpha: 0.2))
        }
    }

    private static func color(_ h: Double, style: BodyMap3DStyle) -> UIColor {
        switch style {
        case .clay, .studio: UIColor(Theme.heat(h))
        case .holo: UIColor(hue: 0.52 - 0.4 * h, saturation: 1, brightness: 0.85 + 0.15 * h, alpha: 1) // cyan → magenta
        }
    }
}

/// Background stage behind the 3D figure, per style.
struct BodyMap3DBackdrop: View {
    let style: BodyMap3DStyle

    var body: some View {
        switch style {
        case .clay:
            RadialGradient(colors: [Color(red: 0.17, green: 0.15, blue: 0.28), Color(red: 0.07, green: 0.07, blue: 0.09)],
                           center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 360)
        case .holo:
            ZStack {
                RadialGradient(colors: [Color(red: 0.11, green: 0.08, blue: 0.31), Color(red: 0.02, green: 0.02, blue: 0.05)],
                               center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 330)
                Circle().fill(RadialGradient(colors: [Color.purple.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 140))
                    .frame(width: 280, height: 280)
            }
        case .studio:
            LinearGradient(colors: [Color(red: 1, green: 0.54, blue: 0.24), Color(red: 1, green: 0.24, blue: 0.5), Color(red: 0.48, green: 0.24, blue: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Demo screens (CI screenshots) force the map mode and style without touching the member's setting.
struct BodyMapDemo {
    var mode: BodyMapMode
    var style: BodyMap3DStyle = .clay
    var picked: Muscle?
    var facing: BodyMap3DPanel.Snap = .front
}

private struct BodyMapDemoKey: EnvironmentKey {
    static let defaultValue: BodyMapDemo? = nil
}

extension EnvironmentValues {
    var bodyMapDemo: BodyMapDemo? {
        get { self[BodyMapDemoKey.self] }
        set { self[BodyMapDemoKey.self] = newValue }
    }
}

/// Compact 2D | 3D switch drawn on the map.
struct BodyMapModeToggle: View {
    @Binding var selection: BodyMapMode
    /// Shown state (a demo can force it).
    var current: BodyMapMode? = nil

    var body: some View {
        let on = current ?? selection
        HStack(spacing: 2) {
            ForEach(BodyMapMode.allCases) { m in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = m }
                } label: {
                    Text(m.label).font(Theme.label(12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(on == m ? Theme.ink : .white.opacity(0.8))
                        .background(Capsule().fill(on == m ? Color.white : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m == .flat ? "2D body map" : "3D body map")
                .accessibilityAddTraits(on == m ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.14)))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Explore → Muscles in 3D (#225): the figure on its stage, Front / Side / Back snaps, and a card for the picked
/// muscle (tap it to open the muscle's page).
struct BodyMap3DPanel: View {
    let heat: [Muscle: Double]
    let style: BodyMap3DStyle
    let modeToggle: AnyView
    let onOpen: (Muscle) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.bodyMapDemo) private var demo
    @State private var picked: Muscle?
    @State private var facing: Snap = .front

    enum Snap: String, CaseIterable, Identifiable {
        case front = "Front", side = "Side", back = "Back"
        var id: String { rawValue }
        var yaw: Double { switch self { case .front: 0; case .side: -90; case .back: 180 } }
    }

    var body: some View {
        ZStack(alignment: .top) {
            BodyMap3DBackdrop(style: style)
            BodyMap3DView(heat: heat, selected: picked, style: style, yaw: facing.yaw) { m in
                withAnimation(.spring(duration: 0.3)) { picked = m }
            }
            .padding(.top, 58)
            .padding(.bottom, 84)
            VStack(spacing: 8) {
                HStack {
                    Text(style == .holo ? "Holo mode" : "Drag to turn · pinch to zoom")
                        .font(Theme.label(11)).tracking(1.5).textCase(.uppercase)
                        .foregroundStyle(style == .holo ? Color.cyan : .white.opacity(0.8))
                    Spacer()
                    modeToggle
                }
                HStack(spacing: 6) {
                    ForEach(Snap.allCases) { s in
                        Button {
                            facing = s
                        } label: {
                            Text(s.rawValue).font(Theme.label(12))
                                .padding(.horizontal, 13).padding(.vertical, 7)
                                .foregroundStyle(facing == s ? (style == .studio ? Color.purple : Theme.ink) : .white)
                                .background(Capsule().fill(facing == s ? Color.white : .white.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(facing == s ? .isSelected : [])
                    }
                }
            }
            .padding(12)
            VStack {
                Spacer()
                pickedCard.padding(10)
            }
        }
        .frame(height: 540)
        .onAppear {
            if let demo {
                picked = demo.picked
                facing = demo.facing
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            ForEach(Muscle.allCases) { m in
                Button(m.name) { onOpen(m) }
            }
        }
    }

    @ViewBuilder private var pickedCard: some View {
        if let m = picked {
            let h = heat[m] ?? 0
            Button { onOpen(m) } label: {
                HStack(spacing: 12) {
                    MuscleThumbnail(muscle: m, heat: h)
                        .frame(width: 44, height: 44)
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.7)
                        let n = Exercise.working(m).reduce(0) { $0 + $1.1.count }
                        Text("\(h >= 0.75 ? "Main mover" : h > 0 ? "Assist" : "Not this week") · \(n) exercises")
                            .font(.caption.weight(.semibold)).opacity(0.9)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(model.weeklySets(for: m))").font(Theme.display(28)).monospacedDigit()
                        Text("SETS").font(Theme.label(10)).tracking(1).opacity(0.8)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy)).opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(m.group.gradient))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(m.name), open exercises")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Text("Tap a muscle to see its exercises")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(Capsule().fill(.black.opacity(0.25)))
                .padding(.bottom, 20)
        }
    }
}

/// Account → Body & Health → Body map: 2D or 3D on Explore (#225).
struct BodyMapModeCard: View {
    @AppStorage(BodyMapMode.storageKey) private var mode = BodyMapMode.flat

    var body: some View {
        HStack(spacing: 12) {
            ForEach(BodyMapMode.allCases) { m in
                let on = mode == m
                Button {
                    withAnimation(.spring(duration: 0.3)) { mode = m }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: m == .flat ? "figure.stand" : "rotate.3d")
                            .font(.system(size: 30, weight: .bold))
                            .frame(height: 40)
                        Text(m.label).font(Theme.display(26))
                        Text(m == .flat ? "Front + back" : "Turn & zoom").font(.caption.weight(.semibold)).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(on ? AnyShapeStyle(WorkoutEngine.Category.strength.gradient) : AnyShapeStyle(Theme.card))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(on ? Theme.lime : Theme.stroke, lineWidth: on ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m == .flat ? "2D body map" : "3D body map")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
    }
}
