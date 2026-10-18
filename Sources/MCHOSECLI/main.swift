import Foundation
import HIDTransport

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

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
default:
    print("mchose-cli <list|open|monitor|info>")
}
