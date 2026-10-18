import IOKit.hid

public final class HIDDeviceRef {
    public let info: HIDDeviceInfo
    public let device: IOHIDDevice

    public init(info: HIDDeviceInfo, device: IOHIDDevice) {
        self.info = info
        self.device = device
    }
}
