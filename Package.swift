// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AlertMe",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-ios.git", .upToNextMajor(from: "4.4.0"))
    ],
    targets: [
        .executableTarget(
            name: "AlertMe",
            dependencies: [
                .product(name: "Lottie", package: "lottie-ios")
            ],
            resources: [
                .copy("Resources/train-animation.json")
            ]
        )
    ]
)
