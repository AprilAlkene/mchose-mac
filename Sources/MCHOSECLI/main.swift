import Foundation
import HIDTransport
import Protocol
import Features

enum CLIError: Error, LocalizedError {
    case noDevice
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .noDevice:
            return "No MCHOSE configuration interface found."
        case .usage(let message):
            return message
        }
    }
}

struct CLIOptions {
    var writePolicy: DeviceWritePolicy = .readOnly
    var command: String = "help"
    var arguments: [String] = []
}

let options = parseOptions()

func parseOptions() -> CLIOptions {
    var raw = Array(CommandLine.arguments.dropFirst())
    var options = CLIOptions()

    if raw.contains("--allow-write") {
        options.writePolicy = .allow
    } else if raw.contains("--dry-run") {
        options.writePolicy = .dryRun
    } else {
        // Read-only is the development default. Writing requires an explicit
        // `--allow-write` opt-in, matching the safety rules in the design spec.
        options.writePolicy = .readOnly
    }
    raw.removeAll { $0.hasPrefix("--") }

    options.command = raw.first ?? "help"
    options.arguments = Array(raw.dropFirst())
    return options
}

func configurationRef() -> HIDDeviceRef? {
    HIDEnumerator().listDevices().first {
        $0.info.identity.isSupportedVendor && $0.info.interface.isConfigurationInterface
    }
}

func loadManifest() throws -> DeviceManifest {
    let path = FileManager.default.currentDirectoryPath
        + "/Resources/DeviceManifests/ace68_turbo_16k.json"
    return try ManifestLoader.load(from: URL(fileURLWithPath: path))
}

func openConnection() throws -> DeviceConnection {
    guard let ref = configurationRef() else {
        throw CLIError.noDevice
    }
    let connection = DeviceConnection(ref: ref, manifest: try loadManifest())
    connection.writePolicy = options.writePolicy
    try connection.connect()
    return connection
}

func printWritePolicy() {
    switch options.writePolicy {
    case .allow:
        print("write policy: allow (--allow-write)")
    case .readOnly:
        print("write policy: read-only (pass --allow-write to enable writes)")
    case .dryRun:
        print("write policy: dry-run (writes are encoded but not sent)")
    }
}

func usage() -> String {
    """
    mchose-cli <command> [options]

    Safety options (default: read-only):
      --read-only              only read commands are sent (default)
      --allow-write            allow write commands
      --dry-run                encode writes but never send them

    Commands:
      list                     enumerate MCHOSE configuration interfaces
      open                     open the configuration interface
      monitor                  print raw input reports for 10 seconds
      watch [seconds]          print hotplug add/remove events (default 5s)
      info <reportId-hex>      send getInfo and print the response
      probe                    read info, triggers, keymap, light and base
      readraw <cmd> <off> <len>  read raw bytes with an arbitrary command
      snapshot [path]          capture a restorable snapshot (JSON)
      restore [path]           restore the latest snapshot (or a given file)
      switchprofile <index>    switch the active profile (needs --allow-write)
      selfcheck                read, write back, and compare all sections
                               (needs --allow-write)

    Examples:
      mchose-cli probe
      mchose-cli snapshot
      mchose-cli selfcheck --allow-write
      mchose-cli restore --allow-write
    """
}

func saveSnapshot(_ snapshot: DeviceSnapshot) throws -> URL {
    if let path = options.arguments.first {
        let url = URL(fileURLWithPath: path)
        try SnapshotStore.write(snapshot, to: url)
        return url
    }
    return try SnapshotStore.save(snapshot)
}

func loadSnapshot() throws -> (DeviceSnapshot, URL) {
    let url: URL
    if let path = options.arguments.first {
        url = URL(fileURLWithPath: path)
    } else {
        guard let latest = try SnapshotStore.latest() else {
            throw CLIError.usage(
                "No snapshot found in \(SnapshotStore.defaultDirectory().path). Run `mchose-cli snapshot` first."
            )
        }
        url = latest
    }
    return (try SnapshotStore.load(from: url), url)
}

