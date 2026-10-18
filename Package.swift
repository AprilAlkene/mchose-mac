// swift-tools-version: 5.9
import PackageDescription

let testSwiftSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-Xfrontend", "-load-plugin-library",
        "-Xfrontend", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib",
    ])
]

let testLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-Xlinker", "-rpath",
        "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
        "-Xlinker", "-rpath",
        "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
    ])
]

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
        .executableTarget(name: "MCHOSECLI", dependencies: ["HIDTransport", "Protocol"]),
        .testTarget(
            name: "HIDTransportTests",
            dependencies: ["HIDTransport"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
        .testTarget(
            name: "ProtocolTests",
            dependencies: ["Protocol", "HIDTransport"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: ["Features", "HIDTransport", "Protocol"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
    ]
)
