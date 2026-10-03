import Darwin
import Foundation

/// One bounded newline-delimited JSON request per owner-only Unix socket connection.
public enum LocalSocket {
    public static let maxMessageBytes = 1_048_576

    public static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw ControlError("Taskport's socket path is too long. Use a shorter TASKPORT_DATA_DIR for both app and CLI.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    public static func configure(_ fd: Int32) {
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    public static func verifyPeer(_ fd: Int32) throws {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else {
            throw ControlError("Taskport only accepts connections from the same macOS user.")
        }
    }

    public static func readMessage(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ControlError("Connection closed or timed out. A submitted change may have completed; check status before retrying.") }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maxMessageBytes else { throw ControlError("Control message exceeds the 1 MiB limit.") }
            if let end = data.firstIndex(of: 10) {
                guard end == data.index(before: data.endIndex) else { throw ControlError("Send one JSON request per connection.") }
                return Data(data[..<end])
            }
        }
    }

    public static func writeMessage(_ data: Data, to fd: Int32) throws {
        guard data.count < maxMessageBytes else { throw ControlError("Control response exceeds the 1 MiB limit.") }
        let framed = data + Data([10])
        try framed.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ControlError("Couldn't send the control message. Check status before retrying a change.") }
                offset += count
            }
        }
    }

    public static func connect(directory: URL) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError("Couldn't create a local socket.") }
        do {
            configure(fd)
            var address = try address(directory.appendingPathComponent("control.sock").path)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0 else {
                if errno == EPERM || errno == EACCES {
                    throw ControlError("Permission denied connecting to Taskport. Request permission to run this CLI outside the agent sandbox; do not rebuild the app or bypass approval.")
                }
                throw ControlError("Taskport isn't reachable. Run taskport launch, then retry. App and CLI must use the same TASKPORT_DATA_DIR.")
            }
            try verifyPeer(fd)
            return fd
        } catch { close(fd); throw error }
    }

    public static func request(_ request: ControlRequest, directory: URL = ControlPaths.directory) throws -> ControlResponse {
        let fd = try connect(directory: directory)
        defer { close(fd) }
        try writeMessage(JSONEncoder().encode(request), to: fd)
        return try JSONDecoder().decode(ControlResponse.self, from: readMessage(fd))
    }
}
