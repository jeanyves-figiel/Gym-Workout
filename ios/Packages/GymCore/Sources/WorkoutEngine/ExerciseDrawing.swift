import Foundation

/// A pose drawing in the app's illustration style (same mannequin as `ios/Tools/illustrations`):
/// two frames (start, end) of segment angles plus a few equipment props. Built in the pose designer
/// for custom exercises (#52).
///
/// Angles are degrees in screen space: 0 = right, 90 = down, -90 = up. Side view faces right;
/// "N" limbs are near the viewer, "F" far. `front` draws a frontal view (both sides opaque).
public struct ExerciseDrawing: Codable, Hashable, Sendable {
    public var frames: [FigurePose]
    public var props: [DrawingProp]
    public var front: Bool

    public init(frames: [FigurePose], props: [DrawingProp] = [], front: Bool = false) {
        self.frames = frames
        self.props = props
        self.front = front
    }

    public init(template: PoseTemplate) {
        self.init(frames: template.frames, props: template.props, front: template.front)
    }

    /// Always two frames.
    public var normalized: ExerciseDrawing {
        var d = self
        if d.frames.isEmpty { d.frames = PoseTemplate.standing.frames }
        if d.frames.count == 1 { d.frames.append(d.frames[0]) }
        d.frames = Array(d.frames.prefix(2))
        d.props = Array(d.props.prefix(8))
        return d
    }
}

public struct FigurePose: Codable, Hashable, Sendable {
    public var torso: Double
    public var neck: Double
    /// Bow of the torso in px (positive rounds the back).
    public var curl: Double
    public var thighN: Double, shinN: Double, footN: Double
    public var thighF: Double, shinF: Double, footF: Double
    public var upperN: Double, foreN: Double, handN: Double
    public var upperF: Double, foreF: Double, handF: Double

    public init(
        torso: Double = -90, neck: Double? = nil, curl: Double = 0,
        legN: (Double, Double) = (90, 90), legF: (Double, Double) = (90, 90),
        armN: (Double, Double) = (90, 90), armF: (Double, Double) = (90, 90),
        footN: Double? = nil, footF: Double? = nil, handN: Double? = nil, handF: Double? = nil
    ) {
        self.torso = torso
        self.neck = neck ?? torso
        self.curl = curl
        thighN = legN.0
        shinN = legN.1
        self.footN = footN ?? legN.1 - 90
        thighF = legF.0
        shinF = legF.1
        self.footF = footF ?? legF.1 - 90
        upperN = armN.0
        foreN = armN.1
        self.handN = handN ?? armN.1
        upperF = armF.0
        foreF = armF.1
        self.handF = handF ?? armF.1
    }
}

/// Joints of the mannequin. Each joint except `hip` ends one segment whose angle it controls.
public enum Joint: String, Codable, CaseIterable, Sendable {
    case hip, shoulder, head
    case kneeN, ankleN, toeN, kneeF, ankleF, toeF
    case elbowN, wristN, handN, elbowF, wristF, handF

    /// The joint this one hangs from.
    public var parent: Joint? {
        switch self {
        case .hip: nil
        case .shoulder: .hip
        case .head: .shoulder
        case .kneeN, .kneeF: .hip
        case .ankleN: .kneeN
        case .ankleF: .kneeF
        case .toeN: .ankleN
        case .toeF: .ankleF
        case .elbowN, .elbowF: .shoulder
        case .wristN: .elbowN
        case .wristF: .elbowF
        case .handN: .wristN
        case .handF: .wristF
        }
    }

    public var isFar: Bool { rawValue.hasSuffix("F") }
}

