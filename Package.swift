// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dynamico",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Dynamico",
            targets: ["Dynamico"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Dynamico",
            dependencies: [],
            path: "Sources/Dynamico"
        )
    ]
)
