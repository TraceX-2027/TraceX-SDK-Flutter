// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tracex_flutter",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(
            name: "tracex-flutter",
            targets: ["tracex_flutter"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "tracex_flutter",
            dependencies: [],
            path: "Sources/tracex_flutter",
            resources: []
        )
    ]
)
