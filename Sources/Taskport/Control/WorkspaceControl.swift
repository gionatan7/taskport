import Foundation
import TaskportControl

/// CLI and UI share the same store and runtime sessions; no second writer or runner.
@MainActor struct WorkspaceControl {
    let store: WorkspaceStore

    func handle(_ request: ControlRequest) -> ControlResponse {
        do {
            try validateOptions(request)
            var response = ControlResponse()
            if request.operation == "projects.list" || request.operation == "status" {
                response.projects = store.document.projects.map { project in
                    ProjectInfo(id: project.id, name: project.name, directory: project.directory,
                        status: String(describing: store.status(of: project)),
                        taskCount: project.tasks.count, runningCount: store.runningCount(in: project),
                        listeningPorts: store.listeningPorts[project.id] ?? [])
                }
                if request.operation == "status" { response.tasks = allTasks() }
                return response
            }
            if request.operation == "sessions.list" {
                response.tasks = allTasks().filter { info in
                    guard let session = store.session(info.id), session.shellPID > 0 else { return false }
                    return request.flags.contains("all") || session.phase.isActive || session.manualCommandRunning
                }
                return response
            }
            if request.operation == "projects.add" {
                let directory = try required("directory", in: request)
                response.projectID = try store.addProject(name: request.values["name"] ?? URL(fileURLWithPath: directory).lastPathComponent,
                    directory: directory)
                return response
            }
            guard let projectID = request.projectID,
                  var project = store.document.projects.first(where: { $0.id == projectID }) else {
                throw WorkspaceError("Project ID not found. Run projects list first.")
            }
            response.projectID = project.id
            switch request.operation {
            case "tunnels.start", "tunnels.status", "tunnels.stop":
                guard request.taskIDs.count == 1,
                      let owner = project.tasks.first(where: { $0.id == request.taskIDs[0] && !$0.isTunnel }) else {
                    throw WorkspaceError("Specify exactly one server task ID from this project, not a tunnel ID.")
                }
                if request.operation == "tunnels.start" {
                    try store.startTunnel(for: owner.id, projectID: project.id,
                        confirmedURL: required("confirm-public-url", in: request), activate: false)
                } else if request.operation == "tunnels.stop" {
                    store.stopAssociatedTunnels(owner.id, projectID: project.id)
                }
                let updated = store.document.projects.first { $0.id == project.id } ?? project
                response.tasks = updated.tasks.filter { $0.isTunnel && $0.tunnelForTaskID == owner.id }
                    .map { taskInfo($0, project: updated) }
            case "projects.edit":
                if let name = request.values["name"] { project.name = name }
                if let directory = request.values["directory"] { project.directory = directory }
                try store.updateProject(project)
            case "tasks.list": response.tasks = project.tasks.map { taskInfo($0, project: project) }
            case "tasks.add", "tasks.edit":
                var task = ProjectTask(definition: TaskDefinition())
                if request.operation == "tasks.edit" {
                    guard request.taskIDs.count == 1, let existing = project.tasks.first(where: { $0.id == request.taskIDs[0] }) else {
                        throw WorkspaceError("Task ID not found. Run tasks list for this project first.")
                    }
                    guard !existing.isTunnel else { throw WorkspaceError("Manage the built-in tunnel through Task links.") }
                    let editsDefinition = !Set(request.values.keys).isDisjoint(with: ["name", "command", "cwd", "environment"])
                    if editsDefinition, existing.importedDefinition != nil, !existing.isOverridden, !request.flags.contains("confirm-local-override") {
                        throw WorkspaceError("This edits only Taskport's local copy, never the project file. Explain this before retrying with --confirm-local-override; modified tasks show Local override.")
                    }
                    task = existing
                }
                if let name = request.values["name"] { task.definition.name = name }
                if let command = request.values["command"] { task.definition.command = command }
                if let address = request.values["url"] { task.localURL = address }
                if let temporary = request.values["temporary"] {
                    guard ["true", "false"].contains(temporary) else { throw WorkspaceError("Use --temporary true or false.") }
                    task.temporary = temporary == "true"
                }
                if let directory = request.values["cwd"] { task.definition.directory = directory }
                if let kind = request.values["kind"] {
                    guard let kind = TaskKind(rawValue: kind) else { throw WorkspaceError("Use --kind service or --kind oneOff.") }
                    task.definition.kind = kind
                }
                if let pinned = request.values["pinned"] {
                    guard ["true", "false"].contains(pinned) else { throw WorkspaceError("Use --pinned true or false.") }
                    task.pinned = pinned == "true"
                    if task.pinned { task.definition.kind = .service }
                }
                if let env = request.values["environment"] {
                    task.definition.environment = try JSONDecoder().decode([String: String].self, from: Data(env.utf8))
                }
                try store.saveTask(task, projectID: project.id)
                response.taskID = task.id
            case "tasks.start", "tasks.stop":
                let tasks = try selectedTasks(request, project: project)
                response.results = tasks.map { task in
                    do {
                        let session = store.session(task.id)
                        if request.operation == "tasks.start" {
                            guard !task.isTunnel else { throw WorkspaceError("Use tunnels start with the server task ID and --confirm-public-url.") }
                            if session?.phase.isActive == true { return ActionResult(taskID: task.id, outcome: "already_active") }
                            try store.startTask(task.id, projectID: project.id, activate: false)
                            return ActionResult(taskID: task.id, outcome: "start_requested")
                        }
                        guard session?.phase.isActive == true else {
                            if session?.manualCommandRunning == true { throw WorkspaceError("A manual command is running. Stop it in the terminal; task stop will not interrupt unrelated work.") }
                            if task.temporary {
                                try store.closeTab(task.id, projectID: project.id)
                                return ActionResult(taskID: task.id, outcome: "removed")
                            }
                            store.stopAssociatedTunnels(task.id, projectID: project.id)
                            return ActionResult(taskID: task.id, outcome: "already_stopped")
                        }
                        store.stopTask(task.id, projectID: project.id)
                        return ActionResult(taskID: task.id, outcome: "stop_requested")
                    } catch { return ActionResult(taskID: task.id, outcome: "failed", error: error.localizedDescription) }
                }
                response.ok = response.results?.allSatisfy { $0.error == nil } ?? true
            default: throw WorkspaceError("Unknown control operation.")
            }
            return response
        } catch { return .failure(error.localizedDescription) }
    }

