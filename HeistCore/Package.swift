// swift-tools-version: 6.2
import PackageDescription

// HeistCore holds the game rules and AI, with no UI code, so the iOS app, the tests and the game server
// all share it. ServerCore is the server's logic without the network (matchmaking, match rooms, ratings);
// the server wraps it in a WebSocket, and the app runs it in-process for offline matches against bots.
let package = Package(
    name: "HeistCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HeistCore", targets: ["HeistCore"]),
        .library(name: "ServerCore", targets: ["ServerCore"]),
    ],
    targets: [
        .target(name: "HeistCore"),
        .target(name: "ServerCore", dependencies: ["HeistCore"]),
        .testTarget(name: "HeistCoreTests", dependencies: ["HeistCore"]),
        .testTarget(name: "ServerCoreTests", dependencies: ["ServerCore"]),
    ]
)
