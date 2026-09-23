// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MacBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacBar", targets: ["MacBar"])],
    targets: [
        .executableTarget(name: "MacBar"),
        .testTarget(name: "MacBarTests", dependencies: ["MacBar"])
    ]
)