func run() throws {
    switch options.command {
    case "list":
        let refs = HIDEnumerator().listDevices().filter {
            $0.info.identity.isSupportedVendor && $0.info.interface.isConfigurationInterface
        }
        if refs.isEmpty {
            print("No MCHOSE configuration interface found.")
        } else {
            for ref in refs {
                let info = ref.info
                print(
                    "\(info.product) vid=0x\(String(info.identity.vendorId, radix: 16)) " +
                    "pid=0x\(String(info.identity.productId, radix: 16)) " +
                    "usagePage=0x\(String(info.interface.usagePage, radix: 16)) " +
                    "usage=0x\(String(info.interface.usage, radix: 16)) " +
                    "in=\(info.interface.maxInputReportSize) out=\(info.interface.maxOutputReportSize) " +
                    "transport=\(info.transport)"
                )
            }
        }

    case "open":
        guard let ref = configurationRef() else {
            throw CLIError.noDevice
        }
        let handle = HIDDeviceHandle(device: ref.device)
        try handle.open()
        print("open=0x0 \(ref.info.product)")
        handle.close()

    case "monitor":
        guard let ref = configurationRef() else {
            throw CLIError.noDevice
        }
        let handle = HIDDeviceHandle(device: ref.device)
        try handle.open()
        try handle.startInputReports { reportId, bytes in
            print("report=0x\(String(reportId, radix: 16)) \(Hex.string(bytes))")
        }
        print("monitoring for 10 seconds; send a read command from the web driver or CLI to see input reports")
        RunLoop.current.run(until: Date().addingTimeInterval(10))
        handle.stopInputReports()
        handle.close()

    case "info":
        guard let reportIdHex = options.arguments.first,
              let reportId = UInt8(reportIdHex, radix: 16) else {
            throw CLIError.usage("usage: mchose-cli info <reportId-hex>")
        }
        guard let ref = configurationRef() else {
            throw CLIError.noDevice
        }
        let handle = HIDDeviceHandle(device: ref.device)
        try handle.open()
        defer { handle.close() }

        let session = CZSession(handle: handle)
        let response = try session.getInfo(reportId: reportId)

        print("response: \(Hex.string(response.raw))")
        print("command: 0x\(String(response.command, radix: 16))")
        print("payload length: \(response.payloadLength) offset: \(response.payloadOffset)")
        print("payload: \(Hex.string(response.payload))")
        if let date = String(bytes: response.payload.suffix(20), encoding: .utf8) {
            print("build date: \(date)")
        }

    case "probe":
        printWritePolicy()
        let connection = try openConnection()
        defer { connection.close() }
        _ = try connection.readInfo()
        Thread.sleep(forTimeInterval: 0.1)

        print("reading base...")
        let base = try connection.readBase()
        let profile = base?.profileIndex ?? 0
        if let base {
            print("active profile: \(base.profileIndex + 1)/\(base.profileCount)")
        }

        print("reading triggers...")
        let triggers = try connection.readTriggers(profile: profile)
        print("reading keymap...")
        let keys = try connection.readKeymap(profile: profile)
        print("reading light...")
        let light = try connection.readLightConfig(profile: profile)

        print("triggers: \(triggers.count)")
        if let first = triggers.first {
            print("first trigger: \(first)")
        }
        print("keymap: \(keys.count)")
        for key in keys.prefix(8) {
            print(
                " key \(key.index): \(key.name) type=\(key.type) " +
                "code1=\(key.code1) code2=\(key.code2)"
            )
        }
        if let light {
            print(
                "light: effect=\(light.effect) brightness=\(light.brightness) " +
                "speed=\(light.speed) color=\(light.hexColor) " +
                "sideBrightness=\(light.sideBrightness)"
            )
        }

    case "snapshot":
        let connection = try openConnection()
        defer { connection.close() }
        let snapshot = try connection.captureSnapshot()
        let url = try saveSnapshot(snapshot)
        print(
            "snapshot saved: \(url.path) " +
            "(product=\(snapshot.product) profile=\(snapshot.profileIndex + 1) " +
            "triggers=\(snapshot.triggers.count) " +
            "keys=\(snapshot.keymap.count) func=\(snapshot.funcConfig.count) base=\(snapshot.base.count))"
        )
        if options.writePolicy == .readOnly {
            print("write policy: read-only (snapshot only reads the device)")
        }

    case "restore":
        let connection = try openConnection()
        defer { connection.close() }
        let (snapshot, url) = try loadSnapshot()
        print("restore: \(url.path) captured \(snapshot.createdAt)")
        if snapshot.product != connection.ref.info.product {
            print(
                "warning: snapshot was captured from \(snapshot.product), " +
                "device reports \(connection.ref.info.product)"
            )
        }
        if options.writePolicy == .readOnly {
            throw CLIError.usage(
                "restore writes to the device; rerun with --allow-write (or --dry-run to validate only)"
            )
        }
        try connection.restore(snapshot)
        if options.writePolicy == .dryRun {
            print("dry-run: snapshot validated, no writes sent")
        } else {
            print("restored and verified all sections")
        }

    case "selfcheck":
        guard options.writePolicy == .allow else {
            throw CLIError.usage(
                "selfcheck writes the values it reads back; rerun with --allow-write"
            )
        }
        printWritePolicy()
        let connection = try openConnection()
        defer { connection.close() }
        _ = try connection.readInfo()
        Thread.sleep(forTimeInterval: 0.1)

        let base = try connection.readBase()
        let profile = base?.profileIndex ?? 0
        print("active profile: \(profile + 1)/\(base?.profileCount ?? 0)")

        let triggers = try connection.readTriggers(profile: profile)
        let keys = try connection.readKeymap(profile: profile)
        let funcConfig = try connection.readFuncConfig(profile: profile)
        let baseBytes = try connection.readBaseBytes()
        print(
            "read: triggers=\(triggers.count) keys=\(keys.count) " +
            "func=\(funcConfig.count) base=\(baseBytes.count)"
        )

        var writeErrors: [String] = []
        do {
            try connection.writeTriggers(triggers, profile: profile)
        } catch {
            writeErrors.append("triggers: \(error.localizedDescription)")
        }
        do {
            try connection.writeKeymap(keys, profile: profile)
        } catch {
            writeErrors.append("keymap: \(error.localizedDescription)")
        }
        do {
            try connection.writeFuncConfig(funcConfig, profile: profile)
        } catch {
            writeErrors.append("func: \(error.localizedDescription)")
        }
        do {
            try connection.writeBase(baseBytes)
        } catch {
            writeErrors.append("base: \(error.localizedDescription)")
        }
        print("write errors: \(writeErrors.isEmpty ? "none" : writeErrors.joined(separator: " | "))")

        let triggers2 = try connection.readTriggers(profile: profile)
        let keys2 = try connection.readKeymap(profile: profile)
        let func2 = try connection.readFuncConfig(profile: profile)
        let base2 = try connection.readBaseBytes()
        print("triggers match: \(triggers == triggers2)")
        print("keymap match: \(keys == keys2)")
        if keys != keys2 {
            let diffs = zip(keys, keys2).enumerated()
                .filter { $0.element.0 != $0.element.1 }
                .map { $0.offset }
            print("keymap diffs: count=\(diffs.count) first=\(diffs.prefix(12))")
            for index in diffs.prefix(5) {
                print("  key \(index): before=\(keys[index]) after=\(keys2[index])")
            }
        }
        print("func match: \(funcConfig == func2)")
        print("base match: \(baseBytes == base2)")

    case "switchprofile":
        guard let indexText = options.arguments.first,
              let index = Int(indexText) else {
            throw CLIError.usage("usage: mchose-cli switchprofile <index> [--allow-write]")
        }
        printWritePolicy()
        let connection = try openConnection()
        defer { connection.close() }
        try connection.switchProfile(index)
        if options.writePolicy == .dryRun {
            print("dry-run: profile switch validated, no writes sent")
        } else {
            let base = try connection.readBase()
            print("profile: \(base?.profileIndex ?? -1)")
        }

    case "readraw":
        guard options.arguments.count >= 3,
              let readCommand = UInt8(options.arguments[0], radix: 16),
              let readOffset = Int(options.arguments[1]),
              let readLength = Int(options.arguments[2]) else {
            throw CLIError.usage("usage: mchose-cli readraw <command-hex> <offset> <length>")
        }
        let connection = try openConnection()
        defer { connection.close() }
        _ = try connection.readInfo()
        Thread.sleep(forTimeInterval: 0.1)
        let bytes = try connection.readRaw(
            command: readCommand,
            offset: readOffset,
            length: readLength
        )
        print("read \(bytes.count) bytes: \(Hex.string(bytes))")

    case "watch":
        let seconds = options.arguments.first.flatMap(TimeInterval.init) ?? 5
        let monitor = HIDDeviceMonitor()
        let startedAt = Date()
        monitor.onDevicesChanged = { added in
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            print("[watch] \(added ? "added" : "removed") at +\(elapsed)s")
        }
        monitor.start()
        print("watching configuration interfaces for \(Int(seconds))s (unplug/replug the keyboard to test)")
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        monitor.stop()

    default:
        print(usage())
    }
}

do {
    try run()
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}
