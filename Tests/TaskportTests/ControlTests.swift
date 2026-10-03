import Foundation
import Testing
import TaskportControl
@testable import Taskport

struct ControlTests {
    @Test @MainActor func lockTransferReloadsTheLatestWorkspaceBeforeStartupWrites() throws {
        let directory = testDirectory("unused").deletingLastPathComponent()
            .appendingPathComponent("c-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = WorkspaceStore(directory: directory)
        let firstServer = ControlServer(directory: directory)
        try firstServer.start { _ in ControlResponse() }
        defer { firstServer.stop() }
        let projectID = try first.addProject(name: "Before", directory: directory.path)
        let waiting = WorkspaceStore(directory: directory)
        #expect(waiting.selectedProject?.name == "Before")
        var project = try #require(first.selectedProject)
        project.name = "Latest"
        try first.updateProject(project)
        let task = ProjectTask(definition: TaskDefinition(name: "New task", command: "true"))
        try first.saveTask(task, projectID: projectID)
        firstServer.stop()
        let nextServer = ControlServer(directory: directory)
        try nextServer.start { _ in ControlResponse() }
        defer { nextServer.stop() }
        waiting.resumePinnedTasks()
        #expect(waiting.selectedProject?.name == "Latest")
        #expect(waiting.selectedProject?.tasks == [task])
        #expect(try waiting.persistence.load() == waiting.document)

        // Never replace a file that became malformed before ownership transferred.
        let corruptWaiting = WorkspaceStore(directory: directory)
        try Data("broken".utf8).write(to: first.persistence.file)
        corruptWaiting.resumePinnedTasks()
        #expect(corruptWaiting.isReadOnly)
        #expect(try Data(contentsOf: first.persistence.file) == Data("broken".utf8))
    }

    @Test func argumentParsingAndSelection() throws {
        let project = UUID(), first = UUID(), second = UUID()
        let request = try CLIArguments.parse(["tasks", "start", project.uuidString, first.uuidString, second.uuidString])
        #expect(request.projectID == project)
        #expect(request.taskIDs == [first, second])
        #expect(try CLIArguments.parse(["sessions", "list", "--all"]).flags == ["all"])
        #expect(throws: (any Error).self) { try CLIArguments.parse(["projects", "list", "extra"]) }
        #expect(throws: (any Error).self) { try CLIArguments.parse(["tasks", "edit", project.uuidString]) }
    }

    @Test @MainActor func definitionsOverrideAndInvalidBatch() throws {
        let directory = testDirectory("control-model")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let control = WorkspaceControl(store: store)
        let add = control.handle(.init(operation: "projects.add", values: ["name": "Example", "directory": directory.path]))
        let project = try #require(add.projectID)
        let taskAdd = control.handle(.init(operation: "tasks.add", projectID: project,
            values: ["name": "Web", "command": "sleep 30", "kind": "service", "pinned": "true"]))
        let task = try #require(taskAdd.taskID)
        #expect(store.sessions.isEmpty)
        #expect(control.handle(.init(operation: "tasks.start", projectID: project, taskIDs: [task, UUID()])).ok == false)
        #expect(store.sessions.isEmpty)
        #expect(control.handle(.init(operation: "tasks.start", projectID: project, taskIDs: [task], flags: ["all"])).ok == false)
        #expect(control.handle(.init(operation: "projects.edit", projectID: project, values: ["name": "Renamed"])).ok)
        let definition = TaskDefinition(name: "Imported", command: "true", kind: .oneOff)
        let imported = ProjectTask(definition: definition, importedDefinition: definition)
        try store.saveTask(imported, projectID: project)
        let pin = ControlRequest(operation: "tasks.edit", projectID: project, taskIDs: [imported.id], values: ["pinned": "true"])
        #expect(control.handle(pin).ok)
        let pinned = try #require(store.selectedProject?.tasks.first { $0.id == imported.id })
        #expect(pinned.participatesInStatus)
        #expect(!pinned.isOverridden)
        #expect(pinned.importedDefinition == definition)
        try store.togglePin(pinned, projectID: project)
        #expect(store.selectedProject?.tasks.first { $0.id == imported.id }?.pinned == false)
        let edit = ControlRequest(operation: "tasks.edit", projectID: project, taskIDs: [imported.id], values: ["name": "Local"])
        #expect(!control.handle(edit).ok)
        var confirmed = edit; confirmed.flags = ["confirm-local-override"]
        #expect(control.handle(confirmed).ok)
        let tasks = try #require(control.handle(.init(operation: "tasks.list", projectID: project)).tasks)
        #expect(tasks.first { $0.id == imported.id }?.localOverride == true)
        #expect(tasks.first { $0.id == task }?.phase == "stopped")
        #expect(control.handle(.init(operation: "sessions.list")).tasks?.isEmpty == true)
        #expect(try store.persistence.load() == store.document)
    }

    @Test @MainActor func privateSocketRoundTripAndExclusiveLock() async throws {
        let directory = testDirectory("unused").deletingLastPathComponent().appendingPathComponent("c-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = ControlServer(directory: directory)
        try server.start { request in request.operation == "status" ? ControlResponse() : .failure("Unknown") }
        defer { server.stop() }
        let other = ControlServer(directory: directory)
        #expect(throws: (any Error).self) { try other.start { _ in ControlResponse() } }
        let result = try await Task.detached { try LocalSocket.request(.init(operation: "status"), directory: directory) }.value
        #expect(result.ok)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("control.sock").path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        let result2 = try await Task.detached { try LocalSocket.request(.init(operation: "unknown"), directory: directory) }.value
        #expect(!result2.ok)
    }

    @Test @MainActor func splitSelectionAndPersistence() throws {
        let directory = testDirectory("split")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory.appendingPathComponent("data"))
        let project = try store.addProject(name: "Panes", directory: directory.path)
        let first = ProjectTask(definition: TaskDefinition(name: "Web", command: "true"))
        let second = ProjectTask(definition: TaskDefinition(name: "API", command: "true"))
        try store.saveTask(first, projectID: project); try store.saveTask(second, projectID: project)
        try store.setSplit(projectID: project, taskID: second.id)
        try store.openTask(second.id, projectID: project)
        #expect(store.selectedTaskID == second.id)
        #expect(store.selectedProject?.split?.taskID == first.id)
        store.saveSplitRatio(0.6, projectID: project, axis: .sideBySide)
        #expect(try store.persistence.load().projects.first?.split?.ratio == 0.6)
        #expect(store.sessions.isEmpty)
        #expect(throws: (any Error).self) { try store.setSplit(projectID: project, taskID: second.id) }
        try store.setSplit(projectID: project, taskID: nil)
        #expect(store.selectedProject?.split == nil)
    }
}
