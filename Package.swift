// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPhotoOrganizer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacPhotoOrganizer", targets: ["MacPhotoOrganizer"]),
    ],
    targets: [
        .executableTarget(
            name: "MacPhotoOrganizer",
            path: "MacPhotoOrganizer",
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
