import Foundation

public enum Hex {
    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func parse(_ string: String) -> [UInt8]? {
        let parts = string.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        guard !parts.isEmpty else { return [] }
        var result: [UInt8] = []
        for part in parts {
            guard part.count == 2, let value = UInt8(part, radix: 16) else { return nil }
            result.append(value)
        }
        return result
    }
}
