// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacOrganizer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacOrganizer", targets: ["MacOrganizer"]),
    ],
    targets: [
        .executableTarget(
            name: "MacOrganizer",
            path: "MacOrganizer",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "Resources",
            ],
            linkerSettings: [
                .linkedFramework("Photos"),
                .linkedFramework("AppKit"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("Quartz"),
            ]
        ),
    ]
)
