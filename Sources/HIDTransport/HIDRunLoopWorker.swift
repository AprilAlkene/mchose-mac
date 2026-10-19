import Foundation

public enum HIDRunLoopWorkerError: Error, LocalizedError {
    case timeout

    public var errorDescription: String? {
        "Timed out waiting for the HID worker thread"
    }
}

/// Runs device I/O on one dedicated thread with a running CFRunLoop.
///
/// IOKit delivers input reports on the run loop that was current when
/// `IOHIDDeviceScheduleWithRunLoop` ran, so a connection has to perform all of
/// its reads/writes on the same thread. A plain `DispatchQueue` does not
/// guarantee that; this worker does.
public final class HIDRunLoopWorker {
    private final class State {
        let ready = DispatchSemaphore(value: 0)
        var runLoop: CFRunLoop?
    }

    private let state = State()

    public init(name: String = "local.mchose.hid-io") {
        let state = self.state
        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            // CFRunLoopRun returns immediately when the loop has no sources or
            // timers, so keep it alive with a far-future timer.
            let timer = CFRunLoopTimerCreate(
                kCFAllocatorDefault,
                CFAbsoluteTimeGetCurrent() + 60 * 60 * 24 * 365,
                0,
                0,
                0,
                { _, _ in },
                nil
            )
            CFRunLoopAddTimer(runLoop, timer, CFRunLoopMode.defaultMode)
            state.runLoop = runLoop
            state.ready.signal()
            CFRunLoopRun()
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
        state.ready.wait()
    }

    /// Queues `body` on the worker thread. Returns immediately.
    public func perform(_ body: @escaping () -> Void) {
        guard let runLoop = state.runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, body)
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs `body` on the worker thread and waits for the result.
    ///
    /// Must not be called from the worker thread itself.
    public func call<T>(_ body: @escaping () throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!
        perform {
            result = Result { try body() }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 10) == .success else {
            throw HIDRunLoopWorkerError.timeout
        }
        return try result.get()
    }
}
