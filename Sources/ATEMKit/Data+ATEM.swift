import Foundation

extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    func uint16BE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 1 < count else {
            return nil
        }

        return (UInt16(self[index(startIndex, offsetBy: offset)]) << 8)
            | UInt16(self[index(startIndex, offsetBy: offset + 1)])
    }

    mutating func setUInt16BE(_ value: UInt16, at offset: Int) {
        self[index(startIndex, offsetBy: offset)] = UInt8(truncatingIfNeeded: value >> 8)
        self[index(startIndex, offsetBy: offset + 1)] = UInt8(truncatingIfNeeded: value)
    }

    func hexString(separator: String = "") -> String {
        map { String(format: "%02x", $0) }.joined(separator: separator)
    }
}
