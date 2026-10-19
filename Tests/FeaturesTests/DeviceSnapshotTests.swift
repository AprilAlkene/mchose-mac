import Foundation
import Testing
@testable import Features

private func makeSnapshot() -> DeviceSnapshot {
    DeviceSnapshot(
        product: "Ace 68 Turbo 16K",
        firmwareVersion: "126",
        createdAt: Date(timeIntervalSince1970: 1_790_000_000),
        profileIndex: 1,
        triggers: [
            TriggerConfig(
                switchType: 1,
                keyMode: 2,
                priority: 0,
                keyActuation: 135,
                pressPrecision: 1,
                releasePrecision: 1,
                rtPress: 300,
                rtRelease: 300,
                pressDeadzone: 0,
                releaseDeadzone: 0
            )
        ],
        keymap: [
            KeyInfo(type: 16, code1: 0, code2: 41, name: "Esc", index: 0),
            KeyInfo(type: 255, code1: 0, code2: 0, name: "空", index: 1),
        ],
        funcConfig: [UInt8](repeating: 0x11, count: 64),
        base: [UInt8](repeating: 0x22, count: 56)
    )
}

@Test func snapshotCodableRoundTrip() throws {
    let snapshot = makeSnapshot()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(DeviceSnapshot.self, from: data)

    #expect(decoded == snapshot)
}

@Test func snapshotWithoutProfileIndexDecodesAsProfileZero() throws {
    // Compatibility with snapshots written before `profileIndex` existed.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(makeSnapshot())

    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object.removeValue(forKey: "profileIndex")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(DeviceSnapshot.self, from: legacyData)

    #expect(decoded.profileIndex == 0)
}

@Test func snapshotStoreSaveLoadAndLatest() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mchose-snapshot-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let snapshot = makeSnapshot()
    let url = try SnapshotStore.save(snapshot, directory: directory)
    #expect(FileManager.default.fileExists(atPath: url.path))

    let loaded = try SnapshotStore.load(from: url)
    #expect(loaded == snapshot)

    let latest = try SnapshotStore.latest(in: directory)
    #expect(latest?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
}

@Test func snapshotStoreWritesToExplicitFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mchose-snapshot-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("manual/snapshot.json")
    let snapshot = makeSnapshot()
    try SnapshotStore.write(snapshot, to: url)

    let loaded = try SnapshotStore.load(from: url)
    #expect(loaded == snapshot)
    // `latest` only scans the top level of the directory, so a snapshot
    // written into a nested path is not returned.
    #expect(try SnapshotStore.latest(in: directory) == nil)
}

@Test func snapshotStoreLatestReturnsNilForMissingDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mchose-snapshot-missing-\(UUID().uuidString)")
    #expect(try SnapshotStore.latest(in: directory) == nil)
}
