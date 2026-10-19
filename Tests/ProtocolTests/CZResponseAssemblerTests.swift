import Testing
@testable import Protocol
@testable import HIDTransport

private func response(
    command: UInt8 = 0x05,
    payload: [UInt8],
    offset: Int = 0
) -> CZResponse {
    CZResponse(
        command: command,
        payloadLength: payload.count,
        payloadOffset: offset,
        payload: payload,
        raw: []
    )
}

@Test func assemblesStreamedPagesInArrivalOrder() {
    // Streamed commands (0x08/0xA0) always answer with offset 0, so the
    // arrival order must be preserved.
    let first = response(command: 0xA0, payload: [1, 2, 3])
    let second = response(command: 0xA0, payload: [4, 5, 6])

    let assembled = CZResponseAssembler.assemble([first, second], expectedLength: 6)

    #expect(assembled == [1, 2, 3, 4, 5, 6])
}

@Test func assemblesAddressedPagesByOffset() {
    // Addressed reads (0x05) echo the requested offset; out-of-order replies
    // must be reordered before assembly.
    let pageZero = response(payload: [1, 2, 3], offset: 0)
    let pageOne = response(payload: [4, 5, 6], offset: 3)

    let assembled = CZResponseAssembler.assemble(
        [pageOne, pageZero],
        expectedLength: 6
    )

    #expect(assembled == [1, 2, 3, 4, 5, 6])
}

@Test func zeroFillsShortRead() {
    let page = response(command: 0x05, payload: [1, 2, 3], offset: 0)

    let assembled = CZResponseAssembler.assemble([page], expectedLength: 6)

    #expect(assembled == [1, 2, 3, 0, 0, 0])
}

@Test func assembleRejectsEmptyInput() {
    #expect(CZResponseAssembler.assemble([], expectedLength: 6).isEmpty)
    #expect(CZResponseAssembler.assemble([response(payload: [1])], expectedLength: 0).isEmpty)
}

@Test func assemblerTruncatesToExpectedLength() {
    let first = response(command: 0xA0, payload: Array(repeating: 0xAA, count: 4))
    let second = response(command: 0xA0, payload: Array(repeating: 0xBB, count: 4))

    let assembled = CZResponseAssembler.assemble([first, second], expectedLength: 6)

    #expect(assembled == [0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB])
}
