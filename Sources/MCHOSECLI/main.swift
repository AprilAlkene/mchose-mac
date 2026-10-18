import Foundation
import HIDTransport
import Protocol

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

func configurationRef() -> HIDDeviceRef? {
    HIDEnumerator().listDevices().first {
        $0.info.identity.isSupportedVendor && $0.info.interface.isConfigurationInterface
    }
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

default:
    print("mchose-cli <list|open|monitor|info>")
}
