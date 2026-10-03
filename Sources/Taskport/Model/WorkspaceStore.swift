import AppKit
import Observation
import SwiftUI

/// Single writer for saved definitions. Runtime sessions are deliberately not Codable.
@MainActor @Observable
final class WorkspaceStore {
    private(set) var document = WorkspaceDocument()
    private(set) var sessions: [TaskSession] = []
    var listeningPorts: [UUID: [Int]] = [:]
    private(set) var isReadOnly = false
    private var closingTabIDs: Set<UUID> = []
    private var openTabIDs: Set<UUID> = []
    private(set) var preservingResumeState = false
    var errorMessage: String?
    var tunnelCopyNotice: UUID?
    var pendingTunnelCopies: Set<UUID> = []
    @ObservationIgnored let persistence: WorkspacePersistence

    init(directory: URL = WorkspacePersistence.applicationDirectory) {
        persistence = WorkspacePersistence(directory: directory)
        do { document = try persistence.load() }
        catch {
            isReadOnly = true
            errorMessage = "Couldn't load the saved workspace. Nothing has been overwritten. \(error.localizedDescription)"
        }
    }

    var selectedProject: Project? { document.projects.first { $0.id == document.selectedProjectID } }
    var selectedTaskID: UUID? { selectedProject?.selectedTaskID }
    var resumeTasksOnLaunch: Bool { document.resumeTasksOnLaunch ?? true }

    func setResumeTasksOnLaunch(_ enabled: Bool) throws {
        try commit {
            $0.resumeTasksOnLaunch = enabled
            if !enabled { $0.runningPinnedTaskIDs = [] }
        }
        recordRunningPinnedTasks()
    }
    var activeCount: Int { sessions.filter { $0.phase.isActive }.count }
    var openShellCount: Int { sessions.filter { $0.shellPID > 0 }.count }

    func session(_ taskID: UUID) -> TaskSession? { sessions.first { $0.id == taskID } }
    func visibleTasks(in project: Project) -> [ProjectTask] {
        project.tasks.filter { !closingTabIDs.contains($0.id) && ($0.pinned || openTabIDs.contains($0.id) || session($0.id) != nil || project.selectedTaskID == $0.id || project.split?.taskID == $0.id) }
    }
    func hasRunningTasks(in project: Project) -> Bool {
        sessions.contains { $0.projectID == project.id && ($0.phase.isActive || $0.manualCommandRunning) }
    }

    func stopAll(in project: Project) {
        sessions.filter { $0.projectID == project.id }.forEach { $0.stop(includeManual: true, focus: false) }
    }

    func moveProjects(from offsets: IndexSet, to destination: Int) {
        guard offsets.allSatisfy({ document.projects.indices.contains($0) }),
              (0...document.projects.count).contains(destination) else { return }
        perform { try commit { $0.projects.move(fromOffsets: offsets, toOffset: destination) } }
    }

    /// Close the terminal, not its saved task definition. Keep ownership until the shell exits.
    func closeTab(_ taskID: UUID, projectID: UUID, confirmed: Bool = false) throws {
        guard let project = document.projects.first(where: { $0.id == projectID }),
              let task = project.tasks.first(where: { $0.id == taskID }) else { return }
        guard !task.pinned else { throw WorkspaceError("Unpin this task before closing its tab.") }
        let terminal = session(taskID)
        guard confirmed || !(terminal?.phase.isActive == true || terminal?.manualCommandRunning == true || terminal?.hasPendingInput == true) else {
            throw WorkspaceError("Confirm closing this busy terminal first.")
        }
        let remaining = visibleTasks(in: project).filter { $0.id != taskID }
        try commit { document in
            guard let index = document.projects.firstIndex(where: { $0.id == projectID }) else { return }
            if document.projects[index].selectedTaskID == taskID {
                document.projects[index].selectedTaskID = project.split?.taskID ?? remaining.first?.id
                document.projects[index].split = nil
            } else if project.split?.taskID == taskID {
                document.projects[index].split = nil
            }
            if task.temporary { document.projects[index].tasks.removeAll { $0.id == taskID } }
        }
        stopAssociatedTunnels(taskID, projectID: projectID)
        openTabIDs.remove(taskID)
        if let terminal, terminal.shellPID > 0 {
            closingTabIDs.insert(taskID)
            terminal.onShellExit = { [weak self, weak terminal] in
                self?.sessions.removeAll { $0 === terminal }
                self?.closingTabIDs.remove(taskID)
            }
            terminal.terminate()
        } else { sessions.removeAll { $0.id == taskID } }
    }
    func runningCount(in project: Project) -> Int {
        project.tasks.filter { $0.participatesInStatus && session($0.id)?.phase == .running }.count
    }
    func status(of project: Project) -> ProjectStatus {
        ProjectStatus.compute(tasks: project.tasks, running: Set(sessions.filter { $0.phase == .running }.map(\.id)))
    }

