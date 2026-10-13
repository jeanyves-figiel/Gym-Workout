import SceneKit
import SwiftUI
import UIKit
import WorkoutEngine

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
    /// Turn to show a side: 0 front, 90 right side, 180 back (snap buttons). Changing it animates.
    var yaw: Double = 0
    var onTap: (Muscle) -> Void
    /// Demo screens: reports when the figure is on screen (vertex count), for CI screenshots.
    var onReady: ((Int) -> Void)?
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
        c.onReady = onReady
        c.setUp()
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.delegate = c
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))))
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.reset(_:)))
        double.numberOfTapsRequired = 2
        view.addGestureRecognizer(double)
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: double)
        view.addGestureRecognizer(tap)
        c.update(figure: figure, heat: heat, selected: selected, yaw: yaw)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.update(figure: figure, heat: heat, selected: selected, yaw: yaw)
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: SCNView?
        var onTap: ((Muscle) -> Void)?
        var onReady: ((Int) -> Void)?
        private let scene = SCNScene()
        /// Turns (yaw); holds the body centred on its middle.
        private let turntable = SCNNode()
        /// Holds the body centred on its middle inside the turntable.
        private let holder = SCNNode()
        private let frontNode = SCNNode(), backNode = SCNNode()
        private let cameraNode = SCNNode()
        private var figure: BodyFigure?
        private var key: String?
        private var yaw = 0.0, distance = Coordinator.homeDistance
        private var requestedYaw: Double?
        private var build: Task<Void, Never>?

        static let homeDistance = 880.0

        func setUp() {
            view?.scene = scene
            let camera = SCNCamera()
            camera.fieldOfView = 28
            camera.zNear = 10
            camera.zFar = 4000
            cameraNode.camera = camera
            scene.rootNode.addChildNode(cameraNode)
            placeCamera()
            view?.pointOfView = cameraNode
            holder.position = SCNVector3(0, -Float(BodyMapLayout.height) / 2, 0)
            holder.addChildNode(frontNode)
            holder.addChildNode(backNode)
            turntable.addChildNode(holder)
            scene.rootNode.addChildNode(turntable)
            addLights()
        }

        private func placeCamera() {
            cameraNode.position = SCNVector3(0, 6, Float(distance))
            cameraNode.look(at: SCNVector3(0, 6, 0))
        }

        func update(figure: BodyFigure, heat: [Muscle: Double], selected: Muscle?, yaw: Double) {
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
                    self.paint(figure: fig, heat: heat, selected: selected)
                    self.view?.setNeedsDisplay()
                    self.onReady?(mesh.front.positions.count + mesh.back.positions.count)
                }
                return
            }
            paint(figure: figure, heat: heat, selected: selected)
        }

        private func paint(figure: BodyFigure, heat: [Muscle: Double], selected: Muscle?) {
            guard frontNode.geometry != nil else { return }
            let newKey = "\(figure)|\(selected?.rawValue ?? "")|" + heat.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue)=\(Int($0.value * 100))" }.joined(separator: ",")
            guard newKey != key else { return }
            key = newKey
            for (node, side) in [(frontNode, BodySide.front), (backNode, .back)] {
                let image = BodyTexture.image(side: side, figure: figure, heat: heat, selected: selected)
                node.geometry?.firstMaterial = Self.material(image)
            }
        }

        /// Matte clay with the heat colours painted on.
        private static func material(_ image: UIImage) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = image
            m.roughness.contents = 0.62
            m.metalness.contents = 0.0
            return m
        }

        /// Soft fill, a white key from the upper left and a violet rim from behind.
        private func addLights() {
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
            add(.ambient, .white, 420)
            add(.directional, .white, 1300, SCNVector3(-300, 400, 500))
            add(.directional, UIColor(red: 0.6, green: 0.42, blue: 1, alpha: 1), 700, SCNVector3(400, 100, -400))
        }

        // MARK: Gestures

        /// Only sideways drags turn the figure; vertical drags keep scrolling the page.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, let view = pan.view else { return true }
            let v = pan.velocity(in: view)
            return abs(v.x) > abs(v.y)
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            let d = g.translation(in: view)
            g.setTranslation(.zero, in: view)
            yaw += Double(d.x) * 0.012
            applyRotation()
            if g.state == .ended {
                // A flick keeps turning a little.
                let v = Double(g.velocity(in: view).x) * 0.012 * 0.25
                turn(to: yaw + v, animated: true, duration: 0.6)
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            distance = max(380, min(1200, distance / Double(g.scale)))
            g.scale = 1
            placeCamera()
        }

        @objc func reset(_ g: UITapGestureRecognizer) {
            distance = Self.homeDistance
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
            // Which surface was hit decides the sheet.
            let point = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
            if let m = BodyMesh.muscle(atModel: point, side: hit.node === frontNode ? .front : .back, figure: figure) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap?(m)
            }
        }

        private func applyRotation() {
            // Turns around its own vertical axis only (no tilt).
            turntable.eulerAngles = SCNVector3(0, Float(yaw), 0)
        }

        private func turn(to target: Double, animated: Bool, duration: Double = 0.5) {
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

        static func geometry(_ s: BodyMesh.Surface) -> SCNGeometry {
            let v = SCNGeometrySource(vertices: s.positions.map { SCNVector3($0.x, $0.y, $0.z) })
            let n = SCNGeometrySource(normals: s.normals.map { SCNVector3($0.x, $0.y, $0.z) })
            let t = SCNGeometrySource(textureCoordinates: s.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
            let e = SCNGeometryElement(indices: s.indices, primitiveType: .triangles)
            return SCNGeometry(sources: [v, n, t], elements: [e])
        }
    }
}

