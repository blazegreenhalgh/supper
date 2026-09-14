// swift-tools-version: 6.0
import PackageDescription

var targets: [Target] = [
    .target(name: "SupperCore", path: "Supper/Domain"),
    .testTarget(name: "SupperCoreTests", dependencies: ["SupperCore"], path: "Tests/Domain")
]
#if os(macOS)
targets += [
    .target(name: "SupperPersistence", dependencies: ["SupperCore"], path: "Supper/Persistence"),
    .testTarget(name: "SupperPersistenceTests", dependencies: ["SupperPersistence", "SupperCore"], path: "Tests/Persistence")
]
#endif
let package = Package(name: "SupperCore", platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "SupperCore", targets: ["SupperCore"])], targets: targets, swiftLanguageModes: [.v5])