public struct DrawingProp: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case bench, seat, pad, box, bar, cable, handle, dumbbell, kettlebell, plate, ball, machine, wall, mat

        public var label: String {
            switch self {
            case .bench: "Bench"
            case .seat: "Seat"
            case .pad: "Pad"
            case .box: "Box"
            case .bar: "Bar"
            case .cable: "Cable"
            case .handle: "Handle"
            case .dumbbell: "Dumbbell"
            case .kettlebell: "Kettlebell"
            case .plate: "Plate"
            case .ball: "Ball"
            case .machine: "Machine"
            case .wall: "Wall"
            case .mat: "Mat"
            }
        }

        /// Where a newly added prop attaches.
        public var defaultAnchor: Joint {
            switch self {
            case .bench, .seat, .machine, .mat: .hip
            case .pad: .kneeN
            case .box, .wall: .toeN
            case .bar, .cable, .handle, .dumbbell, .kettlebell, .ball: .wristN
            case .plate: .shoulder
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var anchor: Joint
    /// Offset from the anchor in viewBox px.
    public var dx: Double
    public var dy: Double

    public init(id: UUID = UUID(), _ kind: Kind, anchor: Joint? = nil, dx: Double = 0, dy: Double = 0) {
        self.id = id
        self.kind = kind
        self.anchor = anchor ?? kind.defaultAnchor
        self.dx = dx
        self.dy = dy
    }
}

// MARK: - Geometry

public struct Point2: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public func moved(_ angle: Double, _ length: Double) -> Point2 {
        let a = angle * .pi / 180
        return Point2(x + cos(a) * length, y + sin(a) * length)
    }

    public static func + (a: Point2, b: Point2) -> Point2 { Point2(a.x + b.x, a.y + b.y) }
    public static func - (a: Point2, b: Point2) -> Point2 { Point2(a.x - b.x, a.y - b.y) }
}

public enum FigureGeometry {
    public static let width = 400.0
    public static let height = 300.0
    public static let floor = 268.0

    public static let torso = 72.0, neck = 10.0, headRadius = 15.0
    public static let upperArm = 42.0, forearm = 38.0, hand = 10.0
    public static let thigh = 56.0, shin = 54.0, foot = 14.0
    public static let limbWidth = 14.0, torsoWidth = 26.0

    /// Joints relative to hip = (0, 0).
    public static func joints(_ p: FigurePose) -> [Joint: Point2] {
        var j: [Joint: Point2] = [.hip: Point2(0, 0)]
        j[.shoulder] = j[.hip]!.moved(p.torso, torso)
        j[.head] = j[.shoulder]!.moved(p.neck, neck + headRadius)
        j[.kneeN] = j[.hip]!.moved(p.thighN, thigh)
        j[.ankleN] = j[.kneeN]!.moved(p.shinN, shin)
        j[.toeN] = j[.ankleN]!.moved(p.footN, foot)
        j[.kneeF] = j[.hip]!.moved(p.thighF, thigh)
        j[.ankleF] = j[.kneeF]!.moved(p.shinF, shin)
        j[.toeF] = j[.ankleF]!.moved(p.footF, foot)
        j[.elbowN] = j[.shoulder]!.moved(p.upperN, upperArm)
        j[.wristN] = j[.elbowN]!.moved(p.foreN, forearm)
        j[.handN] = j[.wristN]!.moved(p.handN, hand)
        j[.elbowF] = j[.shoulder]!.moved(p.upperF, upperArm)
        j[.wristF] = j[.elbowF]!.moved(p.foreF, forearm)
        j[.handF] = j[.wristF]!.moved(p.handF, hand)
        return j
    }

    /// Offset that rests the lowest joint on the floor and centres the figure horizontally.
    public static func groundingOffset(_ j: [Joint: Point2]) -> Point2 {
        func bottom(_ k: Joint) -> Double {
            let r: Double = k == .head ? headRadius : (k == .hip || k == .shoulder ? torsoWidth / 2 : limbWidth / 2)
            return j[k]!.y + r
        }
        let lowest = Joint.allCases.map(bottom).max() ?? 0
        let xs = j.values.map(\.x)
        let cx = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
        return Point2(width / 2 - cx, floor + 1 - lowest)
    }

    /// Joints in viewBox coordinates.
    public static func placed(_ p: FigurePose, offset: Point2? = nil) -> [Joint: Point2] {
        let j = joints(p)
        let o = offset ?? groundingOffset(j)
        return j.mapValues { $0 + o }
    }

    /// Angle (degrees) from `a` to `b`.
    public static func angle(from a: Point2, to b: Point2) -> Double {
        atan2(b.y - a.y, b.x - a.x) * 180 / .pi
    }
}

extension FigurePose {
    /// Sets the angle of the segment that ends at `joint` (the designer drags joints).
    public mutating func setAngle(_ angle: Double, for joint: Joint) {
        switch joint {
        case .hip: break
        case .shoulder:
            let delta = angle - torso
            torso = angle
            neck += delta
        case .head: neck = angle
        case .kneeN: Self.shiftLeg(&thighN, &shinN, &footN, to: angle)
        case .kneeF: Self.shiftLeg(&thighF, &shinF, &footF, to: angle)
        case .ankleN:
            footN += angle - shinN
            shinN = angle
        case .ankleF:
            footF += angle - shinF
            shinF = angle
        case .toeN: footN = angle
        case .toeF: footF = angle
        case .elbowN: Self.shiftLeg(&upperN, &foreN, &handN, to: angle)
        case .elbowF: Self.shiftLeg(&upperF, &foreF, &handF, to: angle)
        case .wristN:
            handN += angle - foreN
            foreN = angle
        case .wristF:
            handF += angle - foreF
            foreF = angle
        case .handN: handN = angle
        case .handF: handF = angle
        }
    }

