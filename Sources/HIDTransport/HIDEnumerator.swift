import IOKit.hid

public final class HIDEnumerator {
    private static let propertyKeys = [
        "Product",
        "VendorID",
        "ProductID",
        "PrimaryUsagePage",
        "PrimaryUsage",
        "MaxInputReportSize",
        "MaxOutputReportSize",
        "Transport",
        "RegistryID",
    ]

    public init() {}

    public func listDevices() -> [HIDDeviceRef] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)

        // Manager open can fail with kIOReturnNotPermitted because protected
        // keyboard interfaces are present; device enumeration still works.
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return devices.compactMap { device in
            var properties: [String: Any] = [:]
            for key in Self.propertyKeys {
                if let value = IOHIDDeviceGetProperty(device, key as CFString) {
                    properties[key] = value
                }
            }
            guard let info = HIDDeviceInfo(properties: properties) else { return nil }
            return HIDDeviceRef(info: info, device: device)
        }
    }

    public static func configurationInfos(from infos: [HIDDeviceInfo]) -> [HIDDeviceInfo] {
        infos.filter { $0.interface.isConfigurationInterface }
    }
}
