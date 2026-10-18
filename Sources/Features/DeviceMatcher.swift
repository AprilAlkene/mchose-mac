import HIDTransport

public enum DeviceMatcher {
    public static func matches(
        info: HIDDeviceInfo,
        manifest: DeviceManifest
    ) -> Bool {
        manifest.identities.contains { identity in
            identity.mode == "normal"
                && identity.vendorId == info.identity.vendorId
                && identity.productId == info.identity.productId
        }
    }
}
