// swift-tools-version: 6.2
import PackageDescription

// The game server: matchmaking, authoritative matches and ratings, running the HeistCore engine.
// ServerCore holds the logic with no network code, so it is tested with in-memory connections;
// HeistServer puts it behind a WebSocket; heist-client is a command-line player for end-to-end tests.
let package = Package(
    name: "HeistServer",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "HeistServer", targets: ["HeistServer"]),
        .executable(name: "heist-client", targets: ["HeistClient"]),
    ],
    dependencies: [
        .package(path: "../HeistCore"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "ServerCore", dependencies: ["HeistCore"]),
        .executableTarget(
            name: "HeistServer",
            dependencies: [
                "HeistCore",
                "ServerCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
        .executableTarget(name: "HeistClient", dependencies: ["HeistCore", "ServerCore"]),
        .testTarget(name: "ServerCoreTests", dependencies: ["ServerCore"]),
    ]
)
