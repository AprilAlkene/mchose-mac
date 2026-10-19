import Testing
import Foundation
@testable import HIDTransport

@Test func runsPerformedBlocksOnWorkerThread() throws {
    let worker = HIDRunLoopWorker(name: "test-hid-worker")
    let wasMain = try worker.call { Thread.isMainThread }
    #expect(wasMain == false)

    let name = try worker.call { Thread.current.name }
    #expect(name == "test-hid-worker")
}

@Test func keepsOneThreadAcrossCalls() throws {
    let worker = HIDRunLoopWorker(name: "test-hid-worker")
    let first = try worker.call { pthread_self() }
    let second = try worker.call { pthread_self() }
    #expect(first == second)
}

@Test func preservesSubmissionOrder() throws {
    let worker = HIDRunLoopWorker(name: "test-hid-worker")
    let lock = NSLock()
    var values: [Int] = []
    for index in 0..<20 {
        worker.perform {
            lock.lock()
            values.append(index)
            lock.unlock()
        }
    }
    // `call` is queued after the blocks above, so it acts as a barrier.
    try worker.call {}

    lock.lock()
    let collected = values
    lock.unlock()
    #expect(collected == Array(0..<20))
}

private struct WorkerTestError: Error {}

@Test func callPropagatesThrownErrors() {
    let worker = HIDRunLoopWorker(name: "test-hid-worker")
    #expect(throws: WorkerTestError.self) {
        try worker.call { throw WorkerTestError() }
    }
}
