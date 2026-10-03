import Foundation
import Testing
import TaskportControl
@testable import Taskport

@MainActor struct ProjectDirectoryTests {
    @Test func folderChangePreservesDefinitionsAndResolvesRelativePaths() throws {
        let root = testDirectory("project-folder")
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        for folder in [old, new] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"scripts":{"new-task":"true"}}"#.utf8).write(to: new.appendingPathComponent("package.json"))
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let id = try store.addProject(name: "Example", directory: old.path, iconName: "hammer")
        let definition = TaskDefinition(name: "Web", command: "true", directory: "web")
        var imported = ProjectTask(definition: definition, pinned: true, source: ".vscode/tasks.json",
            sourceKey: "vscode:Web", importedDefinition: definition, localURL: "http://localhost:4321")
        imported.definition.command = "printf 'local override'"
        let absolute = ProjectTask(definition: TaskDefinition(name: "Absolute", command: "true", directory: old.path))
        let variable = ProjectTask(definition: TaskDefinition(name: "API", command: "true", directory: "${workspaceFolder}/api"))
        for task in [imported, absolute, variable] { try store.saveTask(task, projectID: id) }
        try store.setSplit(projectID: id, taskID: variable.id)
        let original = try #require(store.selectedProject)
        var edited = original
        edited.directory = new.path
        try store.updateProject(edited, replacing: original)
        let saved = try #require(store.selectedProject)
        #expect(saved == edited)
        #expect(saved.tasks == original.tasks)
        #expect(saved.tasks[0].isOverridden)
        #expect(saved.workingDirectory(for: imported).path == new.appendingPathComponent("web").path)
        #expect(saved.workingDirectory(for: variable).path == new.appendingPathComponent("api").path)
        #expect(saved.workingDirectory(for: absolute).path == old.path)
        #expect(try store.persistence.load() == store.document)
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("package.json").path))
        #expect(store.sessions.isEmpty)
    }

    @Test func invalidAndDuplicateFoldersDoNotChangeTheProject() throws {
        let root = testDirectory("project-folder-validation")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let id = try store.addProject(name: "Example", directory: root.path)
        _ = try store.addProject(name: "Other", directory: store.persistence.directory.path)
        let original = try #require(store.document.projects.first { $0.id == id })
        let file = root.appendingPathComponent("file")
        try Data().write(to: file)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: store.persistence.directory)
        for path in ["relative", root.appendingPathComponent("missing").path, file.path, alias.path, ""] {
            var edited = original
            edited.directory = path
            edited.name = "Should not save"
            #expect(throws: WorkspaceError.self) { try store.updateProject(edited) }
            #expect(store.document.projects.first { $0.id == id } == original)
            #expect(try store.persistence.load() == store.document)
        }
    }

    @Test func editorRejectsConcurrentFolderChangesButPreservesNewTasks() throws {
        let root = testDirectory("project-folder-conflict")
        let new = root.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let id = try store.addProject(name: "Example", directory: root.path)
        let original = try #require(store.selectedProject)
        let task = ProjectTask(definition: TaskDefinition(name: "Added via CLI", command: "true"))
        try store.saveTask(task, projectID: id)
        var edited = original
        edited.directory = new.path
        try store.updateProject(edited, replacing: original)
        #expect(store.selectedProject?.tasks == [task])
        edited.directory = original.directory
        edited.name = "Stale editor"
        #expect(throws: WorkspaceError.self) { try store.updateProject(edited, replacing: original) }
        #expect(store.selectedProject?.directory == new.path)
        #expect(store.selectedProject?.name == original.name)
        try store.removeProject(id)
        #expect(throws: WorkspaceError.self) { try store.updateProject(edited, replacing: original) }
        #expect(store.document.projects.isEmpty)
    }

    @Test func cliFolderChangePersistsAndDoesNotRunCommands() throws {
        let root = testDirectory("project-folder-cli")
        let new = root.appendingPathComponent("new folder")
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let id = try store.addProject(name: "Example", directory: root.path)
        let control = WorkspaceControl(store: store)
        let request = try CLIArguments.parse(["projects", "edit", id.uuidString, "--directory", new.path])
        #expect(control.handle(request).ok)
        #expect(store.selectedProject?.id == id)
        #expect(store.selectedProject?.directory == new.path)
        #expect(store.sessions.isEmpty)
        #expect(try store.persistence.load() == store.document)
    }

    @Test func busyShellsBlockChangesAndIdleShellsResetBeforeRestart() async throws {
        let root = testDirectory("project-folder-shell")
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        for folder in [old, new] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let id = try store.addProject(name: "Example", directory: old.path)
        var task = ProjectTask(definition: TaskDefinition(name: "Pinned", command: "sleep 60",
            environment: ["TASKPORT_FOLDER_TEST": "old"]), pinned: true)
        try store.saveTask(task, projectID: id)
        defer { store.terminateAll() }
        try store.startTask(task.id, projectID: id, activate: false)
        let session = try #require(store.session(task.id))
        let original = try #require(store.selectedProject)
        var edited = original
        edited.directory = new.path
        #expect(throws: WorkspaceError.self) { try store.updateProject(edited) }
        try await waitUntil { session.phase == .running }
        let oldPID = session.shellPID
        let control = WorkspaceControl(store: store)
        let change = ControlRequest(operation: "projects.edit", projectID: id, values: ["directory": new.path])
        #expect(!control.handle(change).ok)
        #expect(session.shellPID == oldPID)
        #expect(session.phase == .running)
        #expect(store.selectedProject?.directory == old.path)
        store.stopTask(task.id, projectID: id)
        #expect(!control.handle(change).ok)
        try await waitUntil { session.canStart && session.shellReady }
        #expect(control.handle(change).ok)
        #expect(!session.canStart)
        #expect(throws: WorkspaceError.self) { try store.startTask(task.id, projectID: id, activate: false) }
        try await waitUntil { session.shellPID == 0 }
        #expect(session.canStart)
        #expect(store.session(task.id) === session)
        #expect(store.visibleTasks(in: try #require(store.selectedProject)).contains { $0.id == task.id })
        task.definition.command = "printf '%s\\n%s\\n' \"$PWD\" \"${TASKPORT_FOLDER_TEST-unset}\" > result.txt"
        task.definition.environment = [:]
        try store.saveTask(task, projectID: id)
        try store.startTask(task.id, projectID: id, activate: false)
        try await waitUntil { session.phase == .exited(0) && session.shellReady }
        #expect(try String(contentsOf: new.appendingPathComponent("result.txt"), encoding: .utf8) == new.path + "\nunset\n")
        #expect(!FileManager.default.fileExists(atPath: old.appendingPathComponent("result.txt").path))
        store.terminateAll()
        try await waitUntil { store.openShellCount == 0 }
    }

    @Test func resettingFailedTemporaryShellPreservesFailureAndDefinition() async throws {
        let root = testDirectory("project-folder-failure")
        let new = root.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(directory: root.appendingPathComponent("data"))
        let id = try store.addProject(name: "Example", directory: root.path)
        let failed = ProjectTask(definition: TaskDefinition(name: "Failed experiment", command: "false"), temporary: true)
        try store.saveTask(failed, projectID: id)
        defer { store.terminateAll() }
        try store.startTask(failed.id, projectID: id, activate: false)
        let session = try #require(store.session(failed.id))
        try await waitUntil { session.phase == .exited(1) && session.shellReady }
        // Queue cleanup and change folders in the same actor turn, before it can run.
        store.taskPhaseChanged(failed.id, projectID: id)
        var project = try #require(store.selectedProject)
        project.directory = new.path
        try store.updateProject(project)
        #expect(!session.stopWasRequested)
        try await waitUntil { session.shellPID == 0 }
        await Task.yield()
        #expect(session.phase == .exited(1))
        #expect(store.selectedProject?.tasks == [failed])
        #expect(store.session(failed.id) === session)
        #expect(try store.persistence.load().projects.first?.tasks == [failed])
        store.stopTask(failed.id, projectID: id)
        #expect(store.selectedProject?.tasks.isEmpty == true)
        #expect(store.session(failed.id) == nil)
    }
}
