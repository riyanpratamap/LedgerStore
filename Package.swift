// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LedgerStore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LedgerStore", targets: ["LedgerStore"]),
        .executable(name: "SeedTool", targets: ["SeedTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "LedgerStore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "SeedTool",
            dependencies: [
                "LedgerStore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "LedgerStoreTests",
            dependencies: [
                "LedgerStore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
