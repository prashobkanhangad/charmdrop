// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CharmDrop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CharmDrop", targets: ["CharmDrop"])
    ],
    targets: [
        .executableTarget(
            name: "CharmDrop",
            path: "Sources/CharmDrop"
        ),
        .testTarget(
            name: "CharmDropTests",
            dependencies: ["CharmDrop"],
            path: "Tests/CharmDropTests"
        )
    ]
)
