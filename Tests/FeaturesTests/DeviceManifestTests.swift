import Foundation
import Testing
@testable import Features

@Test func loadsAce68Manifest() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/DeviceManifests/ace68_turbo_16k.json")

    let manifest = try ManifestLoader.load(from: url)

    #expect(manifest.displayName == "Ace 68 Turbo 16K")
    #expect(manifest.protocolFamily == "cz")
    #expect(manifest.verified)

    let identityMatches = manifest.identities.first {
        $0.vendorId == 0x3837 && $0.productId == 0x3026 && $0.mode == "normal"
    }
    #expect(identityMatches != nil)

    #expect(manifest.configInterface.usagePage == 1)
    #expect(manifest.configInterface.usage == 0)
}
