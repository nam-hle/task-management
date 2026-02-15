// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TaskManagement",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TaskManagement",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "TaskManagementTests",
            dependencies: ["TaskManagement"],
            path: "Tests/TaskManagementTests"
        ),
    ]
)
