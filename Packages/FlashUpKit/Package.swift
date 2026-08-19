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
        .package(url: "https://github.com/apple/swift-markdown.git", exact: "0.8.0"),
        // zstd, for the modern `.apkg` container: Apple ships no zstd and there is no system
        // alternative. Upstream itself rather than a wrapper, pinned exact (ADR-004 §3).
        // `FlashUpData` only — `FlashUpDomain` stays dependency-free and portable.
        .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7")
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
            dependencies: [
                "FlashUpDomain",
                .product(name: "libzstd", package: "zstd")
            ],
            resources: [
                .process("CoreData/Model/FlashUp.xcdatamodeld"),
                // SwiftPM's macOS host build copies xcdatamodeld sources without invoking momc.
                // Keep the momc output in a distinct resource directory so Xcode's model compile
                // does not produce a duplicate FlashUp.momd output.
                .copy("CoreData/Model/Precompiled/FlashUpRuntime.momd")
            ],
            // System SQLite: `.apkg` carries an Anki collection database. Not a package —
            // it is already on every Apple platform (ADR-004 §3).
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "FlashUpDomainTests",
            dependencies: ["FlashUpDomain"]
        ),
        .testTarget(
            name: "FlashUpDataTests",
            dependencies: ["FlashUpData"],
            // Real `.apkg` files written by Anki itself, not synthesised: a fixture we build
            // ourselves would only prove the parser agrees with our own assumptions.
            // Regenerate with Tests/FlashUpDataTests/Fixtures/make_fixtures.py.
            resources: [.copy("Fixtures")]
        )
    ]
)
