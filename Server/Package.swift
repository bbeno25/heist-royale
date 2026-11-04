// swift-tools-version: 6.2
import PackageDescription

// The game server: HeistCore's ServerCore (matchmaking, authoritative matches, ratings) behind a
// WebSocket. heist-client is a command-line player for end-to-end tests.
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
        .executableTarget(
            name: "HeistServer",
            dependencies: [
                .product(name: "HeistCore", package: "HeistCore"),
                .product(name: "ServerCore", package: "HeistCore"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
        .executableTarget(
            name: "HeistClient",
            dependencies: [
                .product(name: "HeistCore", package: "HeistCore"),
                .product(name: "ServerCore", package: "HeistCore"),
            ]
        ),
    ]
)
