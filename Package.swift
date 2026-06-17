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
            // AppIcon.icns is consumed only by scripts/build-app.sh, which copies it
            // straight into the .app's Contents/Resources. Exclude it here so SwiftPM
            // doesn't warn about an undeclared resource (it's never loaded at runtime).
            exclude: [
                "Resources/AppIcon.icns"
            ],
            resources: [
                .copy("Resources/train-animation.json")
            ]
        )
    ]
)
