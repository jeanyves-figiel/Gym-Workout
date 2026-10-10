import SwiftUI
import UIKit
import WorkoutEngine

/// Draws an `ExerciseDrawing` frame in the illustration style of `ios/Tools/illustrations`
/// (white capsule mannequin, translucent far limbs, highlighted primary muscles, white props).
struct FigureDrawingView: View {
    let drawing: ExerciseDrawing
    var frame = 0
    var lit: Set<FigureHighlight> = []
    var accent: Color = Theme.lime
    /// Fixed placement (designer drags); nil rests the figure on the floor.
    var offset: Point2?

    var body: some View {
        Canvas { ctx, size in
            let t = FigureTransform(size: size)
            ctx.translateBy(x: t.origin.x, y: t.origin.y)
            ctx.scaleBy(x: t.scale, y: t.scale)
            let d = drawing.normalized
            let pose = d.frames[min(max(frame, 0), d.frames.count - 1)]
            FigureRenderer.draw(in: &ctx, pose: pose, drawing: d, lit: lit, accent: accent, offset: offset)
        }
        .accessibilityHidden(true)
    }
}

/// Maps the 400 × 300 viewBox into a view (aspect fit, centred).
struct FigureTransform {
    let scale: CGFloat
    let origin: CGPoint

    init(size: CGSize) {
        let s = min(size.width / FigureGeometry.width, size.height / FigureGeometry.height)
        scale = s
        origin = CGPoint(x: (size.width - FigureGeometry.width * s) / 2, y: (size.height - FigureGeometry.height * s) / 2)
    }

    func view(_ p: Point2) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func box(_ p: CGPoint) -> Point2 { Point2((p.x - origin.x) / scale, (p.y - origin.y) / scale) }
}

enum FigureRenderer {
    private typealias G = FigureGeometry
    private static let propOpacity = 0.55

    static func draw(
        in ctx: inout GraphicsContext, pose: FigurePose, drawing: ExerciseDrawing,
        lit: Set<FigureHighlight>, accent: Color, offset: Point2?
    ) {
        let j = G.placed(pose, offset: offset)
        line(&ctx, [Point2(14, G.floor + 8), Point2(G.width - 14, G.floor + 8)], 3, .white, 0.35)
        for p in drawing.props { prop(&ctx, p, j) }

        let far = drawing.front ? 1.0 : 0.42
        limbs(&ctx, j, side: "F", opacity: far, lit: lit, accent: accent)
        torso(&ctx, j, pose: pose, width: G.torsoWidth, color: .white)
        if lit.contains(.torso) { torso(&ctx, j, pose: pose, width: G.torsoWidth - 8, color: accent) }
        if lit.contains(.hipBlob) { dot(&ctx, j[.hip]!, 10, accent) }
        let neckEnd = j[.shoulder]!.moved(pose.neck, G.neck)
        line(&ctx, [j[.shoulder]!, neckEnd], 10, .white)
        dot(&ctx, j[.head]!, G.headRadius, .white)
        limbs(&ctx, j, side: "N", opacity: 1, lit: lit, accent: accent)
        if lit.contains(.shoulderBlob) { dot(&ctx, j[.shoulder]!, 9, accent) }
    }

    private static func limbs(
        _ ctx: inout GraphicsContext, _ j: [Joint: Point2], side: String, opacity: Double,
        lit: Set<FigureHighlight>, accent: Color
    ) {
        let n = side == "N"
        let leg = [j[.hip]!, j[n ? .kneeN : .kneeF]!, j[n ? .ankleN : .ankleF]!, j[n ? .toeN : .toeF]!]
        let arm = [j[.shoulder]!, j[n ? .elbowN : .elbowF]!, j[n ? .wristN : .wristF]!, j[n ? .handN : .handF]!]
        line(&ctx, leg, G.limbWidth, .white, opacity)
        line(&ctx, arm, G.limbWidth - 2, .white, opacity)
        let hl = opacity == 1 ? 1.0 : 0.6
        if lit.contains(.thigh) { line(&ctx, [leg[0], leg[1]], G.limbWidth - 6, accent, hl) }
        if lit.contains(.shin) { line(&ctx, [leg[1], leg[2]], G.limbWidth - 6, accent, hl) }
        if lit.contains(.upperArm) { line(&ctx, [arm[0], arm[1]], G.limbWidth - 7, accent, hl) }
        if lit.contains(.forearm) { line(&ctx, [arm[1], arm[2]], G.limbWidth - 7, accent, hl) }
    }

