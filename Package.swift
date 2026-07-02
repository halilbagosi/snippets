// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Snippets",
    // macOS 26+ so the binary is stamped with the modern SDK — AppKit only
    // enables the Liquid Glass design (glass toolbar items, full-size traffic
    // lights) for executables linked against SDK 26 or newer.
    platforms: [.macOS(.v26)],
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
