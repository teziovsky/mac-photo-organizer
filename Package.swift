// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaOrganizer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MediaOrganizer", targets: ["MediaOrganizer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.3"),
    ],
    targets: [
        .executableTarget(
            name: "MediaOrganizer",
            path: "MediaOrganizer",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "Resources",
                "MediaOrganizer.entitlements",
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
            name: "MediaOrganizerTests",
            dependencies: ["MediaOrganizer"],
            path: "Tests/MediaOrganizerTests"
        ),
    ]
)
