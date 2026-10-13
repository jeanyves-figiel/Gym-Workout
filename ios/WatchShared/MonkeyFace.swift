import SwiftUI

// Monkey mascot (#219), shared by the Watch (Monkey coach home, game look) and the iPhone (#227).

/// Mood from the week, streak and readiness; same rule on both devices.
extension MonkeyFace.Mood {
    /// `readiness` is the phone's headline ("Ready to push", "Take it easier").
    static func from(weekDone: Bool, readiness: String?, streakWeeks: Int) -> Self {
        if weekDone { return .party }
        if readiness == "Take it easier" { return .sleepy }
        if readiness == "Ready to push" || streakWeeks >= 2 { return .fired }
        return .happy
    }
}

/// Cartoon monkey drawn with shapes; the eyes and mouth follow its mood.
struct MonkeyFace: View {
    enum Mood { case happy, fired, sleepy, party }
    let mood: Mood
    /// 1 = Watch size (70 × 60 pt); the iPhone draws it bigger.
    var scale: CGFloat = 1

    private let lime = Color(red: 0.80, green: 1.0, blue: 0.24)
    private let fur = Color(red: 0.54, green: 0.35, blue: 0.17)
    private let skin = Color(red: 0.91, green: 0.70, blue: 0.48)

    var body: some View {
        ZStack {
            HStack(spacing: 40) { ear; ear }
            Circle().fill(fur).frame(width: 50, height: 50)
            Ellipse().fill(skin).frame(width: 36, height: 27).offset(y: 9)
            HStack(spacing: 1) {
                Ellipse().fill(skin).frame(width: 15, height: 17)
                Ellipse().fill(skin).frame(width: 15, height: 17)
            }
            .offset(y: -4)
            eyes.offset(y: -4)
            mouth.offset(y: 12)
            if mood == .fired || mood == .party {
                Capsule().fill(lime).frame(width: 42, height: 7).offset(y: -21)
            }
            if mood == .sleepy {
                Text("z").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white).offset(x: 27, y: -24)
            }
        }
        .frame(width: 70, height: 60)
        .scaleEffect(scale)
        .frame(width: 70 * scale, height: 60 * scale)
    }

    private var ear: some View {
        ZStack {
            Circle().fill(fur).frame(width: 20, height: 20)
            Circle().fill(skin).frame(width: 10, height: 10)
        }
    }

    @ViewBuilder private var eyes: some View {
        HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { _ in
                switch mood {
                case .sleepy: Capsule().fill(.black).frame(width: 8, height: 2.5)
                case .party: Arc(up: true).stroke(.black, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).frame(width: 8, height: 4)
                case .happy, .fired: Circle().fill(.black).frame(width: 6, height: 6)
                }
            }
        }
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .happy: Arc(up: false).stroke(.black, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).frame(width: 14, height: 4)
        case .fired: Arc(up: false, closed: true).fill(.black).frame(width: 16, height: 5)
        case .sleepy: Circle().stroke(.black, lineWidth: 2).frame(width: 5, height: 5)
        case .party: Ellipse().fill(.black).frame(width: 12, height: 10)
        }
    }
}

/// Smile (down) or happy-eye (up) curve.
private struct Arc: Shape {
    var up: Bool
    var closed = false

    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = up ? r.maxY : r.minY
        p.move(to: CGPoint(x: r.minX, y: y))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: y), control: CGPoint(x: r.midX, y: up ? r.minY - r.height : r.maxY + r.height))
        if closed { p.closeSubpath() }
        return p
    }
}
