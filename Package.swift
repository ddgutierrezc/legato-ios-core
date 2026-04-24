// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LegatoCore",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "LegatoCore",
            targets: [
                "LegatoCore",
                "LegatoCoreSessionRuntimeiOS"
            ]
        )
    ],
    targets: [
        .target(
            name: "LegatoCore",
            path: "Sources/LegatoCore"
        ),
        .target(
            name: "LegatoCoreSessionRuntimeiOS",
            dependencies: ["LegatoCore"],
            path: "Sources/LegatoCoreSessionRuntimeiOS"
        ),
        .testTarget(
            name: "LegatoCoreTests",
            dependencies: ["LegatoCore"],
            path: "Tests/LegatoCoreTests"
        ),
        .testTarget(
            name: "LegatoCoreSessionRuntimeiOSTests",
            dependencies: [
                "LegatoCore",
                "LegatoCoreSessionRuntimeiOS"
            ],
            path: "Tests/LegatoCoreSessionRuntimeiOSTests"
        )
    ]
)
