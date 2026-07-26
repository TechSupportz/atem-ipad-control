// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ATEMMiniController",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ATEMKit", targets: ["ATEMKit"]),
        .executable(name: "atem-probe", targets: ["ATEMProbe"]),
    ],
    targets: [
        .target(name: "ATEMKit"),
        .executableTarget(
            name: "ATEMProbe",
            dependencies: ["ATEMKit"]
        ),
        .testTarget(
            name: "ATEMKitTests",
            dependencies: ["ATEMKit"]
        ),
    ]
)
