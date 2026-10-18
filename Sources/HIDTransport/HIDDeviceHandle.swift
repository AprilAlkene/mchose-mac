import Foundation
import IOKit.hid

public final class HIDDeviceHandle {
    private let device: IOHIDDevice
    private var isOpen = false
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var onInput: ((UInt8, [UInt8]) -> Void)?

    public init(device: IOHIDDevice) {
        self.device = device
    }

    deinit {
        stopInputReports()
        close()
    }

    public func open() throws {
        guard !isOpen else { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw HIDError.openFailed(result)
        }
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
    }

    public func setOutputReport(reportId: UInt32, bytes: [UInt8]) throws {
        guard isOpen, !bytes.isEmpty else {
            throw HIDError.notFound
        }
        let result = bytes.withUnsafeBufferPointer { buffer -> IOReturn in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(reportId),
                buffer.baseAddress!,
                buffer.count
            )
        }
        guard result == kIOReturnSuccess else {
            throw HIDError.ioKit(result)
        }
    }

    public func startInputReports(_ handler: @escaping (UInt8, [UInt8]) -> Void) throws {
        guard isOpen else {
            throw HIDError.notFound
        }
        stopInputReports()

        let size = 64
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
        inputBuffer = buffer
        onInput = handler

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            size,
            mchoseInputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    public func stopInputReports() {
        onInput = nil
        if let buffer = inputBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
            buffer.deinitialize(count: 64)
            buffer.deallocate()
            inputBuffer = nil
        }
    }

    fileprivate func handleInput(reportId: UInt32, bytes: [UInt8]) {
        onInput?(UInt8(truncatingIfNeeded: reportId), bytes)
    }
}

private func mchoseInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportId: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let handle = Unmanaged<HIDDeviceHandle>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: UnsafePointer(report), count: reportLength))
    handle.handleInput(reportId: reportId, bytes: bytes)
}
