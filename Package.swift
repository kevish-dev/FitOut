// swift-tools-version: 6.0
import PackageDescription

// Run the same profile and persistence tests on macOS without an iOS Simulator.
let package = Package(
    name: "FitOutCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FitOutCore", targets: ["FitOutCore"])],
    targets: [
        .target(name: "FitOutCore", path: "FitOut/Models"),
        .testTarget(name: "FitOutCoreTests", dependencies: ["FitOutCore"], path: "FitOutTests", sources: ["ProfileTests.swift"])
    ]
)
