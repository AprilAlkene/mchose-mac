import Foundation
import HIDTransport
import Protocol
import Features

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

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

switch command {
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
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    let handle = HIDDeviceHandle(device: ref.device)
    do {
        try handle.open()
        print("open=0x0 \(ref.info.product)")
        handle.close()
    } catch {
        print("open failed: \(error.localizedDescription)")
        exit(1)
    }

case "monitor":
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    let handle = HIDDeviceHandle(device: ref.device)
    do {
        try handle.open()
        try handle.startInputReports { reportId, bytes in
            print("report=0x\(String(reportId, radix: 16)) \(Hex.string(bytes))")
        }
        print("monitoring for 10 seconds; send a read command from the web driver or CLI to see input reports")
        RunLoop.current.run(until: Date().addingTimeInterval(10))
        handle.stopInputReports()
        handle.close()
    } catch {
        print("monitor failed: \(error.localizedDescription)")
        exit(1)
    }

case "info":
    guard arguments.count >= 2, let reportId = UInt8(arguments[1], radix: 16) else {
        print("usage: mchose-cli info <reportId-hex>")
        exit(1)
    }
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    let handle = HIDDeviceHandle(device: ref.device)
    do {
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
    } catch {
        print("info failed: \(error.localizedDescription)")
        exit(1)
    }

case "probe":
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    do {
        let connection = DeviceConnection(
            ref: ref,
            manifest: try loadManifest()
        )
        try connection.connect()
        defer { connection.close() }
        _ = try connection.readInfo()
        Thread.sleep(forTimeInterval: 0.1)

        print("reading triggers...")
        let triggers = try connection.readTriggers()
        print("reading keymap...")
        let keys = try connection.readKeymap()
        print("reading light...")
        let light = try connection.readLightConfig()
        print("reading base...")
        let base = try connection.readBase()

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
        if let base {
            print("base: profile=\(base.profileIndex)/\(base.profileCount)")
        }
    } catch {
        print("probe failed: \(error.localizedDescription)")
        exit(1)
    }

case "selfcheck":
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    do {
        let connection = DeviceConnection(
            ref: ref,
            manifest: try loadManifest()
        )
        try connection.connect()
        defer { connection.close() }
        _ = try connection.readInfo()
        Thread.sleep(forTimeInterval: 0.1)

        let triggers = try connection.readTriggers()
        let keys = try connection.readKeymap()
        let funcConfig = try connection.readFuncConfig()
        let baseBytes = try connection.readBaseBytes()
        print(
            "read: triggers=\(triggers.count) keys=\(keys.count) " +
            "func=\(funcConfig.count) base=\(baseBytes.count)"
        )

        var writeErrors: [String] = []
        do {
            try connection.writeTriggers(triggers)
        } catch {
            writeErrors.append("triggers: \(error.localizedDescription)")
        }
        do {
            try connection.writeKeymap(keys)
        } catch {
            writeErrors.append("keymap: \(error.localizedDescription)")
        }
        do {
            try connection.writeFuncConfig(funcConfig)
        } catch {
            writeErrors.append("func: \(error.localizedDescription)")
        }
        do {
            try connection.writeBase(baseBytes)
        } catch {
            writeErrors.append("base: \(error.localizedDescription)")
        }
        print("write errors: \(writeErrors.isEmpty ? "none" : writeErrors.joined(separator: " | "))")

        let triggers2 = try connection.readTriggers()
        let keys2 = try connection.readKeymap()
        let func2 = try connection.readFuncConfig()
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
    } catch {
        print("selfcheck failed: \(error.localizedDescription)")
        exit(1)
    }

case "switchprofile":
    guard arguments.count >= 2, let index = Int(arguments[1]) else {
        print("usage: mchose-cli switchprofile <index>")
        exit(1)
    }
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    do {
        let connection = DeviceConnection(
            ref: ref,
            manifest: try loadManifest()
        )
        try connection.connect()
        defer { connection.close() }
        try connection.switchProfile(index)
        let base = try connection.readBase()
        print("profile: \(base?.profileIndex ?? -1)")
    } catch {
        print("switchprofile failed: \(error.localizedDescription)")
        exit(1)
    }

case "readraw":
    guard arguments.count >= 4,
          let readCommand = UInt8(arguments[1], radix: 16),
          let readOffset = Int(arguments[2]),
          let readLength = Int(arguments[3]) else {
        print("usage: mchose-cli readraw <command-hex> <offset> <length>")
        exit(1)
    }
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    do {
        let connection = DeviceConnection(
            ref: ref,
            manifest: try loadManifest()
        )
        try connection.connect()
        defer { connection.close() }
        _ = try connection.readInfo()
        Thread.sleep(forTimeInterval: 0.1)
        let bytes = try connection.readRaw(
            command: readCommand,
            offset: readOffset,
            length: readLength
        )
        print("read \(bytes.count) bytes: \(Hex.string(bytes))")
    } catch {
        print("readraw failed: \(error.localizedDescription)")
        exit(1)
    }

default:
    print("mchose-cli <list|open|monitor|info|probe|selfcheck|switchprofile|readraw>")
}
