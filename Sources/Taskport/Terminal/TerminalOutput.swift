import Foundation

/// Bounded session output for CLI inspection, never persisted. Escape-string payloads are not retained.
struct TerminalOutput {
    private enum Escape { case none, escape, csi, string, stringEscape }
    private var escape = Escape.none
    private var bytes = Data()
    private var truncated = false
    static let byteLimit = 131_072

    mutating func append(_ data: Data) {
        var clean = Data()
        for byte in data {
            switch escape {
            case .none:
                if byte == 0x1b { escape = .escape }
                else if byte >= 0x20 && byte != 0x7f || [0x09, 0x0a, 0x0d].contains(byte) { clean.append(byte) }
            case .escape:
                if byte == 0x5b { escape = .csi }
                else if [0x5d, 0x50, 0x5e, 0x5f, 0x58].contains(byte) { escape = .string }
                else if !(0x20...0x2f).contains(byte) { escape = .none }
            case .csi:
                if (0x40...0x7e).contains(byte) { escape = .none }
            case .string:
                if byte == 0x07 { escape = .none }
                else if byte == 0x1b { escape = .stringEscape }
            case .stringEscape:
                if byte == 0x5c { escape = .none }
                else if byte != 0x1b { escape = .string }
            }
        }
        bytes.append(clean)
        if bytes.count > Self.byteLimit {
            bytes.removeFirst(bytes.count - Self.byteLimit)
            truncated = true
        }
    }

    func tail(lines limit: Int) -> (text: String, truncated: Bool) {
        let text = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let count = lines.count - (lines.last == "" ? 1 : 0)
        let start = max(0, count - max(1, limit))
        return (lines.dropFirst(start).joined(separator: "\n"), truncated || start > 0)
    }
}
