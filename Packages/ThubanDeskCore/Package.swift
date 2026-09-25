// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThubanDeskCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ThubanDeskCore", targets: ["ThubanDeskCore"]),
        .executable(name: "thuban-desk-live-check", targets: ["ThubanDeskLiveCheck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "ThubanDeskCore",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Env-gated live check against a real Google Calendar (creates one test event, reads it back, deletes it).
        // Never run by tests, smoke or build scripts. See scripts/live_check.sh.
        .executableTarget(
            name: "ThubanDeskLiveCheck",
            dependencies: ["ThubanDeskCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ThubanDeskCoreTests",
            dependencies: ["ThubanDeskCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
