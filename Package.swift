// swift-tools-version: 6.0
import PackageDescription

// Run the same profile and persistence tests on macOS without an iOS Simulator.
let package = Package(
    name: "FitOutCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FitOutCore", targets: ["FitOutCore"])],
    targets: [
        .target(name: "FitOutCore", path: "FitOut", sources: ["Models", "Core/Storage", "Features/Profile/ProfileData.swift", "Features/Profile/ProfileStore.swift", "Features/Gym/GymDomain.swift", "Features/Workouts/WorkoutDomain.swift"]),
        .testTarget(name: "FitOutCoreTests", dependencies: ["FitOutCore"], path: "FitOutTests", sources: ["ProfileTests.swift"])
    ]
)