    /// Rotating the first segment of a limb carries the rest along (keeps the bend).
    private static func shiftLeg(_ a: inout Double, _ b: inout Double, _ c: inout Double, to angle: Double) {
        let delta = angle - a
        a = angle
        b += delta
        c += delta
    }
}

/// Starting points for the designer.
public enum PoseTemplate: String, CaseIterable, Sendable, Identifiable {
    case standing, seated, squat, lyingBack, lyingFront, plank, kneeling, hanging

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standing: "Standing"
        case .seated: "Seated"
        case .squat: "Squat"
        case .lyingBack: "On back"
        case .lyingFront: "On front"
        case .plank: "Plank"
        case .kneeling: "Kneeling"
        case .hanging: "Hanging"
        }
    }

    public var front: Bool { false }

    public var frames: [FigurePose] {
        switch self {
        case .standing:
            [FigurePose(armN: (90, 90), armF: (88, 88)), FigurePose(armN: (0, -40), armF: (5, -35))]
        case .seated:
            [FigurePose(legN: (0, 90), legF: (0, 90), armN: (60, 0), armF: (65, 0)),
             FigurePose(legN: (-40, 40), legF: (0, 90), armN: (60, 0), armF: (65, 0))]
        case .squat:
            [FigurePose(armN: (0, 0), armF: (0, 0)),
             FigurePose(torso: -60, legN: (-10, 110), legF: (-10, 110), armN: (0, 0), armF: (0, 0))]
        case .lyingBack:
            [FigurePose(torso: 180, legN: (-40, 75), legF: (-40, 75), armN: (-90, -90), armF: (-90, -90), footN: 0, footF: 0),
             FigurePose(torso: 180, legN: (-40, 75), legF: (-40, 75), armN: (-100, -110), armF: (-100, -110), footN: 0, footF: 0)]
        case .lyingFront:
            [FigurePose(torso: -2, legN: (180, 180), legF: (180, 180), armN: (120, 0), armF: (120, 0), footN: 90, footF: 90),
             FigurePose(torso: -22, neck: -50, legN: (180, 180), legF: (180, 180), armN: (90, 0), armF: (90, 0), footN: 90, footF: 90)]
        case .plank:
            [FigurePose(torso: -4, legN: (176, 176), legF: (176, 176), armN: (90, 90), armF: (90, 90), handN: 0, handF: 0),
             FigurePose(torso: -2, legN: (178, 178), legF: (178, 178), armN: (145, 45), armF: (145, 45), handN: 0, handF: 0)]
        case .kneeling:
            [FigurePose(legN: (0, 90), legF: (90, 180), armN: (90, 90), armF: (90, 90), footF: 180),
             FigurePose(legN: (0, 90), legF: (90, 180), armN: (-90, -90), armF: (-90, -90), footF: 180)]
        case .hanging:
            [FigurePose(armN: (-88, -90), armF: (-92, -90)),
             FigurePose(armN: (62, -100), armF: (58, -100))]
        }
    }

    public var props: [DrawingProp] {
        switch self {
        case .seated: [DrawingProp(.seat)]
        case .lyingBack, .lyingFront: [DrawingProp(.mat)]
        case .hanging: [DrawingProp(.bar)]
        default: []
        }
    }
}

/// Which drawn segment lights up for each primary muscle (same as the illustration generator).
public enum FigureHighlight: Sendable, Hashable {
    case thigh, shin, hipBlob, torso, shoulderBlob, upperArm, forearm

    public static func segments(for muscles: [Muscle]) -> Set<FigureHighlight> {
        Set(muscles.map { m -> FigureHighlight in
            switch m {
            case .quads, .hamstrings, .adductors, .hipFlexors: .thigh
            case .glutes: .hipBlob
            case .calves: .shin
            case .chest, .abs, .obliques, .lowerBack, .upperBack, .lats: .torso
            case .frontDelts, .sideDelts, .rearDelts, .rotatorCuff: .shoulderBlob
            case .biceps, .triceps: .upperArm
            case .forearms: .forearm
            }
        })
    }
}
