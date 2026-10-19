/// Assembles the payloads of one or more `CZResponse` pages into a single
/// contiguous byte buffer.
///
/// Two response families exist:
///
/// - **Addressed reads** (for example command `0x05`, func config) echo the
///   requested offset back in bytes 5..6, so the replies may be matched to the
///   correct page by offset even if they arrive out of order.
/// - **Streamed reads** (commands `0x08` and `0xA0`) always answer with offset
///   `0`, so arrival order is the only ordering information available.
public enum CZResponseAssembler {
    public static func assemble(
        _ responses: [CZResponse],
        expectedLength: Int
    ) -> [UInt8] {
        guard expectedLength > 0, !responses.isEmpty else { return [] }

        let ordered = order(responses)

        var result: [UInt8] = []
        result.reserveCapacity(expectedLength)
        for response in ordered {
            result.append(contentsOf: response.payload)
            if result.count >= expectedLength { break }
        }

        if result.count < expectedLength {
            // Keep the previous behaviour: a short read is zero-filled so that
            // callers always receive a fixed-size buffer.
            result.append(
                contentsOf: Array(repeating: 0, count: expectedLength - result.count)
            )
        }
        return Array(result.prefix(expectedLength))
    }

    /// Sorts replies by their echoed offset only when every reply has a
    /// distinct offset. Streamed replies all share offset `0`, in which case
    /// the original arrival order is preserved.
    static func order(_ responses: [CZResponse]) -> [CZResponse] {
        let offsets = responses.map(\.payloadOffset)
        guard Set(offsets).count == offsets.count else { return responses }
        return responses.sorted { $0.payloadOffset < $1.payloadOffset }
    }
}
