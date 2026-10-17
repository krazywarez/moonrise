// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MoonriseKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SkyEngine", targets: ["SkyEngine"]),
        .library(name: "SkyRenderer", targets: ["SkyRenderer"]),
        .library(name: "Feeds", targets: ["Feeds"]),
    ],
    targets: [
        // Astronomy Engine v2.1.19 (MIT), https://github.com/cosinekitty/astronomy
        .target(
            name: "CAstronomy",
            exclude: ["LICENSE"],
            cSettings: [.unsafeFlags(["-w"])]
        ),
        .target(name: "SkyEngine", dependencies: ["CAstronomy"]),
        .target(
            name: "SkyRenderer",
            dependencies: ["SkyEngine"],
            resources: [.copy("Resources/bsc5.json"), .copy("Resources/constellations.json"), .copy("Resources/coastline.json")]
        ),
        .target(name: "Feeds"),
        .testTarget(name: "SkyEngineTests", dependencies: ["SkyEngine"]),
        .testTarget(name: "FeedsTests", dependencies: ["Feeds"]),
        .testTarget(name: "SkyRendererTests", dependencies: ["SkyRenderer"]),
    ]
)
