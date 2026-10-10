// swift-tools-version: 6.0
// Fasit for app-mappingen: kompilerer appens egne Swift-filer for Tavla og konkurransene (kopiert inn av
// kjor.sh) mot GolfgutuCore, og skriver tabellene for test/fixtures/tavla.json som JSON. Ikke en del av
// appen; brukes bare til å lage test/fixtures/tavla.forventet.json.
import PackageDescription

let package = Package(
    name: "TavlaFasit",
    platforms: [.macOS("26.0")],
    dependencies: [.package(name: "GolfgutuCore", path: "../../../../Packages/GolfgutuCore")],
    targets: [
        .executableTarget(name: "TavlaFasit", dependencies: [.product(name: "GolfgutuCore", package: "GolfgutuCore")]),
    ],
    swiftLanguageModes: [.v6]
)
