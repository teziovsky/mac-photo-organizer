// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TeziovskyUtilities",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TeziovskyUtilities", targets: ["TeziovskyUtilities"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.3"),
    ],
    targets: [
        .executableTarget(
            name: "TeziovskyUtilities",
            path: "TeziovskyUtilities",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "Resources",
                "TeziovskyUtilities.entitlements",
            ],
            linkerSettings: [
                .linkedFramework("Photos"),
                .linkedFramework("AppKit"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("Quartz"),
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "TeziovskyUtilitiesTests",
            dependencies: ["TeziovskyUtilities"],
            path: "Tests/TeziovskyUtilitiesTests"
        ),
    ]
)
