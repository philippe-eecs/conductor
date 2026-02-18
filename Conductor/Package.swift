// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Conductor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Conductor", targets: ["Conductor"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.4.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Conductor",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            path: "Sources",
            exclude: [
                "Info.plist",
                "Conductor.entitlements"
            ]
        ),
        .testTarget(
            name: "ConductorTests",
            dependencies: ["Conductor"],
            path: "Tests"
        )
    ]
)
