import SwiftUI

// Level ladder (#242), shared by the iPhone and the Watch: six ranks, what each one unlocks.
// Levels only unlock looks; no training feature is ever locked by level (Pro stays the only lock).

extension Color {
    init(hex v: UInt32) {
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// What the monkey wears from a rank on.
enum MonkeyGear: Sendable {
    case headband, cap, dumbbell, shades, lightning, crown
}

/// Ring drawn around the monkey from Regular on.
enum RankRing: Sendable {
    case none, bronze, silver, gold, legend

    var colors: [Color] {
        switch self {
        case .none: [.clear]
        case .bronze: [Color(hex: 0xD98547), Color(hex: 0xFFB873), Color(hex: 0xD98547)]
        case .silver: [Color(hex: 0xB3BFD1), Color(hex: 0xF2F7FF), Color(hex: 0xB3BFD1)]
        case .gold: [Color(hex: 0xFFC71A), Color(hex: 0xFFED80), Color(hex: 0xFFC71A)]
        case .legend: [Color(hex: 0xFF3DA8), Color(hex: 0xFFC23D), Color(hex: 0x3DFFB0), Color(hex: 0x3D5AFF), Color(hex: 0xFF3DA8)]
        }
    }
}

/// Level-up effect of a rank.
enum LevelEffect: Sendable {
    case confetti, fireworks, crowns
}

/// One unlock on the ladder.
struct GamePerk: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let title: String
}

enum GameRank: Int, CaseIterable, Comparable, Identifiable, Sendable {
    case rookie, regular, iron, steel, titan, legend

    static let perLevel = 500

    var id: Int { rawValue }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    static func of(level: Int) -> GameRank { allCases.last { level >= $0.minLevel } ?? .rookie }

    var minLevel: Int { [1, 3, 8, 15, 25, 40][rawValue] }
    /// Total XP where this rank starts.
    var minXP: Int { (minLevel - 1) * Self.perLevel }
    var next: GameRank? { GameRank(rawValue: rawValue + 1) }

    var title: String { ["Rookie", "Regular", "Iron", "Steel", "Titan", "Legend"][rawValue] }

    /// "Levels 3–7", "Level 40+".
    var levels: String {
        guard let next else { return "Level \(minLevel)+" }
        return next.minLevel - 1 == minLevel ? "Level \(minLevel)" : "Levels \(minLevel)–\(next.minLevel - 1)"
    }

    var gear: MonkeyGear { [.headband, .cap, .dumbbell, .shades, .lightning, .crown][rawValue] }

    /// Best ring unlocked so far.
    var ring: RankRing {
        switch self {
        case .rookie: .none
        case .regular, .iron: .bronze
        case .steel: .silver
        case .titan: .gold
        case .legend: .legend
        }
    }

    /// Best level-up effect unlocked so far.
    var effect: LevelEffect {
        switch self {
        case .rookie, .regular: .confetti
        case .iron, .steel: .fireworks
        case .titan, .legend: .crowns
        }
    }

    /// Card gradient as 0xRRGGBB.
    var tint: (UInt32, UInt32) {
        switch self {
        case .rookie: (0x3DFFB0, 0x1E9BFF)
        case .regular: (0xFFC23D, 0xFF7A3D)
        case .iron: (0x6B7A99, 0x2B3550)
        case .steel: (0x3D5AFF, 0x7B3DFF)
        case .titan: (0xB23DFF, 0xFF3DA8)
        case .legend: (0xFF3D5A, 0xFFC23D)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: tint.0), Color(hex: tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// App icon unlocked at this rank (alternate icon name), if any.
    var appIcon: String? {
        switch self {
        case .iron: "AppIcon-Iron"
        case .titan: "AppIcon-Titan"
        case .legend: "AppIcon-Legend"
        default: nil
        }
    }

    /// What reaching this rank unlocks.
    var perks: [GamePerk] {
        switch self {
        case .rookie: [
            GamePerk(id: "headband", symbol: "face.smiling.inverse", title: "Lime headband monkey"),
            GamePerk(id: "confetti", symbol: "party.popper.fill", title: "Confetti on every level-up"),
        ]
        case .regular: [
            GamePerk(id: "cap", symbol: "face.smiling.inverse", title: "Cap monkey"),
            GamePerk(id: "title", symbol: "person.text.rectangle.fill", title: "Regular title on your Community profile"),
            GamePerk(id: "bronze", symbol: "circle.circle.fill", title: "Bronze ring"),
        ]
        case .iron: [
            GamePerk(id: "dumbbell", symbol: "dumbbell.fill", title: "Dumbbell monkey"),
            GamePerk(id: "fireworks", symbol: "sparkles", title: "Fireworks when you finish"),
            GamePerk(id: "icon-iron", symbol: "app.badge.fill", title: "Iron app icon"),
        ]
        case .steel: [
            GamePerk(id: "shades", symbol: "sunglasses.fill", title: "Sunglasses monkey"),
            GamePerk(id: "silver", symbol: "circle.circle.fill", title: "Silver ring"),
            GamePerk(id: "accent", symbol: "paintpalette.fill", title: "Pick your colour for Train and Watch"),
        ]
        case .titan: [
            GamePerk(id: "lightning", symbol: "bolt.fill", title: "Lightning monkey"),
            GamePerk(id: "gold", symbol: "circle.circle.fill", title: "Gold ring"),
            GamePerk(id: "crowns", symbol: "crown.fill", title: "Crown rain on level-up"),
            GamePerk(id: "icon-titan", symbol: "app.badge.fill", title: "Titan app icon"),
        ]
        case .legend: [
            GamePerk(id: "crown", symbol: "crown.fill", title: "Crowned monkey"),
            GamePerk(id: "animated", symbol: "rays", title: "Animated ring"),
            GamePerk(id: "icon-legend", symbol: "app.badge.fill", title: "Legend app icon"),
            GamePerk(id: "legend-badge", symbol: "checkmark.seal.fill", title: "Legend badge on your Community posts"),
        ]
        }
    }
}

/// Colour picked from Steel on for XP bars and level chips on Train and the Watch.
enum GameAccent: String, CaseIterable, Codable, Identifiable, Sendable {
    case lime, aqua, pink, sun, violet

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colors: (UInt32, UInt32) {
        switch self {
        case .lime: (0xCCFF3D, 0x3DDC84)
        case .aqua: (0x3DFFE0, 0x1E9BFF)
        case .pink: (0xFF7AD9, 0xFF3D8A)
        case .sun: (0xFFE03D, 0xFF8A3D)
        case .violet: (0xC79BFF, 0x7B3DFF)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: colors.0), Color(hex: colors.1)], startPoint: .leading, endPoint: .trailing)
    }

