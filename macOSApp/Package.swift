// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WallpaperControlApp",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "WallpaperControlApp", targets: ["WallpaperControlApp"]),
    ],
    targets: [
        .target(
            name: "PythonBridgeKit",
            path: "Sources/PythonBridgeKit",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "WallpaperControlApp",
            dependencies: ["PythonBridgeKit"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "WallpaperControlAppTests",
            dependencies: ["WallpaperControlApp"],
            path: "Tests/WallpaperControlAppTests"
        )
    ]
)