    private func selectedTasks(_ request: ControlRequest, project: Project) throws -> [ProjectTask] {
        if request.flags.contains("all") {
            guard request.taskIDs.isEmpty else { throw WorkspaceError("Use task IDs or --all, not both.") }
            return project.tasks.filter(\.participatesInStatus)
        }
        guard !request.taskIDs.isEmpty else { throw WorkspaceError("Specify task IDs or --all (pinned long-running tasks).") }
        // Validate the complete selection before any process is started or stopped.
        return try Array(Set(request.taskIDs)).sorted { $0.uuidString < $1.uuidString }.map { id in
            guard let task = project.tasks.first(where: { $0.id == id }) else { throw WorkspaceError("A task ID doesn't belong to this project. No tasks were changed.") }
            return task
        }
    }

    private func allTasks() -> [TaskInfo] {
        store.document.projects.flatMap { project in project.tasks.map { taskInfo($0, project: project) } }
    }

    private func taskInfo(_ task: ProjectTask, project: Project) -> TaskInfo {
        let session = store.session(task.id)
        let phase: String
        var exitCode: Int32?
        switch session?.phase ?? .stopped {
        case .stopped: phase = "stopped"
        case .starting: phase = "starting"
        case .running: phase = "running"
        case .stopping: phase = "stopping"
        case .exited(let code): phase = "exited"; exitCode = code
        case .failed: phase = "failed"
        }
        return TaskInfo(id: task.id, projectID: project.id, name: task.definition.name, command: task.definition.command,
            directory: task.definition.directory, kind: task.definition.kind.rawValue, phase: phase, pinned: task.pinned,
            localOverride: task.isOverridden, terminalInUse: session?.manualCommandRunning == true || session?.hasPendingInput == true,
            environmentKeys: task.definition.environment.keys.sorted(), source: task.source, exitCode: exitCode, shellPID: session?.shellPID ?? 0,
            localURL: task.localURL, temporary: task.temporary, tunnelForTaskID: task.tunnelForTaskID,
            remoteURL: session?.phase.isActive == true ? session?.remoteURL?.absoluteString : nil)
    }

    private func required(_ key: String, in request: ControlRequest) throws -> String {
        guard let value = request.values[key], !value.isEmpty else { throw WorkspaceError("Missing --\(key).") }
        return value
    }

    private func validateOptions(_ request: ControlRequest) throws {
        let allowed: Set<String>
        var flags: Set<String> = []
        switch request.operation {
        case "tunnels.start": allowed = ["confirm-public-url"]
        case "tunnels.status", "tunnels.stop": allowed = []
        case "projects.add", "projects.edit": allowed = ["name", "directory"]
        case "tasks.add", "tasks.edit": allowed = ["name", "command", "cwd", "kind", "pinned", "environment", "url", "temporary"]; flags = ["confirm-local-override"]
        case "tasks.start", "tasks.stop", "sessions.list": allowed = []; flags = ["all"]
        case "tasks.list", "projects.list", "status": allowed = []
        default: throw WorkspaceError("Unknown control operation.")
        }
        guard Set(request.values.keys).isSubset(of: allowed), request.flags.isSubset(of: flags) else {
            throw WorkspaceError("Unsupported option for this operation. Run taskport help.")
        }
    }
}