    var color: Color { Color(hex: colors.0) }
}

/// The monkey wearing its rank's gear inside its rank's ring.
struct RankMonkey: View {
    let rank: GameRank
    var mood: MonkeyFace.Mood = .happy
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = 82 * scale
        ZStack {
            if rank.ring != .none {
                TimelineView(.animation(paused: rank.ring != .legend || reduceMotion)) { t in
                    let angle = rank.ring == .legend ? t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90 : 0
                    Circle()
                        .strokeBorder(AngularGradient(colors: rank.ring.colors, center: .center, angle: .degrees(angle)), lineWidth: 5 * scale)
                }
                .frame(width: d, height: d)
            }
            MonkeyFace(mood: mood, scale: scale * 0.95, gear: rank.gear)
                .offset(y: 3 * scale)
        }
        .frame(width: d, height: d)
        .accessibilityLabel("\(rank.title) monkey")
    }
}

/// Full-screen level-up: the rank's effect (confetti, fireworks or crown rain) over the new level.
struct LevelUpCelebration: View {
    let level: Int
    /// Smaller type and monkey on the Watch.
    var compact = false
    var onDone: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var pop = false

    private var rank: GameRank { GameRank.of(level: level) }
    private var newRank: Bool { rank.minLevel == level }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            if !reduceMotion {
                TimelineView(.animation) { t in
                    Canvas { ctx, size in draw(ctx, size: size, time: t.date.timeIntervalSince(start)) }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            VStack(spacing: compact ? 4 : 12) {
                RankMonkey(rank: rank, mood: .party, scale: compact ? 0.8 : 2)
                    .scaleEffect(pop ? 1 : 0.4)
                Text(newRank ? "New rank!" : "Level up!")
                    .font(.system(size: compact ? 12 : 18, weight: .heavy, design: .rounded))
                    .textCase(.uppercase).tracking(1.5)
                    .foregroundStyle(Color(hex: rank.tint.0))
                Text("Level \(level)").font(.system(size: compact ? 30 : 64, weight: .black, design: .rounded))
                Text(rank.title).font(.system(size: compact ? 16 : 30, weight: .heavy, design: .rounded))
                    .padding(.horizontal, compact ? 10 : 18).padding(.vertical, compact ? 3 : 6)
                    .background(Capsule().fill(rank.gradient))
                if newRank, !compact {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rank.perks) { p in
                            Label(p.title, systemImage: p.symbol).font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                    }
                    .padding(.top, 8)
                }
                Text("Tap to continue").font(.system(size: compact ? 9 : 13, weight: .semibold)).opacity(0.6).padding(.top, compact ? 2 : 12)
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .onAppear {
            start = Date()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { pop = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Closes the celebration")
    }

    private static let palette: [UInt32] = [0xCCFF3D, 0xFF3DA8, 0xFFC23D, 0x3DFFE0, 0x7B3DFF, 0xFF7A3D]

    private func draw(_ ctx: GraphicsContext, size: CGSize, time: Double) {
        let n = compact ? 24 : 60
        for i in 0..<n {
            let seed = Double(i) * 12.9898
            let r1 = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude
            let r2 = (sin(seed * 1.7) * 23421.631).truncatingRemainder(dividingBy: 1).magnitude
            let color = Color(hex: Self.palette[i % Self.palette.count])
            switch rank.effect {
            case .confetti, .crowns:
                let speed = size.height * (0.25 + 0.35 * r2)
                let y = (time * speed + r1 * size.height * 1.5).truncatingRemainder(dividingBy: size.height * 1.2) - size.height * 0.1
                let x = r1 * size.width + sin(time * 2 + seed) * 14
                if rank.effect == .crowns, i % 2 == 0 {
                    ctx.draw(Text("👑").font(.system(size: compact ? 12 : 26)), at: CGPoint(x: x, y: y))
                } else {
                    let w: CGFloat = compact ? 4 : 8
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(time * 4 + seed))
                    c.fill(Path(CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)), with: .color(color))
                }
            case .fireworks:
                let burst = i / 12
                let period = 1.6
                let local = (time + Double(burst) * 0.45).truncatingRemainder(dividingBy: period) / period
                let bx = size.width * (0.2 + 0.6 * ((sin(Double(burst) * 7.1) + 1) / 2))
                let by = size.height * (0.15 + 0.3 * ((cos(Double(burst) * 3.3) + 1) / 2))
                let a = Double(i % 12) / 12 * 2 * .pi
                let dist = local * (compact ? 40 : 110)
                let p = CGPoint(x: bx + cos(a) * dist, y: by + sin(a) * dist + local * local * 30)
                let s: CGFloat = compact ? 3 : 6
                var c = ctx
                c.opacity = 1 - local
                c.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                         with: .color(Color(hex: Self.palette[burst % Self.palette.count])))
            }
        }
    }
}
