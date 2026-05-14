// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SchroSIM",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SchroSIM",
            targets: ["SchroSIM"]
        ),
        .executable(
            name: "schrosim-cli",
            targets: ["schrosim-cli"]
        )
    ],
    targets: [
        // =========================
        // Core library
        // =========================
        .target(
            name: "SchroSIM",
            path: "core-swift/Sources/SchroSIM"
        ),

        // =========================
        // CLI executable
        // =========================
        .executableTarget(
            name: "schrosim-cli",
            dependencies: ["SchroSIM"],
            path: "core-swift/Sources/schrosim-cli"
        ),

        // =========================
        // Tests
        // =========================
        .testTarget(
            name: "SchroSIMTests",
            dependencies: ["SchroSIM"],
            path: "core-swift/Tests/SchroSIMTests"
        )
    ]
)