/// Sheet art for the 3D figure: the 2D map drawn into an image (front or back) on clay-coloured skin.
enum BodyTexture {
    /// Pixels per design unit.
    static let scale: CGFloat = 3

    static func image(side: BodySide, figure: BodyFigure, heat: [Muscle: Double], selected: Muscle?) -> UIImage {
        let size = CGSize(width: CGFloat(BodyMapLayout.width) * scale, height: CGFloat(BodyMapLayout.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { r in
            let ctx = r.cgContext
            let skin = UIColor(red: 0.20, green: 0.20, blue: 0.25, alpha: 1), empty = UIColor(red: 0.27, green: 0.27, blue: 0.34, alpha: 1)
            let stroke = UIColor(white: 0, alpha: 0.45), detail = UIColor(white: 0, alpha: 0.3)
            ctx.setFillColor(skin.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            for shape in BodyMapLayout.shapes(side, figure: figure) {
                let path = BodyMapView.smooth(shape.points, s: scale).cgPath
                let h = heat[shape.muscle] ?? 0
                ctx.addPath(path)
                ctx.setFillColor((h > 0 ? UIColor(Theme.heat(h)) : empty).cgColor)
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
}

/// Demo screens (CI screenshots) force the map mode without touching the member's setting.
struct BodyMapDemo {
    var mode: BodyMapMode
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
    let modeToggle: AnyView
    let onOpen: (Muscle) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.bodyMapDemo) private var demo
    @State private var picked: Muscle?
    @State private var facing: Snap = .front
    /// Demo screens only: vertex count once the figure is built.
    @State private var demoVertices: Int?

    enum Snap: String, CaseIterable, Identifiable {
        case front = "Front", side = "Side", back = "Back"
        var id: String { rawValue }
        var yaw: Double { switch self { case .front: 0; case .side: -65; case .back: 180 } }
    }

    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(colors: [Color(red: 0.17, green: 0.15, blue: 0.28), Color(red: 0.07, green: 0.07, blue: 0.09)],
                           center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 360)
            BodyMap3DView(heat: heat, selected: picked, yaw: facing.yaw, onTap: { m in
                withAnimation(.spring(duration: 0.3)) { picked = m }
            }, onReady: demo == nil ? nil : { demoVertices = $0 })
            .padding(.top, 58)
            .padding(.bottom, 84)
            VStack(spacing: 8) {
                HStack {
                    Text("Drag to turn · pinch to zoom")
                        .font(Theme.label(11)).tracking(1.5).textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.8))
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
                                .foregroundStyle(facing == s ? Theme.ink : .white)
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
                if demo != nil {
                    Text(demoVertices.map { "\($0) vertices" } ?? "building figure…").font(.caption2).foregroundStyle(Theme.muted)
                }
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
