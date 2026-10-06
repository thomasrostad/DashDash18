// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GolfgutuCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(name: "GolfgutuCore", targets: ["GolfgutuCore"]),
    ],
    targets: [
        .target(name: "GolfgutuCore"),
        .testTarget(
            name: "GolfgutuCoreTests",
            dependencies: ["GolfgutuCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
