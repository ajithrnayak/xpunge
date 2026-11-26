// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "xpunge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "xpunge", targets: ["xpunge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "XPungeCore"),
        .executableTarget(
            name: "xpunge",
            dependencies: [
                "XPungeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "XPungeCoreTests",
            dependencies: ["XPungeCore"],
            resources: [.copy("Fixtures")]
        ),
        // Output and argument handling in the executable.
        .testTarget(
            name: "XPungeTests",
            dependencies: ["xpunge", "XPungeCore"]
        ),
    ]
)
