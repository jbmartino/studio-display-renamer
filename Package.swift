// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StudioDisplayRenamer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StudioDisplayRenamer",
            path: "Sources"
        ),
        .testTarget(
            name: "StudioDisplayRenamerTests",
            dependencies: ["StudioDisplayRenamer"],
            path: "Tests"
        )
    ]
)
