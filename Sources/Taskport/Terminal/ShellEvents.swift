import Foundation

/// Incremental parser for Taskport's own nonce-tagged OSC messages, not terminal text.
struct ShellEvents {
    enum Event: Equatable { case ready(Int32), busy }
    private let prefix: Data
    private var pending = Data()

    init(token: String) { prefix = Data("\u{1B}]777;taskport;\(token);".utf8) }

    mutating func consume(_ data: Data) -> (output: Data, events: [Event]) {
        pending.append(data)
        var output = Data()
        var events: [Event] = []
        while let marker = pending.range(of: prefix) {
            output.append(pending[..<marker.lowerBound])
            pending.removeSubrange(..<marker.lowerBound)
            guard let end = pending.firstIndex(of: 7) else {
                if pending.count > 4096 { output.append(pending); pending.removeAll() }
                return (output, events)
            }
            let payload = String(decoding: pending.dropFirst(prefix.count).prefix(upTo: end), as: UTF8.self)
            if payload == "busy" { events.append(.busy) }
            else if payload.hasPrefix("ready;"), let code = Int32(payload.dropFirst(6)) { events.append(.ready(code)) }
            pending.removeSubrange(...end)
        }
        var keep = min(pending.count, prefix.count - 1)
        while keep > 0, pending.suffix(keep) != prefix.prefix(keep) { keep -= 1 }
        output.append(pending.prefix(pending.count - keep))
        pending = Data(pending.suffix(keep))
        return (output, events)
    }
}
