// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LyngoCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "LyngoCore", targets: ["LyngoCore"])],
    targets: [
        .target(name: "LyngoCore"),
        .testTarget(name: "LyngoCoreTests", dependencies: ["LyngoCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
