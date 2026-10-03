import Darwin
import Foundation

/// The main actor serializes app mutations; socket reads/writes never block the UI.
@MainActor public final class ControlServer {
    private var source: DispatchSourceRead?
    private var lockFD: Int32 = -1
    private var clients = 0
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func start(handler: @escaping @MainActor @Sendable (ControlRequest) -> ControlResponse) throws {
        guard source == nil else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFDIR, (info.st_mode & 0o077) == 0 else {
            throw ControlError("Taskport's data directory must be owned by you with mode 0700, and must not be a symlink.")
        }
        let lock = open(directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw ControlError("Couldn't open the Taskport control lock.") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock); throw ControlError("Another Taskport app already owns this workspace.")
        }
        let path = directory.appendingPathComponent("control.sock").path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        do {
            guard fd >= 0 else { throw ControlError("Couldn't create the Taskport control socket.") }
            var address = try LocalSocket.address(path)
            // Only remove a stale owned socket, after obtaining the exclusive workspace lock.
            if lstat(path, &info) == 0 {
                guard info.st_uid == geteuid(), (info.st_mode & S_IFMT) == S_IFSOCK else {
                    throw ControlError("The control socket path contains another file. Nothing was replaced.")
                }
                guard unlink(path) == 0 else { throw ControlError("Couldn't remove the stale control socket.") }
            }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
                throw ControlError("Couldn't bind the Taskport control socket.")
            }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.acceptClients(fd, handler: handler) }
            }
            source.setCancelHandler { close(fd) }
            self.source = source
            lockFD = lock
            source.resume()
        } catch {
            if fd >= 0 { close(fd) }
            close(lock)
            throw error
        }
    }

    private func acceptClients(_ listener: Int32, handler: @escaping @MainActor @Sendable (ControlRequest) -> ControlResponse) {
        while true {
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { return }
            guard clients < 8 else { close(fd); continue }
            clients += 1
            LocalSocket.configure(fd)
            // Accepted sockets must use bounded blocking I/O on the detached worker.
            _ = fcntl(fd, F_SETFL, 0)
            Task.detached { [weak self] in
                defer { close(fd) }
                do {
                    try LocalSocket.verifyPeer(fd)
                    let data = try LocalSocket.readMessage(fd)
                    let response: ControlResponse
                    do {
                        let request = try JSONDecoder().decode(ControlRequest.self, from: data)
                        response = await handler(request)
                    } catch { response = .failure("Invalid control request JSON.") }
                    try LocalSocket.writeMessage(JSONEncoder().encode(response), to: fd)
                } catch { /* Broken clients cannot affect the app or another request. */ }
                await self?.finishedClient()
            }
        }
    }

    private func finishedClient() { clients -= 1 }

    public func stop() {
        source?.cancel(); source = nil
        if lockFD >= 0 {
            unlink(directory.appendingPathComponent("control.sock").path)
            close(lockFD); lockFD = -1
        }
    }
}
