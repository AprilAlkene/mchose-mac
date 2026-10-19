import IOKit.hid

public final class HIDEnumerator {
    /// Interfaces that can carry the CZ configuration protocol, restricted to
    /// supported vendors: normal mode (`usagePage 0x01 / usage 0x00`) and the
    /// vendor boot mode (`0xFF00 / 0x01`). Matching these instead of every HID
    /// device keeps `IOHIDManagerOpen` away from protected keyboard and pointer
    /// interfaces, which would otherwise trigger an Input Monitoring prompt
    /// and stall enumeration for seconds.
    static let configurationMatching: [[String: Any]] = {
        var matching: [[String: Any]] = []
        for vendorId in HIDDeviceIdentity.supportedVendorIds {
            matching.append([
                kIOHIDVendorIDKey as String: vendorId,
                kIOHIDDeviceUsagePageKey as String: 0x01,
                kIOHIDDeviceUsageKey as String: 0x00,
            ])
            matching.append([
                kIOHIDVendorIDKey as String: vendorId,
                kIOHIDDeviceUsagePageKey as String: 0xFF00,
                kIOHIDDeviceUsageKey as String: 0x01,
            ])
        }
        return matching
    }()

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
        IOHIDManagerSetDeviceMatchingMultiple(
            manager,
            Self.configurationMatching as CFArray
        )

        // Opening can fail when no matching interface is present; enumeration
        // then simply yields no devices.
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
