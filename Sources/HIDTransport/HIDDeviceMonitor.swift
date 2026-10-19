import Foundation
import IOKit.hid

/// Watches for hotplug events of MCHOSE configuration interfaces.
///
/// Only the `usagePage 0x01 / usage 0x00` interface is matched, so the
/// manager never has to open a protected keyboard interface. Callbacks are
/// delivered on the main run loop.
public final class HIDDeviceMonitor {
    /// Called on the main run loop when a matching configuration interface
    /// appears (`added == true`) or disappears (`added == false`).
    public var onDevicesChanged: ((_ added: Bool) -> Void)?

    private let manager: IOHIDManager
    private var isStarted = false

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        stop()
    }

    public func start() {
        guard !isStarted else { return }

        let matching: [[String: Any]] = HIDDeviceIdentity.supportedVendorIds.map { vendorId in
            [
                kIOHIDVendorIDKey as String: vendorId,
                kIOHIDDeviceUsagePageKey as String: 0x01,
                kIOHIDDeviceUsageKey as String: 0x00,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemovalCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        // Opening can fail when no interface is present yet; callbacks for
        // later arrivals still fire, so the result is deliberately ignored.
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isStarted = true
    }

    public func stop() {
        guard isStarted else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isStarted = false
    }

    fileprivate func notifyChanged(added: Bool) {
        onDevicesChanged?(added)
    }
}

private func hidDeviceMatchingCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().notifyChanged(added: true)
}

private func hidDeviceRemovalCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().notifyChanged(added: false)
}
