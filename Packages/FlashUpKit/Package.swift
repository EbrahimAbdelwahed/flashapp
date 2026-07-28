// swift-tools-version: 5.10

import PackageDescription

// Dependency direction (spec §0.3): App -> FlashUpData -> FlashUpDomain -> (swift-fsrs, Foundation).
// FlashUpDomain must build for macOS so its tests run without a simulator.
let package = Package(
    name: "FlashUpKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FlashUpDomain", targets: ["FlashUpDomain"]),
        .library(name: "FlashUpData", targets: ["FlashUpData"])
    ],
    dependencies: [
        // FSRS engine, pinned to an exact commit rather than a tag: the latest tag (5.0.0)
        // declares its scheduler API `internal`, so nothing outside the module can call it.
        // Proven and recorded in docs/decisions/ADR-003-fsrs.md (bead fu-03 / B0.4).
        .package(
            url: "https://github.com/open-spaced-repetition/swift-fsrs.git",
            revision: "4fbaf20184d62f82a9f44f343337c61a2c5483e9"
        ),
        // Markdown AST parsing for the editor/renderer.
        .package(url: "https://github.com/apple/swift-markdown.git", exact: "0.8.0")
    ],
    targets: [
        .target(
            name: "FlashUpDomain",
            dependencies: [
                .product(name: "FSRS", package: "swift-fsrs"),
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .target(
            name: "FlashUpData",
            dependencies: ["FlashUpDomain"]
        ),
        .testTarget(
            name: "FlashUpDomainTests",
            dependencies: ["FlashUpDomain"]
        ),
        .testTarget(
            name: "FlashUpDataTests",
            dependencies: ["FlashUpData"]
        )
    ]
)
