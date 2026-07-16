// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeDeck",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DeckCore"),
        .executableTarget(name: "ClaudeDeck", dependencies: ["DeckCore"]),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"]),
    ]
)
