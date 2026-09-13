// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SupperCore",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "SupperCore", targets: ["SupperCore"])],
    targets: [
        .target(name: "SupperCore", path: "Supper/Domain"),
        .testTarget(name: "SupperCoreTests", dependencies: ["SupperCore"], path: "Tests/Domain")
    ],
    swiftLanguageModes: [.v5]
)
