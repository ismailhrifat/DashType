// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DashType",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "DashTypeCore",
            targets: ["DashTypeCore"]
        ),
        .executable(
            name: "DashType",
            targets: ["DashTypeApp"]
        ),
    ],
    targets: [
        .target(
            name: "DashTypeCore"
        ),
        .executableTarget(
            name: "DashTypeApp",
            dependencies: ["DashTypeCore"]
        ),
        .testTarget(
            name: "DashTypeCoreTests",
            dependencies: ["DashTypeCore"]
        ),
    ]
)

