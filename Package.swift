// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MCHOSEMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HIDTransport", targets: ["HIDTransport"]),
        .library(name: "Protocol", targets: ["Protocol"]),
        .library(name: "Features", targets: ["Features"]),
        .executable(name: "mchose-cli", targets: ["MCHOSECLI"]),
    ],
    targets: [
        .target(
            name: "HIDTransport",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(name: "Protocol", dependencies: ["HIDTransport"]),
        .target(name: "Features", dependencies: ["HIDTransport", "Protocol"]),
        .executableTarget(name: "MCHOSECLI", dependencies: ["HIDTransport", "Protocol", "Features"]),
        .testTarget(
            name: "HIDTransportTests",
            dependencies: ["HIDTransport"]
        ),
        .testTarget(
            name: "ProtocolTests",
            dependencies: ["Protocol", "HIDTransport"],
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: ["Features", "HIDTransport", "Protocol"]
        ),
    ]
)
