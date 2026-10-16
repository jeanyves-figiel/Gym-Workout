import Foundation

/// Three numbers in the Watch's device frame (Core Motion units: g for acceleration, rad/s for rotation).
public struct Vec3: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public var length: Double { dot(self).squareRoot() }

    public var unit: Vec3 {
        let l = length
        return l > 0 ? Vec3(x / l, y / l, z / l) : .zero
    }

    public static func * (v: Vec3, k: Double) -> Vec3 { Vec3(v.x * k, v.y * k, v.z * k) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
}

/// One device-motion reading: user acceleration (gravity removed) and gravity, both in g, and rotation rate.
public struct MotionSample: Equatable, Sendable {
    public var userAcceleration: Vec3
    public var gravity: Vec3
    /// Rotation rate magnitude in rad/s; 0 when unknown.
    public var rotationRate: Double

    public init(userAcceleration: Vec3, gravity: Vec3, rotationRate: Double = 0) {
        self.userAcceleration = userAcceleration
        self.gravity = gravity
        self.rotationRate = rotationRate
    }

    /// Acceleration along "up" (against gravity), in g.
    public var verticalUp: Double {
        let g = gravity.unit
        return g == .zero ? userAcceleration.z : -userAcceleration.dot(g)
    }
}
