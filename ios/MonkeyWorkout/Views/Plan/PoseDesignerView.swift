import SwiftUI
import WorkoutEngine

/// Pose designer for custom exercises (#52): start from a template, drag the joints for the start and
/// end position, add equipment props. Draws in the same style as the built-in illustrations.
struct PoseDesignerView: View {
    @Binding var drawing: ExerciseDrawing
    let category: WorkoutEngine.Category
    let primary: [Muscle]

    @State private var frame = 0
    @State private var playing = false
    @State private var playFrame = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Frame", selection: $frame) {
                    Text("Start").tag(0)
                    Text("End").tag(1)
                }
                .pickerStyle(.segmented)
                .disabled(playing)

                stage

                HStack(spacing: 10) {
                    actionButton(playing ? "Stop" : "Play", symbol: playing ? "stop.fill" : "play.fill") { playing.toggle() }
                    actionButton("Start → end", symbol: "doc.on.doc") {
                        let start = drawing.normalized.frames[0]
                        drawing.frames = [start, start]
                    }
                    actionButton(drawing.front ? "Side view" : "Front view", symbol: "person.fill.turn.right") {
                        drawing.front.toggle()
                    }
                }

                Text("Start from").eyebrow()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(PoseTemplate.allCases) { t in
                            Button { drawing = ExerciseDrawing(template: t) } label: { templateTile(t) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                Text("Equipment").eyebrow()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DrawingProp.Kind.allCases, id: \.self) { k in
                            let on = drawing.props.contains { $0.kind == k }
                            Button { toggle(k) } label: {
                                Text(k.label)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(on ? Theme.ink : .white)
                                    .background {
                                        if on { Capsule().fill(Theme.lime) } else { Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5) }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Drag the dots to pose the body. Drag a square to move equipment.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Pose")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: playing) {
            playFrame = 0
            guard playing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.3)) { playFrame = (playFrame + 1) % 2 }
            }
        }
        .onAppear { drawing = drawing.normalized }
    }

    private var stage: some View {
        PoseStage(drawing: $drawing, frame: playing ? playFrame : frame, editable: !playing,
                  lit: FigureHighlight.segments(for: primary), accent: category.figureAccent)
            .aspectRatio(4 / 3, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(category.gradient))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func toggle(_ k: DrawingProp.Kind) {
        if let i = drawing.props.firstIndex(where: { $0.kind == k }) {
            drawing.props.remove(at: i)
        } else if drawing.props.count < 8 {
            drawing.props.append(DrawingProp(k))
        }
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
        }
        .buttonStyle(.plain)
    }

    private func templateTile(_ t: PoseTemplate) -> some View {
        VStack(spacing: 4) {
            FigureDrawingView(drawing: ExerciseDrawing(template: t), accent: category.figureAccent)
                .frame(width: 92, height: 69)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(category.gradient))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(t.label).font(Theme.label(12))
        }
    }
}

/// The drawing with draggable joint and prop handles.
private struct PoseStage: View {
    @Binding var drawing: ExerciseDrawing
    let frame: Int
    let editable: Bool
    let lit: Set<FigureHighlight>
    let accent: Color

    /// Placement frozen while dragging, so the figure doesn't jump as it re-grounds.
    @State private var frozen: Point2?

    private static let handles: [Joint] = [.head, .shoulder, .elbowN, .wristN, .kneeN, .ankleN, .toeN, .elbowF, .wristF, .kneeF, .ankleF]

    var body: some View {
        GeometryReader { geo in
            let t = FigureTransform(size: geo.size)
            let d = drawing.normalized
            let pose = d.frames[min(frame, 1)]
            let placed = FigureGeometry.placed(pose, offset: frozen)
            ZStack(alignment: .topLeading) {
                FigureDrawingView(drawing: d, frame: frame, lit: lit, accent: accent, offset: frozen)
                if editable {
                    ForEach(d.props) { p in
                        let a = placed[p.anchor] ?? placed[.hip]!
                        handle(square: true, far: false)
                            .position(t.view(Point2(a.x + p.dx, a.y + p.dy)))
                            .highPriorityGesture(propDrag(p, anchor: a, t: t))
                    }
                    ForEach(Self.handles, id: \.self) { joint in
                        handle(square: false, far: joint.isFar && !d.front)
                            .position(t.view(placed[joint]!))
                            .highPriorityGesture(jointDrag(joint, placed: placed, t: t))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: "stage")
        }
    }

    private func handle(square: Bool, far: Bool) -> some View {
        Group {
            if square {
                RoundedRectangle(cornerRadius: 4).fill(Theme.ink.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: 2))
                    .frame(width: 18, height: 18)
            } else {
                Circle().fill(far ? Theme.ink.opacity(0.35) : Theme.ink.opacity(0.7))
                    .overlay(Circle().strokeBorder(Theme.lime.opacity(far ? 0.6 : 1), lineWidth: 2.5))
                    .frame(width: far ? 18 : 22, height: far ? 18 : 22)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private func jointDrag(_ joint: Joint, placed: [Joint: Point2], t: FigureTransform) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("stage"))
            .onChanged { v in
                if frozen == nil {
                    frozen = FigureGeometry.groundingOffset(FigureGeometry.joints(drawing.normalized.frames[min(frame, 1)]))
                }
                let current = FigureGeometry.placed(drawing.normalized.frames[min(frame, 1)], offset: frozen)
                guard let parent = joint.parent, let origin = current[parent] else { return }
                let target = t.box(v.location)
                var d = drawing.normalized
                d.frames[min(frame, 1)].setAngle(FigureGeometry.angle(from: origin, to: target), for: joint)
                drawing = d
            }
            .onEnded { _ in withAnimation(.snappy) { frozen = nil } }
    }

    private func propDrag(_ p: DrawingProp, anchor: Point2, t: FigureTransform) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("stage"))
            .onChanged { v in
                let target = t.box(v.location)
                guard let i = drawing.props.firstIndex(where: { $0.id == p.id }) else { return }
                drawing.props[i].dx = min(200, max(-200, target.x - anchor.x))
                drawing.props[i].dy = min(200, max(-200, target.y - anchor.y))
            }
    }
}
