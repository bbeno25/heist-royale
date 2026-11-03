// swift-tools-version: 6.2
import PackageDescription

// HeistCore holds the game rules and AI. It has no UI code, so the iOS app,
// the tests and (later) the Linux game server can all share it.
let package = Package(
    name: "HeistCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HeistCore", targets: ["HeistCore"]),
    ],
    targets: [
        .target(name: "HeistCore"),
        .testTarget(name: "HeistCoreTests", dependencies: ["HeistCore"]),
    ]
)
