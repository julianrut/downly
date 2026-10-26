// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Downly",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Downly", targets: ["Downly"]),
        .executable(name: "downly-selftest", targets: ["SelfTest"]),
    ],
    targets: [
        .target(name: "DownlyCore", path: "Sources/DownlyCore"),
        .executableTarget(name: "Downly", dependencies: ["DownlyCore"], path: "Sources/Downly"),
        .executableTarget(name: "SelfTest", dependencies: ["DownlyCore"], path: "Sources/SelfTest"),
        .testTarget(name: "DownlyCoreTests", dependencies: ["DownlyCore"], path: "Tests/DownlyCoreTests"),
    ]
)
