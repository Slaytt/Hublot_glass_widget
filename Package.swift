// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hublot",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Hublot",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/Hublot"
        )
    ]
)
