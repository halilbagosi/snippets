// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Snippets",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Snippets",
            path: "Sources/Snippets",
            resources: [
                .process("Resources"),
                .process("Views/Components/DisintegrationShaders.metal.txt")
            ]
        ),
        .testTarget(
            name: "SnippetsTests",
            dependencies: ["Snippets"]
        )
    ]
)
