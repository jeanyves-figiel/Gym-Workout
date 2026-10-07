// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GymCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WorkoutEngine", targets: ["WorkoutEngine"]),
        .library(name: "APIClient", targets: ["APIClient"]),
    ],
    targets: [
        .target(name: "WorkoutEngine"),
        .target(name: "APIClient"),
        .testTarget(name: "WorkoutEngineTests", dependencies: ["WorkoutEngine"]),
        .testTarget(name: "APIClientTests", dependencies: ["APIClient"]),
    ]
)
