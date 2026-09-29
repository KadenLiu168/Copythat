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
            exclude: [
                "Resources/AppIcon.icns",
                "Resources/AppIcon-transparent.png",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .process("Resources/MenuBarIconTemplate.png")
            ]
        ),
        .testTarget(
            name: "CopythatTests",
            dependencies: ["Copythat"]
        )
    ]
)
