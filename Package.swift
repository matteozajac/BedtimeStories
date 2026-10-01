// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "BedtimeCore",
    platforms: [.macOS(.v15), .iOS("27.0")],
    products: [.library(name: "BedtimeCore", targets: ["BedtimeCore"])],
    targets: [
        .target(name: "BedtimeCore", path: "BedtimeStories/Core"),
        .testTarget(name: "BedtimeCoreTests", dependencies: ["BedtimeCore"], path: "Tests/BedtimeCoreTests")
    ]
)
