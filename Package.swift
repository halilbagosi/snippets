// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Snippets",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Snippets",
            path: "Sources/Snippets",
            resources: [
                .process("Resources"),
                .process("Views/Components/GlassBreakShaders.metal")
            ]
        ),
        .testTarget(
            name: "SnippetsTests",
            dependencies: ["Snippets"]
        )
    ]
)
