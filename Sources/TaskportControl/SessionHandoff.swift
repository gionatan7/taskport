import Darwin
import Foundation

/// Only IDs and configuration digests cross the restart boundary, never commands or secrets.
public struct SessionHandoff: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let projectID: UUID
        public let taskID: UUID
        public let fingerprint: String
        public let confirmedTunnelURL: String?
        public init(projectID: UUID, taskID: UUID, fingerprint: String, confirmedTunnelURL: String? = nil) {
            self.projectID = projectID; self.taskID = taskID; self.fingerprint = fingerprint
            self.confirmedTunnelURL = confirmedTunnelURL
        }
    }
    public let version: Int
    public let id: UUID
    public let createdAt: Date
    public let sourceProcessID: Int32
    public let entries: [Entry]
    public let openTaskIDs: Set<UUID>
    public let skipped: [ActionResult]

    public init(id: UUID, sourceProcessID: Int32, entries: [Entry], openTaskIDs: Set<UUID>,
                skipped: [ActionResult] = [], createdAt: Date = Date()) {
        version = 1; self.id = id; self.createdAt = createdAt; self.sourceProcessID = sourceProcessID
        self.entries = entries; self.openTaskIDs = openTaskIDs; self.skipped = skipped
    }

    private static func path(in directory: URL) -> URL { directory.appendingPathComponent("session-restore.json") }

    public static func validateDirectory(_ directory: URL) throws {
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFDIR, (info.st_mode & 0o077) == 0 else {
            throw ControlError("The restore directory must be owned by you, private (0700), and not a symlink.")
        }
    }

    public func save(in directory: URL) throws {
        try Self.validateDirectory(directory)
        // A fresh quit may replace an abandoned handoff, but never follow its symlink.
        let staging = directory.appendingPathComponent("restore-staging-\(UUID().uuidString).json")
        let fd = open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ControlError("Couldn't create the private restore checkpoint.") }
        defer { close(fd); unlink(staging.path) }
        let data = try JSONEncoder().encode(self)
        guard data.count <= LocalSocket.maxMessageBytes else { throw ControlError("The restore checkpoint is too large.") }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ControlError("Couldn't save the restore checkpoint.") }
                offset += count
            }
        }
        guard fsync(fd) == 0, rename(staging.path, Self.path(in: directory).path) == 0 else {
            throw ControlError("Couldn't finish saving the restore checkpoint.")
        }
        try Self.syncDirectory(directory)
    }

    public static func load(in directory: URL, now: Date = Date()) throws -> Self {
        try validateDirectory(directory)
        let fd = open(path(in: directory).path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ControlError("No saved session is available. Use quit --save-session first.") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(), (info.st_mode & S_IFMT) == S_IFREG,
              (info.st_mode & 0o077) == 0, info.st_size > 0, info.st_size <= LocalSocket.maxMessageBytes else {
            close(fd); throw ControlError("The saved session must be a private, owned, bounded regular file.")
        }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let data = try file.read(upToCount: LocalSocket.maxMessageBytes + 1) ?? Data()
        guard data.count <= LocalSocket.maxMessageBytes else { throw ControlError("The saved session is too large.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, value.sourceProcessID > 1,
              now.timeIntervalSince(value.createdAt) >= -60, now.timeIntervalSince(value.createdAt) < 86_400,
              Set(value.entries.map(\.taskID)).count == value.entries.count else {
            throw ControlError("The saved session is invalid or over 24 hours old. A normal launch discards it.")
        }
        return value
    }

    /// Consume durably before any task starts: retrying a launch cannot replay commands.
    public static func consume(_ id: UUID, in directory: URL) throws -> Self {
        let value = try load(in: directory)
        guard value.id == id else { throw ControlError("The saved session changed. No tasks were restored.") }
        try discard(in: directory)
        return value
    }

    public static func discard(in directory: URL) throws {
        try validateDirectory(directory)
        guard unlink(path(in: directory).path) == 0 || errno == ENOENT else {
            throw ControlError("Couldn't remove the saved session. No tasks were restored.")
        }
        try syncDirectory(directory)
    }

    private static func syncDirectory(_ directory: URL) throws {
        let fd = open(directory.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw ControlError("Couldn't sync the restore directory.") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw ControlError("Couldn't sync the consumed restore checkpoint.") }
    }
}

/// Serialize lifecycle clients, including the gap while no app owns the workspace.
public final class LifecycleLease {
    private let fd: Int32
    public init(directory: URL) throws {
        try SessionHandoff.validateDirectory(directory)
        fd = open(directory.appendingPathComponent("lifecycle.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ControlError("Couldn't open the lifecycle lock.") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); throw ControlError("Another Taskport restart or restore is in progress.")
        }
    }
    deinit { close(fd) }

    public static func requireStopped(directory: URL) throws {
        try SessionHandoff.validateDirectory(directory)
        let fd = open(directory.appendingPathComponent("control.lock").path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw ControlError("Couldn't inspect the workspace owner. Launch Taskport normally first.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            throw ControlError("Taskport still owns this workspace. Wait for it to quit before restoring.")
        }
    }
}
