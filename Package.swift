// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPhotoOrganizer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacPhotoOrganizer", targets: ["MacPhotoOrganizer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.3"),
    ],
    targets: [
        .executableTarget(
            name: "MacPhotoOrganizer",
            path: "MacPhotoOrganizer",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "Resources",
                "MacPhotoOrganizer.entitlements",
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
            name: "MacPhotoOrganizerTests",
            dependencies: ["MacPhotoOrganizer"],
            path: "Tests/MacPhotoOrganizerTests"
        ),
    ]
)
