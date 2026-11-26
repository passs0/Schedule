// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Schedule",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ScheduleCore",
            targets: ["ScheduleCore"]
        ),
        .executable(
            name: "Schedule",
            targets: ["ScheduleApp"]
        )
    ],
    targets: [
        .target(
            name: "ScheduleCore",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .executableTarget(
            name: "ScheduleApp",
            dependencies: ["ScheduleCore"]
        ),
        .executableTarget(
            name: "ScheduleCoreVerify",
            dependencies: ["ScheduleCore"]
        ),
        .testTarget(
            name: "ScheduleCoreTests",
            dependencies: ["ScheduleCore"]
        )
    ]
)
