// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AgenticIO",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "AgenticIO",
            targets: [
                "AgenticIO",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-agentic/Agentic.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Workspace.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Primitives.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Version.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Schema.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Macros.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/IO.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Writers.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Readers.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Path.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/FileTypes.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Selection.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Position.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Difference.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Concatenation.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Search.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-langs/Parsing.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Reporting.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Errors.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Clipboard.git",
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "AgenticIO",
            dependencies: [
                .product(
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticStandard",
                    package: "Agentic"
                ),
                .product(
                    name: "Reporting",
                    package: "Reporting"
                ),
                .product(
                    name: "Workspace",
                    package: "Workspace"
                ),
                .product(
                    name: "Primitives",
                    package: "Primitives"
                ),
                .product(
                    name: "Version",
                    package: "Version"
                ),
                .product(
                    name: "Schema",
                    package: "Schema"
                ),
                .product(
                    name: "Macros",
                    package: "Macros"
                ),
                .product(
                    name: "IO",
                    package: "IO"
                ),
                .product(
                    name: "Writers",
                    package: "Writers"
                ),
                .product(
                    name: "Errors",
                    package: "Errors"
                ),
                .product(
                    name: "Readers",
                    package: "Readers"
                ),
                .product(
                    name: "Path",
                    package: "Path"
                ),
                .product(
                    name: "PathParsing",
                    package: "Path"
                ),
                .product(
                    name: "FileTypes",
                    package: "FileTypes"
                ),
                .product(
                    name: "Selection",
                    package: "Selection"
                ),
                .product(
                    name: "Position",
                    package: "Position"
                ),
                .product(
                    name: "Difference",
                    package: "Difference"
                ),
                .product(
                    name: "Concatenation",
                    package: "Concatenation"
                ),
                .product(
                    name: "Search",
                    package: "Search"
                ),
                .product(
                    name: "Parsing",
                    package: "Parsing"
                ),
                .product(
                    name: "Clipboard",
                    package: "Clipboard"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)

for target in package.targets {
    switch target.type {
    case .regular, .executable, .test, .macro:
        var settings = target.swiftSettings ?? []

        settings.append(
            .treatAllWarnings(as: .error)
        )

        target.swiftSettings = settings

    case .plugin, .system, .binary:
        break

    @unknown default:
        break
    }
}