    /// Surfaces errors without hiding or replacing the saved workspace.
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    func blockWrites(_ message: String) { isReadOnly = true; errorMessage = message }

    func selectProject(_ id: UUID?) {
        perform {
            try commit { $0.selectedProjectID = id }
            if let project = selectedProject, let taskID = project.selectedTaskID {
                try openTask(taskID, projectID: project.id)
            }
        }
    }

    @discardableResult
    func addProject(name: String, directory: String, iconName: String? = nil) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WorkspaceError("Enter a project name.") }
        let url = URL(fileURLWithPath: directory).resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard directory.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceError("Choose an existing project folder.")
        }
        guard !document.projects.contains(where: { $0.directory == url.path }) else {
            throw WorkspaceError("This folder is already a project.")
        }
        let project = Project(name: name, directory: url.path, iconName: iconName)
        try commit { $0.projects.append(project); $0.selectedProjectID = project.id }
        return project.id
    }

    func updateProject(_ project: Project, replacing original: Project? = nil) throws {
        guard let previous = document.projects.first(where: { $0.id == project.id }) else {
            throw WorkspaceError("This project was removed. Cancel the editor and choose a project.")
        }
        if let original {
            guard previous.name == original.name, previous.directory == original.directory,
                  previous.iconName == original.iconName else {
                throw WorkspaceError("This project changed while you were editing. Cancel and reopen it to load the latest version.")
            }
        }
        guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError("Enter a project name.") }
        var updated = project
        if previous.directory != project.directory {
            var isDirectory: ObjCBool = false
            let url = URL(fileURLWithPath: project.directory).resolvingSymlinksInPath().standardizedFileURL
            guard project.directory.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw WorkspaceError("Choose an existing absolute project folder.")
            }
            guard !document.projects.contains(where: { $0.id != project.id && $0.directory == url.path }) else {
                throw WorkspaceError("This folder is already a project.")
            }
            updated.directory = url.path
        }
        let folderChanged = previous.directory != updated.directory
        let owned = sessions.filter { $0.projectID == project.id }
        if folderChanged {
            guard owned.allSatisfy({ $0.canStart && ($0.shellPID == 0 || $0.shellReady) }) else {
                throw WorkspaceError("Stop this project's tasks and tunnels, and finish or clear terminal input before changing its folder. Wait for its shells to become idle.")
            }
        }
        try commit { document in
            guard let index = document.projects.firstIndex(where: { $0.id == project.id }) else { return }
            document.projects[index].name = updated.name
            document.projects[index].directory = updated.directory
            document.projects[index].iconName = updated.iconName
        }
        // Keep surfaces/output, but discard cwd and environment from the old folder.
        // New starts wait for shell exit before opening a fresh shell in the new folder.
        if folderChanged {
            listeningPorts.removeValue(forKey: project.id)
            owned.forEach { $0.resetIdleShell() }
        }
    }

    func removeProject(_ id: UUID) throws {
        let owned = sessions.filter { $0.projectID == id }
        guard !owned.contains(where: { $0.phase.isActive || $0.manualCommandRunning }) else {
            throw WorkspaceError("Stop this project's tasks and terminal commands before removing it.")
        }
        try commit {
            $0.projects.removeAll { $0.id == id }
            if $0.selectedProjectID == id { $0.selectedProjectID = $0.projects.first?.id }
        }
        owned.forEach { $0.terminate() }
        // Keep terminating shells mounted until exit; their views have no selected project.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.sessions.removeAll { $0.projectID == id && $0.shellPID == 0 }
        }
    }

    /// Editor saves are conditional on the snapshot shown when editing began.
    func saveTask(_ task: ProjectTask, projectID: UUID, replacing original: ProjectTask?) throws {
        guard let project = document.projects.first(where: { $0.id == projectID }) else {
            throw WorkspaceError("This project was removed while you were editing. Cancel this editor and choose a project.")
        }
        let current = project.tasks.first { $0.id == task.id }
        if let original {
            guard current != nil else {
                throw WorkspaceError("This task was removed while you were editing. Cancel this editor; add a new task if you want to recreate it.")
            }
            guard current == original else {
                throw WorkspaceError("This task changed while you were editing. Cancel and reopen it to load the latest version before making your changes.")
            }
        } else if current != nil {
            throw WorkspaceError("This task already exists. Cancel and reopen it before editing.")
        }
        try saveTask(task, projectID: projectID)
    }

    func saveTask(_ task: ProjectTask, projectID: UUID) throws {
        var task = task
        task.definition = try task.definition.validated()
        let address = try LocalAddress.validate(task.localURL ?? "")
        task.localURL = address.isEmpty ? nil : address
        if task.definition.kind == .oneOff || task.temporary || task.isTunnel { task.pinned = false }
        if let project = document.projects.first(where: { $0.id == projectID }),
           let previous = project.tasks.first(where: { $0.id == task.id }), previous.localURL != task.localURL,
           project.tasks.contains(where: { $0.tunnelForTaskID == task.id && session($0.id)?.phase.isActive == true }) {
            throw WorkspaceError("Stop this task's tunnel before changing its URL.")
        }
        try commit { document in
            guard let project = document.projects.firstIndex(where: { $0.id == projectID }) else { return }
            if let index = document.projects[project].tasks.firstIndex(where: { $0.id == task.id }) {
                document.projects[project].tasks[index] = task
            } else { document.projects[project].tasks.append(task) }
            if document.projects[project].selectedTaskID == nil { document.projects[project].selectedTaskID = task.id }
        }
        recordRunningPinnedTasks()
    }

    func togglePin(_ task: ProjectTask, projectID: UUID) throws {
        guard !task.temporary else { throw WorkspaceError("Turn off Temporary before pinning this task.") }
        var updated = task
        updated.pinned.toggle()
        if updated.pinned { updated.definition.kind = .service }
        try saveTask(updated, projectID: projectID)
    }

    func importTasks(_ tasks: [ProjectTask], projectID: UUID) throws {
        try commit { document in
            guard let index = document.projects.firstIndex(where: { $0.id == projectID }) else { return }
            let existing = Set(document.projects[index].tasks.compactMap(\.sourceKey))
            document.projects[index].tasks += tasks.filter { $0.sourceKey.map { !existing.contains($0) } ?? true }
        }
    }

    func openTask(_ taskID: UUID, projectID: UUID) throws {
        guard !closingTabIDs.contains(taskID) else { throw WorkspaceError("This terminal is still closing. Try again when it has stopped.") }
        guard let project = document.projects.first(where: { $0.id == projectID }),
              project.tasks.contains(where: { $0.id == taskID }) else { return }
        try commit { document in
            document.selectedProjectID = projectID
            if let index = document.projects.firstIndex(where: { $0.id == projectID }) {
                if document.projects[index].split?.taskID == taskID,
                   let previous = document.projects[index].selectedTaskID, previous != taskID {
                    document.projects[index].split?.taskID = previous
                }
                document.projects[index].selectedTaskID = taskID
            }
        }
        // Selecting an unstarted task does not execute a shell or project command.
        openTabIDs.insert(taskID)
        session(taskID)?.terminal.requestFocus()
    }

    func startTask(_ taskID: UUID, projectID: UUID, activate: Bool = true) throws {
        guard !closingTabIDs.contains(taskID) else { throw WorkspaceError("This terminal is still closing. Try again when it has stopped.") }
        guard !isReadOnly else { throw WorkspaceError("This workspace is read-only. Resolve its startup error before running tasks.") }
        guard let project = document.projects.first(where: { $0.id == projectID }),
              let task = project.tasks.first(where: { $0.id == taskID }) else { return }
        if activate { try openTask(taskID, projectID: projectID) }
        let terminal: TaskSession
        if let existing = session(taskID) { terminal = existing }
        else {
            terminal = TaskSession(taskID: taskID, projectID: projectID, dataDirectory: persistence.directory)
            sessions.append(terminal)
            terminal.onRemoteURL = { [weak self] url in
                self?.completeTunnelCopy(taskID, url: url)
            }
            terminal.onPhaseChange = { [weak self] in
                self?.recordRunningPinnedTasks()
                self?.taskPhaseChanged(taskID, projectID: projectID)
            }
        }
        var resolved = task
        resolved.definition.environment = task.definition.environment.mapValues { $0.replacingOccurrences(of: "${workspaceFolder}", with: project.directory) }
        try terminal.start(task: resolved, directory: project.workingDirectory(for: task).path, focus: activate)
    }

    func runAll(in project: Project) {
        for task in project.tasks where task.participatesInStatus {
            perform { try startTask(task.id, projectID: project.id) }
        }
    }

    var hasRunningTasks: Bool { sessions.contains { $0.phase.isActive || $0.manualCommandRunning } }
    func stopAll() { sessions.forEach { $0.stop(includeManual: true, focus: false) } }
    func terminateAll() { sessions.forEach { $0.terminate() } }

    /// Freeze the last running set before shutdown changes sessions to stopping/exited.
    func prepareToQuit() {
        recordRunningPinnedTasks()
        preservingResumeState = true
    }

    func cancelQuit() {
        preservingResumeState = false
        recordRunningPinnedTasks()
    }

    /// Called only after acquiring the workspace's exclusive control lock.
    func resumePinnedTasks() {
        guard !isReadOnly else { return }
        // Initialization may predate another owner's final write. Re-read only once
        // this app owns the control lock, before any startup cleanup or task launch.
        do { document = try persistence.load() }
        catch {
            blockWrites("Couldn't reload the saved workspace. Nothing has been overwritten. \(error.localizedDescription)")
            return
        }
        let saved = document.runningPinnedTaskIDs ?? []
        do {
            // This one startup checkpoint also persists a v1 migration and its backup,
            // even when cleanup leaves the decoded document logically unchanged.
            try commit(forceSave: true) {
                $0.runningPinnedTaskIDs = []
                for index in $0.projects.indices {
                    $0.projects[index].tasks.removeAll { $0.temporary }
                    let ids = Set($0.projects[index].tasks.map(\.id))
                    if let selected = $0.projects[index].selectedTaskID, !ids.contains(selected) {
                        $0.projects[index].selectedTaskID = $0.projects[index].tasks.first?.id
                    }
                    if let split = $0.projects[index].split,
                       !ids.contains(split.taskID) || split.taskID == $0.projects[index].selectedTaskID { $0.projects[index].split = nil }
                }
            }
        }
        catch { errorMessage = error.localizedDescription; return }
        guard resumeTasksOnLaunch else { return }
        for project in document.projects {
            for task in project.tasks where task.participatesInStatus && saved.contains(task.id) {
                perform { try startTask(task.id, projectID: project.id, activate: false) }
            }
        }
    }

    private func recordRunningPinnedTasks() {
        guard !preservingResumeState, !isReadOnly else { return }
        let eligible = Set(document.projects.flatMap(\.tasks).filter(\.participatesInStatus).map(\.id))
        let running = resumeTasksOnLaunch ? Set(sessions.filter { $0.phase == .running }.map(\.id)).intersection(eligible) : []
        guard running != document.runningPinnedTaskIDs ?? [] else { return }
        perform { try commit { $0.runningPinnedTaskIDs = running } }
    }

    func setSplit(projectID: UUID, taskID: UUID?, axis: PaneAxis = .sideBySide) throws {
        guard let project = document.projects.first(where: { $0.id == projectID }) else { throw WorkspaceError("Project not found.") }
        if let taskID {
            guard !closingTabIDs.contains(taskID) else { throw WorkspaceError("This terminal is still closing.") }
            guard project.tasks.contains(where: { $0.id == taskID }), taskID != project.selectedTaskID else {
                throw WorkspaceError("Choose a different task for the second pane.")
            }
        }
        try commit { document in
            guard let index = document.projects.firstIndex(where: { $0.id == projectID }) else { return }
            document.projects[index].split = taskID.map { PaneSplit(taskID: $0, axis: axis) }
        }
    }

    func saveSplitRatio(_ ratio: Double, projectID: UUID, axis: PaneAxis) {
        guard ratio.isFinite, let project = document.projects.first(where: { $0.id == projectID }),
              let split = project.split, split.axis == axis, abs(split.ratio - ratio) > 0.01 else { return }
        perform {
            try commit { document in
                guard let index = document.projects.firstIndex(where: { $0.id == projectID }) else { return }
                document.projects[index].split?.ratio = min(0.85, max(0.15, ratio))
            }
        }
    }

    private func commit(forceSave: Bool = false, _ update: (inout WorkspaceDocument) -> Void) throws {
        guard !isReadOnly else { throw WorkspaceError("The saved workspace couldn't be read. Resolve that error before making changes.") }
        var next = document
        update(&next)
        guard forceSave || next != document else { return }
        try persistence.save(next)
        document = next
    }
}
