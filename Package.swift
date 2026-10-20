// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DobleCaraM2022",
    targets: [
        .target(
            name: "PagePlan",
            path: "app",
            sources: ["PagePlan.swift"]
        ),
        .testTarget(
            name: "PagePlanTests",
            dependencies: ["PagePlan"],
            path: "Tests/PagePlanTests"
        ),
    ]
)
