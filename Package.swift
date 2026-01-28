// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SchroSIM",
    platforms: [
        .macOS(.v13)
        ],
        products: [
            .library(name: "SchroSIM", targets: ["SchroSIM"]),
        ],
        targets: [
            .target(
                name: "SchroSIM",
                path: "Sources/SchroSIM"
            ),
            .testTarget(
                name: "SchroSIMTests",
                dependencies: ["SchroSIM"],
                path: "Tests/SchroSIMTests"
            ),
        ]
    )