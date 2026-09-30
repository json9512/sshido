import Foundation

public enum ShortcutDisplay {
    public static func display(_ bytes: [UInt8]) -> String {
        if let s = String(bytes: bytes, encoding: .utf8),
           !s.isEmpty,
           s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f }) {
            return s
        }
        return bytes.map { String(format: "\\x%02x", $0) }.joined()
    }

    public static func parseByte(_ raw: String) -> UInt8? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("0x") {
            return UInt8(trimmed.dropFirst(2), radix: 16)
        }

        let containsHexLetter = trimmed.contains { ("a"..."f").contains($0) }
        if containsHexLetter {
            return UInt8(trimmed, radix: 16)
        }

        let allDigits = trimmed.allSatisfy { ("0"..."9").contains($0) }
        guard allDigits else { return nil }
        return UInt8(trimmed, radix: 10)
    }
}
