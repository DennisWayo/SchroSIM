// swift-tools-version: 5.9
import Foundation
import PackageDescription

let enterpriseUISourcePath = "enterprise/core-swift/Sources/schrosim-enterprise-ui"
let enterpriseUITestsPath = "enterprise/core-swift/Tests/EnterpriseUITests"
let hasEnterpriseUI = FileManager.default.fileExists(atPath: enterpriseUISourcePath)

var products: [Product] = [
    .library(
        name: "SchroSIM",
        targets: ["SchroSIM"]
    ),
    .executable(
        name: "schrosim-cli",
        targets: ["schrosim-cli"]
    ),
]

if hasEnterpriseUI {
    products.append(
        .executable(
            name: "schrosim-enterprise-ui",
            targets: ["schrosim-enterprise-ui"]
        )
    )
}

var targets: [Target] = [
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
    ),
]

if hasEnterpriseUI {
    targets.append(
        .executableTarget(
            name: "schrosim-enterprise-ui",
            dependencies: ["SchroSIM"],
            path: enterpriseUISourcePath
        )
    )

    if FileManager.default.fileExists(atPath: enterpriseUITestsPath) {
        targets.append(
            .testTarget(
                name: "EnterpriseUITests",
                dependencies: ["schrosim-enterprise-ui"],
                path: enterpriseUITestsPath
            )
        )
    }
}

let package = Package(
    name: "SchroSIM",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    targets: targets
)
