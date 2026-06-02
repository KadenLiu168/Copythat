// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Copythat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Copythat", targets: ["Copythat"])
    ],
    targets: [
        .executableTarget(
            name: "Copythat",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CopythatTests",
            dependencies: ["Copythat"]
        )
    ]
)
