import Foundation
import HIDTransport

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
        var response: [UInt8] = []
        try handle.startInputReports { _, bytes in
            if bytes.count >= 2, bytes[0] == 0xAA, bytes[1] == 0x03, response.isEmpty {
                response = bytes
            }
        }

        var request: [UInt8] = [0x55, 0x03, 0x00, 0x38, 0x38, 0x00, 0x00, 0x00]
        request.append(contentsOf: Array(repeating: 0, count: 56))

        let deadline = Date().addingTimeInterval(2.0)
        for _ in 0..<2 {
            try handle.setOutputReport(reportId: UInt32(reportId), bytes: request)
            let attemptDeadline = Date().addingTimeInterval(0.4)
            while response.isEmpty && Date() < attemptDeadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            if !response.isEmpty { break }
        }
        while response.isEmpty && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        handle.stopInputReports()
        handle.close()

        if response.isEmpty {
            print("info failed: timed out waiting for a 0xAA 0x03 response")
            exit(1)
        }
        print("response: \(Hex.string(response))")
    } catch {
        print("info failed: \(error.localizedDescription)")
        exit(1)
    }

default:
    print("mchose-cli <list|open|monitor|info>")
}
