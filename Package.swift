// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RoomDeckAudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RoomDeckAudio", targets: ["RoomDeckAudioApp"])
    ],
    targets: [
        .executableTarget(
            name: "RoomDeckAudioApp",
            path: "Sources/RoomDeckAudioApp"
        ),
        .testTarget(
            name: "RoomDeckAudioAppTests",
            dependencies: ["RoomDeckAudioApp"],
            path: "Tests/RoomDeckAudioAppTests"
        ),
    ]
)
