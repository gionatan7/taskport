import Foundation

enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case service, oneOff
    var id: Self { self }
    var label: String { self == .service ? "Long-running" : "One-off" }
}

struct TaskDefinition: Codable, Equatable {
    var name = ""
    var command = ""
    var directory = "."
    var kind: TaskKind = .service
    var environment: [String: String] = [:]

    func validated() throws -> Self {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { throw WorkspaceError("Enter a task name.") }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceError("Enter the command to run.")
        }
        guard !command.contains("\0"), !directory.contains("\0") else { throw WorkspaceError("Remove null characters from the task.") }
        guard environment.allSatisfy({ key, value in
            key.range(of: #"\A[A-Za-z_][A-Za-z0-9_]*\z"#, options: .regularExpression) != nil && !value.contains("\0")
        }) else { throw WorkspaceError("Use valid environment names and remove null characters from their values.") }
        if value.directory.isEmpty { value.directory = "." }
        return value
    }
}

struct ProjectTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var definition: TaskDefinition
    var pinned = false
    var source: String?
    var sourceKey: String?
    var importedDefinition: TaskDefinition?
    var localURL: String?
    var temporary = false
    var tunnelForTaskID: UUID?
    var isOverridden: Bool {
        guard var original = importedDefinition else { return false }
        // Run classification and pinning are Taskport preferences, not source edits.
        original.kind = definition.kind
        return original != definition
    }
    var isTunnel: Bool { sourceKey == "builtin:cloudflare" }
    var participatesInStatus: Bool { pinned && !temporary && definition.kind == .service && !isTunnel }
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var directory: String
    var iconName: String?
    var tasks: [ProjectTask] = []
    var selectedTaskID: UUID?
    var split: PaneSplit?
    var linkedTasks: [ProjectTask] { tasks.filter { !$0.isTunnel && !($0.localURL ?? "").isEmpty } }

    func workingDirectory(for task: ProjectTask) -> URL {
        let path = task.definition.directory.replacingOccurrences(of: "${workspaceFolder}", with: directory)
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        return URL(fileURLWithPath: directory).appendingPathComponent(path).standardizedFileURL
    }
}

enum PaneAxis: String, Codable, CaseIterable {
    case sideBySide, stacked
}

struct PaneSplit: Codable, Equatable {
    var taskID: UUID
    var axis: PaneAxis
    var ratio = 0.5
}

struct WorkspaceDocument: Codable, Equatable {
    var version = 2
    var projects: [Project] = []
    var selectedProjectID: UUID?
    var runningPinnedTaskIDs: Set<UUID>?
    var resumeTasksOnLaunch: Bool?
}

struct WorkspaceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum ProjectStatus: Equatable {
    case stopped, partial, running
    static func compute(tasks: [ProjectTask], running: Set<UUID>) -> Self {
        let pinned = tasks.filter(\.participatesInStatus)
        let count = pinned.filter { running.contains($0.id) }.count
        return count == 0 ? .stopped : count == pinned.count ? .running : .partial
    }
}

enum LocalAddress {
    static func validate(_ string: String) throws -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let url = URLComponents(string: trimmed), ["http", "https"].contains(url.scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, ["", "/"].contains(url.path),
              url.port.map({ (1...65535).contains($0) }) ?? true else {
            throw WorkspaceError("Use an HTTP or HTTPS origin with a port, without a path or credentials.")
        }
        return trimmed
    }
}
