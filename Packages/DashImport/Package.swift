// swift-tools-version: 6.0
import PackageDescription

/// Importverktøyet for fase 9: leser et øyeblikksbilde (JSON) av PWA-basen, mapper det til
/// appens skjema og skriver én idempotent SQL-fil. Ingen nettverk, ingen nøkler.
let package = Package(
    name: "DashImport",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .executable(name: "dashimport", targets: ["dashimport"]),
        .library(name: "DashImportKit", targets: ["DashImportKit"]),
    ],
    dependencies: [
        .package(path: "../GolfgutuCore"),
    ],
    targets: [
        .target(
            name: "DashImportKit",
            dependencies: [.product(name: "GolfgutuCore", package: "GolfgutuCore")]
        ),
        .executableTarget(
            name: "dashimport",
            dependencies: ["DashImportKit"]
        ),
        .testTarget(
            name: "DashImportKitTests",
            dependencies: ["DashImportKit", .product(name: "GolfgutuCore", package: "GolfgutuCore")],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
