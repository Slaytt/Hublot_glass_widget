// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hublot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Hublot", path: "Sources/Hublot")
    ]
)