    private static func torso(_ ctx: inout GraphicsContext, _ j: [Joint: Point2], pose: FigurePose, width: Double, color: Color) {
        let a = j[.hip]!, b = j[.shoulder]!
        var path = Path()
        path.move(to: cg(a))
        if pose.curl == 0 {
            path.addLine(to: cg(b))
        } else {
            let r = (pose.torso + 90) * .pi / 180
            let c = Point2((a.x + b.x) / 2 - cos(r) * pose.curl, (a.y + b.y) / 2 - sin(r) * pose.curl)
            path.addQuadCurve(to: cg(b), control: cg(c))
        }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    // MARK: Props

    private static func prop(_ ctx: inout GraphicsContext, _ p: DrawingProp, _ j: [Joint: Point2]) {
        let a = j[p.anchor] ?? j[.hip]!
        let c = Point2(a.x + p.dx, a.y + p.dy)
        let floor = G.floor + 8
        switch p.kind {
        case .bench:
            let top = c.y + 9
            rect(&ctx, c.x - 55, top, 110, 10, 0.6)
            rect(&ctx, c.x - 45, top + 10, 8, max(0, floor - top - 10), 0.45, r: 2)
            rect(&ctx, c.x + 37, top + 10, 8, max(0, floor - top - 10), 0.45, r: 2)
        case .seat:
            let top = c.y + 9
            rect(&ctx, c.x - 23, top, 46, 10, 0.65)
            rect(&ctx, c.x - 5, top + 10, 10, max(0, floor - top - 10), 0.45, r: 2)
        case .pad:
            line(&ctx, [Point2(c.x - 26, c.y - 12), Point2(c.x + 26, c.y - 12)], 12, .white, 0.6)
        case .box:
            let top = c.y + 7
            rect(&ctx, c.x - 45, top, 90, max(8, floor - top), 0.5)
        case .bar:
            line(&ctx, [Point2(c.x - 30, c.y), Point2(c.x + 30, c.y)], 6, .white, 0.8)
            line(&ctx, [Point2(c.x - 30, c.y), Point2(c.x - 30, 0)], 5, .white, 0.4, cap: .butt)
            line(&ctx, [Point2(c.x + 30, c.y), Point2(c.x + 30, 0)], 5, .white, 0.4, cap: .butt)
        case .cable:
            let column = c.x + 90
            rect(&ctx, column - 9, 40, 18, floor - 40, 0.45, r: 6)
            line(&ctx, [c, Point2(column, 52)], 2.5, .white, 0.7)
            dot(&ctx, c, 6, .white, 0.8)
        case .handle:
            line(&ctx, [Point2(c.x, c.y - 12), Point2(c.x, c.y + 12)], 7, .white, 0.8)
        case .dumbbell:
            rect(&ctx, c.x - 13, c.y - 7, 26, 14, 0.85)
        case .kettlebell:
            dot(&ctx, Point2(c.x, c.y + 15), 11, .white, 0.85)
            line(&ctx, [Point2(c.x - 6, c.y + 5), Point2(c.x, c.y - 2), Point2(c.x + 6, c.y + 5)], 4, .white, 0.85)
        case .plate:
            dot(&ctx, c, 24, .white, 0.5)
            dot(&ctx, c, 5, .white, 0.9)
        case .ball:
            dot(&ctx, c, 13, .white, 0.85)
        case .machine:
            rect(&ctx, c.x - 70, c.y - 150, 140, 150 + max(0, floor - c.y), 0.16, r: 10)
        case .wall:
            rect(&ctx, c.x + 10, 20, 12, floor - 20, 0.4, r: 2)
        case .mat:
            rect(&ctx, c.x - 130, G.floor + 5, 260, 6, 0.4, r: 3)
        }
    }

    // MARK: Primitives

    private static func cg(_ p: Point2) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    private static func line(
        _ ctx: inout GraphicsContext, _ pts: [Point2], _ w: Double, _ color: Color, _ opacity: Double = 1,
        cap: CGLineCap = .round
    ) {
        var path = Path()
        path.addLines(pts.map(cg))
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: w, lineCap: cap, lineJoin: .round))
    }

    private static func dot(_ ctx: inout GraphicsContext, _ c: Point2, _ r: Double, _ color: Color, _ opacity: Double = 1) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(opacity)))
    }

    private static func rect(
        _ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ opacity: Double, r: Double = 4
    ) {
        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r), with: .color(.white.opacity(opacity)))
    }
}

extension WorkoutEngine.Category {
    /// Highlight colour for figures on this category's gradient (lime, dark where the gradient is lime/yellow).
    var figureAccent: Color {
        switch self {
        case .warmup: Color(red: 0.72, green: 0.29, blue: 0)
        case .stretch: Color(red: 0.04, green: 0.48, blue: 0.29)
        default: Theme.lime
        }
    }
}

/// One frame of a custom exercise's picture: the photo if there is one (frame 0), else the pose
/// drawing (frame 0 = start, 1 = end); a photo + pose shows the pose as frame 1.
struct CustomExerciseArt: View {
    let record: CustomExercise
    var frame = 0
    var contentMode: ContentMode = .fill

    var body: some View {
        if let data = record.photo, frame == 0 || record.drawing == nil, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let d = record.drawing {
            FigureDrawingView(
                drawing: d, frame: record.photo == nil ? frame : 1, lit: FigureHighlight.segments(for: record.primary),
                accent: record.category.figureAccent)
        }
    }
}

extension CustomExercise {
    /// Frames shown as start/end: photo + pose → photo then pose; pose only → its two frames; photo only → one.
    var frameCount: Int {
        switch (photo != nil, drawing != nil) {
        case (true, true), (false, true): 2
        case (true, false): 1
        case (false, false): 0
        }
    }
}
