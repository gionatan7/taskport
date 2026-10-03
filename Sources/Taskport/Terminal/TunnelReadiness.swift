import Foundation

/// Quick tunnels advertise a URL before connecting. Publish it only after registration.
struct TunnelReadiness {
    private var outputTail = ""
    private var advertisedURL: URL?
    private var connected = false
    private var published = false

    mutating func consume(_ data: Data) -> URL? {
        guard !published else { return nil }
        outputTail = String((outputTail + String(decoding: data, as: UTF8.self)).suffix(8192))
        if advertisedURL == nil,
           let range = outputTail.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com\b"#, options: .regularExpression) {
            advertisedURL = URL(string: String(outputTail[range]))
        }
        if outputTail.contains("Registered tunnel connection") { connected = true }
        guard connected, let advertisedURL else { return nil }
        published = true
        return advertisedURL
    }
}
