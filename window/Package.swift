// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChatBoard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ChatBoard", targets: ["ChatBoard"]),
        .executable(name: "StandIn", targets: ["StandIn"]),
        .executable(name: "E2E", targets: ["E2E"]),
    ],
    targets: [
        // Everything that decides what the board shows, with no AppKit, so it can be tested.
        .target(name: "ChatBoardCore"),
        // The window, docking, the Cmd+D shortcut and the snapshot renderer.
        .executableTarget(name: "ChatBoard", dependencies: ["ChatBoardCore"]),
        // A stand-in for Claude that the end-to-end tests run the board beside, and the runner that drives both.
        // See scripts/e2e.sh.
        .executableTarget(name: "StandIn", path: "Sources/StandIn"),
        .executableTarget(name: "E2E", path: "Sources/E2E"),
        // Swift Testing. With only the Command Line Tools installed, run scripts/test.sh instead of `swift test`.
        .testTarget(name: "ChatBoardCoreTests", dependencies: ["ChatBoardCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
