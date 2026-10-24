import Foundation

public struct ControlRequest: Codable, Sendable {
    public var operation: String
    public var projectID: UUID?
    public var groupID: UUID?
    public var taskIDs: [UUID]
    public var values: [String: String]
    public var flags: Set<String>
    public init(operation: String, projectID: UUID? = nil, taskIDs: [UUID] = [],
                values: [String: String] = [:], flags: Set<String> = [], groupID: UUID? = nil) {
        self.operation = operation; self.projectID = projectID; self.taskIDs = taskIDs
        self.values = values; self.flags = flags
        self.groupID = groupID
    }
}

public struct ControlResponse: Codable, Sendable {
    public var ok = true
    public var error: String?
    public var projects: [ProjectInfo]?
    public var groups: [GroupInfo]?
    public var tasks: [TaskInfo]?
    public var results: [ActionResult]?
    public var ports: [Int]?
    public var projectID: UUID?
    public var taskID: UUID?
    public var groupID: UUID?
    public var output: String?
    public var outputTruncated: Bool?
    public var handoffID: UUID?
    public var processID: Int32?
    public var state: String?
    public init() {}
    public static func failure(_ message: String) -> Self {
        var response = Self(); response.ok = false; response.error = message; return response
    }
}

public struct GroupInfo: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let isCollapsed: Bool
    public let projectCount: Int
    public init(id: UUID, name: String, isCollapsed: Bool, projectCount: Int) {
        self.id = id; self.name = name; self.isCollapsed = isCollapsed; self.projectCount = projectCount
    }
}

public struct ProjectInfo: Codable, Sendable {
    public let id: UUID
    public let name, directory, status: String
    public let taskCount, runningCount: Int
    public let listeningPorts: [Int]
    public let groupID: UUID?
    public init(id: UUID, name: String, directory: String, status: String, taskCount: Int, runningCount: Int, listeningPorts: [Int] = [], groupID: UUID? = nil) {
        self.id = id; self.name = name; self.directory = directory
        self.status = status; self.taskCount = taskCount; self.runningCount = runningCount
        self.listeningPorts = listeningPorts
        self.groupID = groupID
    }
}

public struct TaskInfo: Codable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let name, command, directory, kind, phase: String
    public let pinned, localOverride, terminalInUse: Bool
    public let environmentKeys: [String]
    public let source: String?
    public let exitCode: Int32?
    public let shellPID: Int32
    public let localURL, remoteURL: String?
    public let temporary: Bool
    public let tunnelForTaskID: UUID?
    public init(id: UUID, projectID: UUID, name: String, command: String, directory: String, kind: String, phase: String,
                pinned: Bool, localOverride: Bool, terminalInUse: Bool, environmentKeys: [String],
                source: String?, exitCode: Int32?, shellPID: Int32, localURL: String?, temporary: Bool,
                tunnelForTaskID: UUID?, remoteURL: String?) {
        self.id = id; self.projectID = projectID; self.name = name; self.command = command; self.directory = directory
        self.kind = kind; self.phase = phase; self.pinned = pinned; self.localOverride = localOverride
        self.terminalInUse = terminalInUse; self.environmentKeys = environmentKeys
        self.source = source; self.exitCode = exitCode; self.shellPID = shellPID
        self.localURL = localURL; self.temporary = temporary; self.tunnelForTaskID = tunnelForTaskID; self.remoteURL = remoteURL
    }
}

public struct ActionResult: Codable, Sendable {
    public let taskID: UUID
    public let outcome: String
    public let error: String?
    public init(taskID: UUID, outcome: String, error: String? = nil) {
        self.taskID = taskID; self.outcome = outcome; self.error = error
    }
}

public struct ControlError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum ControlPaths {
    public static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["TASKPORT_DATA_DIR"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Taskport", isDirectory: true)
    }
}
