// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DashType",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            from: "12.7.0"
        ),
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
            dependencies: [
                "DashTypeCore",
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            ]
        ),
        .testTarget(
            name: "DashTypeCoreTests",
            dependencies: ["DashTypeCore"]
        ),
    ]
)
