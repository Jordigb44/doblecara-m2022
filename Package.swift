// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DobleCaraM2022",
    defaultLocalization: "es",
    targets: [
        .target(
            name: "PagePlan",
            path: "app",
            exclude: ["Resources"],
            sources: ["PagePlan.swift", "UpdateChecker.swift"]
        ),
        .testTarget(
            name: "PagePlanTests",
            dependencies: ["PagePlan"],
            path: "Tests/PagePlanTests"
        ),
    ]
)
