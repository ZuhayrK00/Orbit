// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Orbit", targets: ["Orbit"]), .library(name: "OrbitCore", targets: ["OrbitCore"])],
    targets: [
        .target(name: "OrbitCore"),
        .executableTarget(name: "Orbit", dependencies: ["OrbitCore"]),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"]),
        .testTarget(name: "OrbitServiceTests", dependencies: ["Orbit", "OrbitCore"])
    ],
    swiftLanguageModes: [.v5]
)
