// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HofundSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "HofundSDK", targets: ["HofundSDK"]),
    ],
    targets: [
        // No third-party dependencies — Foundation + URLSession only.
        .target(name: "HofundSDK"),
        .testTarget(name: "HofundSDKTests", dependencies: ["HofundSDK"]),
    ]
)
