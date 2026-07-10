// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TranslatorCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TranslatorCore", targets: ["TranslatorCore"])
    ],
    targets: [
        .target(name: "TranslatorCore"),
        .testTarget(name: "TranslatorCoreTests", dependencies: ["TranslatorCore"])
    ]
)
