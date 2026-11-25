// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AgenticIOTests",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "t_aio_all",
            targets: [
                "AgenticIOTesting",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-agentic/Agentic.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/IO.git",
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
            url: "https://github.com/swift-lco/Schema.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Writers.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Errors.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Path.git",
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
            url: "https://github.com/swift-lco/Concatenation.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Search.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-tooling/Testing.git",
            branch: "master"
        ),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "AgenticIOTesting",
            dependencies: [
                .product(name: "AgenticIO", package: "AgenticIO"),
                .product(name: "IO", package: "IO"),
                .product(
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "Workspace",
                    package: "Workspace"
                ),
                .product(
                    name: "Concatenation",
                    package: "Concatenation"
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
                    name: "Position",
                    package: "Position"
                ),
                .product(
                    name: "Schema",
                    package: "Schema"
                ),
                .product(
                    name: "Search",
                    package: "Search"
                ),
                .product(
                    name: "Selection",
                    package: "Selection"
                ),
                .product(
                    name: "Primitives",
                    package: "Primitives"
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
                    name: "Testing",
                    package: "Testing"
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
