// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VSDXStudio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VSDXStudio", targets: ["VSDXStudio"])
    ],
    targets: [
        .target(
            name: "CZLib",
            path: "Sources/CZLib",
            publicHeadersPath: "include"
        ),
        .target(
            name: "VSDXCore",
            dependencies: ["CZLib"],
            path: "Sources/VSDXCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VSDXStudio",
            dependencies: ["VSDXCore"],
            path: "Sources/VSDXStudio",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VSDXTests",
            dependencies: ["VSDXCore"],
            path: "Tests/VSDXTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
