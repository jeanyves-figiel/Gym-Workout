// swift-tools-version: 5.9
import PackageDescription

// Apple Watch lift sensor (#383): rep detection, bar speed, range of motion and load–velocity maths.
// Pure Swift (no Core Motion) so it is tested with `swift test` on macOS; the Watch feeds it device motion.
let package = Package(
    name: "LiftSensor",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "LiftSensor", targets: ["LiftSensor"]),
    ],
    targets: [
        .target(name: "LiftSensor"),
        .testTarget(name: "LiftSensorTests", dependencies: ["LiftSensor"]),
    ]
)
