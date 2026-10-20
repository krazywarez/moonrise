// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MoonriseKit",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "SkyEngine", targets: ["SkyEngine"]),
        .library(name: "SkyRenderer", targets: ["SkyRenderer"]),
        .library(name: "Feeds", targets: ["Feeds"]),
        .library(name: "Library", targets: ["Library"]),
        .library(name: "ObservingLog", targets: ["ObservingLog"]),
        .library(name: "Answers", targets: ["Answers"]),
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
            resources: [.copy("Resources/bsc5.json"), .copy("Resources/constellations.json"), .copy("Resources/coastline.json"), .copy("Resources/spacecraft.json"), .copy("Resources/skycultures.json"), .copy("Resources/messier.json")]
        ),
        .target(name: "Feeds"),
        .target(name: "ObservingLog"),
        .target(name: "Library", resources: [.copy("Resources/pages"), .copy("Resources/tours"), .copy("Resources/stories")]),
        .target(name: "Answers", dependencies: ["SkyEngine", "SkyRenderer", "Feeds", "Library"]),
        .testTarget(name: "SkyEngineTests", dependencies: ["SkyEngine"]),
        .testTarget(name: "FeedsTests", dependencies: ["Feeds"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ObservingLogTests", dependencies: ["ObservingLog"]),
        .testTarget(name: "LibraryTests", dependencies: ["Library", "SkyRenderer", "SkyEngine"]),
        .testTarget(name: "SkyRendererTests", dependencies: ["SkyRenderer"]),
        .testTarget(name: "AnswersTests", dependencies: ["Answers"]),
    ]
)
